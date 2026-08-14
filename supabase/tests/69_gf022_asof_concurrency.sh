#!/usr/bin/env bash
set -euo pipefail

# GF-022 review hardening: real-session proof that a backdated outflow cannot
# borrow a later inflow even after waiting on the same Cohort advisory lock,
# plus COMMIT-time rejection of malformed SPLIT and MERGE operation shapes.

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
  echo 'ERROR: GF-022 hardening concurrency prerequisites missing.' >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

provision_cohort() {
  local reference="$1" headcount="$2" key="$3" id
  id="$(psql_value "select id from public.livestock_cohorts where organization_id='$ORG' and project_id='$PROJECT' and cohort_reference='$reference' limit 1")"
  if [[ -z "$id" ]]; then
    psql_sql "$AUTH select public.create_livestock_cohort('$ORG','$PROJECT','$HERD','$SITE','$reference','PURCHASED',current_date-1,$headcount,null,null,null,null,null,null,null,'$key');" >/dev/null
    id="$(psql_value "select id from public.livestock_cohorts where organization_id='$ORG' and project_id='$PROJECT' and cohort_reference='$reference' limit 1")"
    psql_sql "$AUTH select public.transition_livestock_cohort('$ORG','$PROJECT','$id','PLANNED','ACTIVE','تفعيل اختبار المراجعة',null,'$key-act');" >/dev/null
  fi
  [[ -n "$id" ]] || { echo "ERROR: could not provision $reference" >&2; exit 1; }
  printf '%s' "$id"
}

# ---------------------------------------------------------------------------
# Race: later inflow commits first; backdated outflow waits on the same lock and
# must still evaluate availability at its earlier effective time.
# ---------------------------------------------------------------------------
ASOF="$(provision_cohort 'دفعة سباق الزمن 022' 10 'gf22h-race-asof')"

LATER_INFLOW="begin;
$AUTH
select public.record_livestock_birth('$ORG','$PROJECT','$ASOF',10,now()-interval '1 minute',null,null,'gf22h-race-later-birth');
select pg_sleep(2);
commit;"
BACKDATED_OUTFLOW="$AUTH
select public.record_livestock_mortality('$ORG','$PROJECT','$ASOF',15,now()-interval '2 minutes','UNKNOWN',null,null,null,'gf22h-race-backdated-mortality');"

run_session "$LATER_INFLOW" "$tmpdir/inflow.log" & inflow_pid=$!
sleep 0.35
set +e
run_session "$BACKDATED_OUTFLOW" "$tmpdir/outflow.log"
outflow_status=$?
wait "$inflow_pid"
inflow_status=$?
set -e

if [[ "$inflow_status" -ne 0 ]]; then
  echo 'ERROR: later inflow transaction failed unexpectedly.' >&2
  cat "$tmpdir/inflow.log" >&2 || true
  exit 1
fi
if [[ "$outflow_status" -eq 0 ]]; then
  echo 'ERROR: backdated outflow borrowed a later inflow.' >&2
  exit 1
fi
if ! grep -q 'exceeds quantity as of effective time' "$tmpdir/outflow.log"; then
  echo 'ERROR: backdated outflow failed for the wrong reason.' >&2
  cat "$tmpdir/outflow.log" >&2 || true
  exit 1
fi
[[ "$(psql_value "select current_quantity from public.livestock_cohort_quantity_rollforward where cohort_id='$ASOF'")" == '20' ]] || {
  echo 'ERROR: as-of race left an unexpected current quantity.' >&2
  exit 1
}
MORT_COUNT="$(psql_value "select count(*) from public.livestock_quantity_events where cohort_id='$ASOF' and event_type='MORTALITY'")"
[[ "$MORT_COUNT" == '0' ]] || {
  echo "ERROR: rejected backdated outflow wrote $MORT_COUNT mortality rows." >&2
  exit 1
}

# ---------------------------------------------------------------------------
# COMMIT-time exact shape: balanced legs without matching lineage must fail.
# This proves conservation alone is not enough.
# ---------------------------------------------------------------------------
SPLIT_SRC="$(provision_cohort 'دفعة شكل تقسيم مصدر 022' 10 'gf22h-shape-split-src')"
SPLIT_DST="$(provision_cohort 'دفعة شكل تقسيم وجهة 022' 10 'gf22h-shape-split-dst')"
SPLIT_OP='99999999-0000-4000-8000-000000000221'

MALFORMED_SPLIT="begin;
insert into public.livestock_quantity_operations(
  id,organization_id,project_id,operation_type,effective_at,reason,performed_by,idempotency_key,request_hash
) values (
  '$SPLIT_OP','$ORG','$PROJECT','SPLIT',now()-interval '30 seconds','اختبار شكل تقسيم','$ACTOR','gf22h-shape-split-op',repeat('a',64)
);
insert into public.livestock_quantity_events(
  organization_id,project_id,cohort_id,event_type,quantity,effective_at,operation_id,recorded_by,idempotency_key,request_hash
) values
  ('$ORG','$PROJECT','$SPLIT_SRC','SPLIT_OUT',1,now()-interval '30 seconds','$SPLIT_OP','$ACTOR','gf22h-shape-split-out',repeat('b',64)),
  ('$ORG','$PROJECT','$SPLIT_DST','SPLIT_IN',1,now()-interval '30 seconds','$SPLIT_OP','$ACTOR','gf22h-shape-split-in',repeat('c',64));
commit;"

set +e
run_session "$MALFORMED_SPLIT" "$tmpdir/malformed-split.log"
split_status=$?
set -e
if [[ "$split_status" -eq 0 ]]; then
  echo 'ERROR: malformed SPLIT committed without lineage.' >&2
  exit 1
fi
if ! grep -q 'exactly one out leg, one in leg and one lineage row' "$tmpdir/malformed-split.log"; then
  echo 'ERROR: malformed SPLIT failed for the wrong reason.' >&2
  cat "$tmpdir/malformed-split.log" >&2 || true
  exit 1
fi
[[ "$(psql_value "select count(*) from public.livestock_quantity_operations where id='$SPLIT_OP'")" == '0' ]] || {
  echo 'ERROR: malformed SPLIT left a partial operation after failed COMMIT.' >&2
  exit 1
}

# MERGE: two OUT legs and one balanced IN leg but only one lineage row. The
# existing conservation invariant passes; the new exact-shape invariant must
# reject the transaction at COMMIT.
MERGE_A="$(provision_cohort 'دفعة شكل دمج أ 022' 10 'gf22h-shape-merge-a')"
MERGE_B="$(provision_cohort 'دفعة شكل دمج ب 022' 10 'gf22h-shape-merge-b')"
MERGE_DST="$(provision_cohort 'دفعة شكل دمج وجهة 022' 10 'gf22h-shape-merge-dst')"
MERGE_OP='99999999-0000-4000-8000-000000000222'

MALFORMED_MERGE="begin;
insert into public.livestock_quantity_operations(
  id,organization_id,project_id,operation_type,effective_at,reason,performed_by,idempotency_key,request_hash
) values (
  '$MERGE_OP','$ORG','$PROJECT','MERGE',now()-interval '20 seconds','اختبار شكل دمج','$ACTOR','gf22h-shape-merge-op',repeat('d',64)
);
insert into public.livestock_quantity_events(
  organization_id,project_id,cohort_id,event_type,quantity,effective_at,operation_id,recorded_by,idempotency_key,request_hash
) values
  ('$ORG','$PROJECT','$MERGE_A','MERGE_OUT',1,now()-interval '20 seconds','$MERGE_OP','$ACTOR','gf22h-shape-merge-out-a',repeat('e',64)),
  ('$ORG','$PROJECT','$MERGE_B','MERGE_OUT',1,now()-interval '20 seconds','$MERGE_OP','$ACTOR','gf22h-shape-merge-out-b',repeat('f',64)),
  ('$ORG','$PROJECT','$MERGE_DST','MERGE_IN',2,now()-interval '20 seconds','$MERGE_OP','$ACTOR','gf22h-shape-merge-in',repeat('1',64));
insert into public.livestock_cohort_lineage(
  organization_id,project_id,operation_id,source_cohort_id,destination_cohort_id,quantity
) values ('$ORG','$PROJECT','$MERGE_OP','$MERGE_A','$MERGE_DST',1);
commit;"

set +e
run_session "$MALFORMED_MERGE" "$tmpdir/malformed-merge.log"
merge_status=$?
set -e
if [[ "$merge_status" -eq 0 ]]; then
  echo 'ERROR: malformed MERGE committed with incomplete lineage.' >&2
  exit 1
fi
if ! grep -q 'one lineage row per source' "$tmpdir/malformed-merge.log"; then
  echo 'ERROR: malformed MERGE failed for the wrong reason.' >&2
  cat "$tmpdir/malformed-merge.log" >&2 || true
  exit 1
fi
[[ "$(psql_value "select count(*) from public.livestock_quantity_operations where id='$MERGE_OP'")" == '0' ]] || {
  echo 'ERROR: malformed MERGE left a partial operation after failed COMMIT.' >&2
  exit 1
}

echo 'GF-022 as-of concurrency + COMMIT exact-shape PASS.'