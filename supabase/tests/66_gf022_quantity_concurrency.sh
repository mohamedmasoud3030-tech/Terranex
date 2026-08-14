#!/usr/bin/env bash
set -euo pipefail

# GF-022 / Livestock derived-quantity concurrency.
#
# Real multi-session races prove that the derived headcount cannot be
# over-consumed by simultaneous commands. Nothing here depends on a disabled
# UI button: every guard is a database guard.
#
# Race 1 — mortality: current = 10, session A kills 7, session B kills 6.
#          Both cannot succeed (7 + 6 = 13 > 10).
# Race 2 — split:     current = 100, session A splits 70, session B splits 50.
#          Both cannot succeed (70 + 50 = 120 > 100).
# Race 3 — merge vs mortality on a shared source: the two commands serialize
#          and the source can never be overdrawn.
#
# The protection is a per-Cohort advisory transaction lock taken by every
# quantity command before it reads the derived balance, plus a deferred
# non-negative constraint trigger as a last-resort backstop.

DB="${TERRANEX_TEST_DB:-terranex_test}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
export PGPASSWORD
CONTAINER="${TERRANEX_DB_CONTAINER:-}"

psql_sql() {
  local sql="$1"
  if [[ -n "$CONTAINER" ]]; then
    printf '%s\n' "$sql" | docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -q -U "$PGUSER" -d "$DB"
  else
    printf '%s\n' "$sql" | psql -v ON_ERROR_STOP=1 -q -d "$DB"
  fi
}

psql_value() {
  local sql="$1"
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -Atq -U "$PGUSER" -d "$DB" -c "$sql"
  else
    psql -v ON_ERROR_STOP=1 -Atq -d "$DB" -c "$sql"
  fi
}

run_session() {
  local sql="$1" log="$2"
  if psql_sql "$sql" >"$log" 2>&1; then return 0; fi
  return 1
}

ORG='10000000-0000-4000-8000-000000000001'
ACTOR='00000000-0000-4000-8000-000000000001'
AUTH="set request.jwt.claim.sub='$ACTOR'; set role authenticated;"

PROJECT="$(psql_value "select id from public.investment_projects where organization_id='$ORG' and internal_reference='GF020-LS-A' limit 1")"
HERD="$(psql_value "select id from public.livestock_herds where organization_id='$ORG' and project_id='$PROJECT' and internal_reference='HERD-A' limit 1")"
SITE="$(psql_value "select id from public.livestock_sites where organization_id='$ORG' and project_id='$PROJECT' and internal_reference='SITE-A' limit 1")"
if [[ -z "$PROJECT" || -z "$HERD" || -z "$SITE" ]]; then
  echo 'ERROR: GF-022 concurrency prerequisites missing.' >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

provision_cohort() {
  local reference="$1" headcount="$2" key="$3" id
  id="$(psql_value "select id from public.livestock_cohorts where organization_id='$ORG' and project_id='$PROJECT' and cohort_reference='$reference' limit 1")"
  if [[ -z "$id" ]]; then
    psql_sql "$AUTH select public.create_livestock_cohort('$ORG','$PROJECT','$HERD','$SITE','$reference','PURCHASED',date '2026-08-01',$headcount,null,null,null,null,null,null,null,'$key');" >/dev/null
    id="$(psql_value "select id from public.livestock_cohorts where organization_id='$ORG' and project_id='$PROJECT' and cohort_reference='$reference' limit 1")"
    psql_sql "$AUTH select public.transition_livestock_cohort('$ORG','$PROJECT','$id','PLANNED','ACTIVE','تفعيل دفعة السباق',null,'$key-act');" >/dev/null
  fi
  if [[ -z "$id" ]]; then
    echo "ERROR: could not provision cohort $reference" >&2
    exit 1
  fi
  printf '%s' "$id"
}

quantity_of() {
  psql_value "select current_quantity from public.livestock_cohort_quantity_rollforward where cohort_id='$1'"
}

# ---------------------------------------------------------------------------
# Race 1 — two concurrent mortality commands cannot both consume the herd.
# ---------------------------------------------------------------------------
MORT="$(provision_cohort 'دفعة سباق النفوق' 10 'gf22-race-mort')"
[[ "$(quantity_of "$MORT")" == '10' ]] || {
  echo "ERROR: mortality race cohort did not start at 10 (got $(quantity_of "$MORT"))." >&2
  exit 1
}

KILL_7="$AUTH
select public.record_livestock_mortality('$ORG','$PROJECT','$MORT',7,now(),'DISEASE',null,null,null,'gf22-race-mort-7');"
KILL_6="$AUTH
select public.record_livestock_mortality('$ORG','$PROJECT','$MORT',6,now(),'INJURY',null,null,null,'gf22-race-mort-6');"

set +e
run_session "$KILL_7" "$tmpdir/m7.log" & pid_a=$!
run_session "$KILL_6" "$tmpdir/m6.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: concurrent mortality expected exactly one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/m7.log" "$tmpdir/m6.log" >&2 || true
  exit 1
fi
if [[ "$status_a" -ne 0 ]]; then LOSER="$tmpdir/m7.log"; else LOSER="$tmpdir/m6.log"; fi
if ! grep -Eq 'exceeds the current derived quantity|as-of quantity cannot go below zero' "$LOSER"; then
  echo 'ERROR: the losing mortality did not fail on the derived-quantity ceiling.' >&2
  cat "$LOSER" >&2
  exit 1
fi
AFTER_MORT="$(quantity_of "$MORT")"
if [[ "$AFTER_MORT" != '3' && "$AFTER_MORT" != '4' ]]; then
  echo "ERROR: mortality race left an invalid balance: $AFTER_MORT" >&2
  exit 1
fi
EVENTS="$(psql_value "select count(*) from public.livestock_quantity_events where cohort_id='$MORT' and event_type='MORTALITY'")"
if [[ "$EVENTS" != '1' ]]; then
  echo "ERROR: mortality race wrote $EVENTS events; exactly 1 is allowed." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Race 2 — two concurrent splits cannot both draw from the same source.
# ---------------------------------------------------------------------------
SPLIT_SRC="$(provision_cohort 'دفعة سباق التقسيم' 100 'gf22-race-split')"
[[ "$(quantity_of "$SPLIT_SRC")" == '100' ]] || {
  echo "ERROR: split race cohort did not start at 100." >&2
  exit 1
}

SPLIT_70="$AUTH
select public.split_livestock_cohort('$ORG','$PROJECT','$SPLIT_SRC',70,now(),'ناتج سباق التقسيم ٧٠','$HERD','$SITE',null,null,'سباق تقسيم ٧٠',null,null,'gf22-race-split-70');"
SPLIT_50="$AUTH
select public.split_livestock_cohort('$ORG','$PROJECT','$SPLIT_SRC',50,now(),'ناتج سباق التقسيم ٥٠','$HERD','$SITE',null,null,'سباق تقسيم ٥٠',null,null,'gf22-race-split-50');"

set +e
run_session "$SPLIT_70" "$tmpdir/s70.log" & pid_c=$!
run_session "$SPLIT_50" "$tmpdir/s50.log" & pid_d=$!
wait "$pid_c"; status_c=$?
wait "$pid_d"; status_d=$?
set -e

if ! { [[ "$status_c" -eq 0 && "$status_d" -ne 0 ]] || [[ "$status_c" -ne 0 && "$status_d" -eq 0 ]]; }; then
  echo "ERROR: concurrent splits expected exactly one success; A=$status_c B=$status_d" >&2
  cat "$tmpdir/s70.log" "$tmpdir/s50.log" >&2 || true
  exit 1
fi
if [[ "$status_c" -ne 0 ]]; then SLOSER="$tmpdir/s70.log"; else SLOSER="$tmpdir/s50.log"; fi
if ! grep -Eq 'exceeds the current derived quantity|as-of quantity cannot go below zero' "$SLOSER"; then
  echo 'ERROR: the losing split did not fail on the derived-quantity ceiling.' >&2
  cat "$SLOSER" >&2
  exit 1
fi

AFTER_SPLIT="$(quantity_of "$SPLIT_SRC")"
if [[ "$AFTER_SPLIT" != '30' && "$AFTER_SPLIT" != '50' ]]; then
  echo "ERROR: split race left an invalid source balance: $AFTER_SPLIT" >&2
  exit 1
fi

# The losing split must have created NO destination Cohort and NO half operation.
DEST_COUNT="$(psql_value "select count(*) from public.livestock_cohorts where organization_id='$ORG' and project_id='$PROJECT' and cohort_reference in ('ناتج سباق التقسيم ٧٠','ناتج سباق التقسيم ٥٠')")"
if [[ "$DEST_COUNT" != '1' ]]; then
  echo "ERROR: the split race created $DEST_COUNT destination cohorts; exactly 1 is allowed." >&2
  exit 1
fi
OP_COUNT="$(psql_value "select count(*) from public.livestock_quantity_operations o join public.livestock_cohort_lineage l on l.operation_id=o.id where l.source_cohort_id='$SPLIT_SRC'")"
if [[ "$OP_COUNT" != '1' ]]; then
  echo "ERROR: the split race left $OP_COUNT operations against the source; expected 1." >&2
  exit 1
fi

# Conservation still holds exactly across the surviving operation.
CONSERVED="$(psql_value "select bool_and(x.out_qty = x.in_qty) from (
  select o.id,
    sum(case when t.direction=-1 then q.quantity else 0 end) as out_qty,
    sum(case when t.direction=1 then q.quantity else 0 end) as in_qty
  from public.livestock_quantity_operations o
  join public.livestock_quantity_events q on q.operation_id = o.id
  join public.livestock_quantity_event_types t on t.code = q.event_type
  group by o.id) x")"
if [[ "$CONSERVED" != 't' ]]; then
  echo 'ERROR: an operation failed the conservation invariant after the race.' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Race 3 — a merge and a mortality competing for the same source serialize.
# ---------------------------------------------------------------------------
SHARED="$(provision_cohort 'دفعة سباق مشترك' 20 'gf22-race-shared')"
PARTNER="$(provision_cohort 'دفعة سباق شريك' 20 'gf22-race-partner')"

MERGE_ALL="$AUTH
select public.merge_livestock_cohorts('$ORG','$PROJECT',array['$SHARED','$PARTNER']::uuid[],array[20,20]::integer[],now(),'ناتج سباق الدمج','$HERD','$SITE',null,null,'سباق دمج',null,null,'gf22-race-merge');"
KILL_ALL="$AUTH
select public.record_livestock_mortality('$ORG','$PROJECT','$SHARED',20,now(),'WEATHER',null,null,null,'gf22-race-shared-mort');"

set +e
run_session "$MERGE_ALL" "$tmpdir/merge.log" & pid_e=$!
run_session "$KILL_ALL" "$tmpdir/kill.log" & pid_f=$!
wait "$pid_e"; status_e=$?
wait "$pid_f"; status_f=$?
set -e

if ! { [[ "$status_e" -eq 0 && "$status_f" -ne 0 ]] || [[ "$status_e" -ne 0 && "$status_f" -eq 0 ]]; }; then
  echo "ERROR: merge/mortality race expected exactly one success; merge=$status_e mortality=$status_f" >&2
  cat "$tmpdir/merge.log" "$tmpdir/kill.log" >&2 || true
  exit 1
fi

SHARED_AFTER="$(quantity_of "$SHARED")"
if [[ "$SHARED_AFTER" != '0' ]]; then
  echo "ERROR: the shared source should be fully consumed exactly once (got $SHARED_AFTER)." >&2
  exit 1
fi

# A zero balance is truthful and does NOT silently mutate the lifecycle.
STATE="$(psql_value "select public.livestock_current_cohort_state('$SHARED')")"
if [[ "$STATE" != 'ACTIVE' ]]; then
  echo "ERROR: reaching zero quantity mutated the lifecycle state to $STATE." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Global invariants after every race.
# ---------------------------------------------------------------------------
NEGATIVE="$(psql_value "select count(*) from public.livestock_cohort_quantity_rollforward where current_quantity < 0")"
if [[ "$NEGATIVE" != '0' ]]; then
  echo "ERROR: $NEGATIVE cohorts hold a negative derived quantity." >&2
  exit 1
fi

INVARIANT="$(psql_value "select bool_and(
  r.current_quantity =
    (case when c.is_operational_as_of_now then r.opening_headcount else 0 end)
    + r.births + r.split_in + r.merge_in
    - r.mortality - r.split_out - r.merge_out)
  from public.livestock_cohort_quantity_rollforward r
  join public.livestock_cohorts_read c on c.id = r.cohort_id")"
if [[ "$INVARIANT" != 't' ]]; then
  echo 'ERROR: the quantity rollforward invariant is violated after the races.' >&2
  exit 1
fi

UNBALANCED="$(psql_value "select count(*) from (
  select o.id,
    sum(case when t.direction=-1 then q.quantity else 0 end) as out_qty,
    sum(case when t.direction=1 then q.quantity else 0 end) as in_qty
  from public.livestock_quantity_operations o
  join public.livestock_quantity_events q on q.operation_id = o.id
  join public.livestock_quantity_event_types t on t.code = q.event_type
  group by o.id) x where x.out_qty <> x.in_qty")"
if [[ "$UNBALANCED" != '0' ]]; then
  echo "ERROR: $UNBALANCED operations do not conserve quantity." >&2
  exit 1
fi

echo 'GF-022 real multi-session quantity concurrency PASS: mortality, split and merge races each admit exactly one winner; conservation and non-negativity hold.'
