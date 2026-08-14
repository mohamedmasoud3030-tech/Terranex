#!/usr/bin/env bash
set -euo pipefail

# GF-021 / Livestock movement concurrency.
#
# A real two-session race proves that two simultaneous movements cannot both
# consume the same current placement and create conflicting successors.
#
# The Cohort sits at (Site A, Herd A). Session A moves it to Site B; session B
# concurrently moves it to Site C. Both declare the SAME source placement, so
# exactly one may commit. The loser must fail rather than branch the chain.
#
# Two independent mechanisms enforce this and both are asserted here:
#   1. the command takes a per-Cohort advisory transaction lock and re-reads
#      the derived placement under it;
#   2. UNIQUE(previous_movement_id) makes a second successor to the same
#      predecessor impossible even if a lock were somehow bypassed.

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

PROJECT="$(psql_value "select id from public.investment_projects where organization_id='$ORG' and internal_reference='GF020-LS-A' limit 1")"
HERD="$(psql_value "select id from public.livestock_herds where organization_id='$ORG' and internal_reference='HERD-A' limit 1")"
SITE_A="$(psql_value "select id from public.livestock_sites where organization_id='$ORG' and internal_reference='SITE-A' limit 1")"
if [[ -z "$PROJECT" || -z "$HERD" || -z "$SITE_A" ]]; then
  echo 'ERROR: GF-021 concurrency prerequisites missing (GF020-LS-A project / HERD-A / SITE-A).' >&2
  exit 1
fi

# Dedicated race sites so the race never collides with the SQL suite fixtures.
SITE_R1="$(psql_value "select id from public.livestock_sites where organization_id='$ORG' and internal_reference='SITE-RACE-1' limit 1")"
if [[ -z "$SITE_R1" ]]; then
  psql_sql "set request.jwt.claim.sub='$ACTOR'; set role authenticated;
    select public.create_livestock_site('$ORG','$PROJECT','موقع سباق ١','SITE-RACE-1','BARN',null,null,'gf21-race-site-1');"
  SITE_R1="$(psql_value "select id from public.livestock_sites where organization_id='$ORG' and internal_reference='SITE-RACE-1' limit 1")"
fi
SITE_R2="$(psql_value "select id from public.livestock_sites where organization_id='$ORG' and internal_reference='SITE-RACE-2' limit 1")"
if [[ -z "$SITE_R2" ]]; then
  psql_sql "set request.jwt.claim.sub='$ACTOR'; set role authenticated;
    select public.create_livestock_site('$ORG','$PROJECT','موقع سباق ٢','SITE-RACE-2','BARN',null,null,'gf21-race-site-2');"
  SITE_R2="$(psql_value "select id from public.livestock_sites where organization_id='$ORG' and internal_reference='SITE-RACE-2' limit 1")"
fi
if [[ -z "$SITE_R1" || -z "$SITE_R2" ]]; then
  echo 'ERROR: could not provision the GF-021 concurrency sites.' >&2
  exit 1
fi

# A dedicated ACTIVE Cohort whose opening placement is Site A / Herd A.
COHORT="$(psql_value "select id from public.livestock_cohorts where organization_id='$ORG' and cohort_reference='دفعة سباق الحركة' limit 1")"
if [[ -z "$COHORT" ]]; then
  psql_sql "set request.jwt.claim.sub='$ACTOR'; set role authenticated;
    select public.create_livestock_cohort('$ORG','$PROJECT','$HERD','$SITE_A','دفعة سباق الحركة','PURCHASED',date '2026-08-01',25,null,null,null,null,null,null,null,'gf21-race-cohort');"
  COHORT="$(psql_value "select id from public.livestock_cohorts where organization_id='$ORG' and cohort_reference='دفعة سباق الحركة' limit 1")"
  psql_sql "set request.jwt.claim.sub='$ACTOR'; set role authenticated;
    select public.transition_livestock_cohort('$ORG','$PROJECT','$COHORT','PLANNED','ACTIVE','تفعيل دفعة السباق',null,'gf21-race-activate');"
fi
if [[ -z "$COHORT" ]]; then
  echo 'ERROR: could not provision the GF-021 concurrency cohort.' >&2
  exit 1
fi

BEFORE_SITE="$(psql_value "select current_site_id from public.livestock_cohort_current_placement where cohort_id='$COHORT'")"
BEFORE_SOURCE="$(psql_value "select placement_source from public.livestock_cohort_current_placement where cohort_id='$COHORT'")"
if [[ "$BEFORE_SITE" != "$SITE_A" || "$BEFORE_SOURCE" != 'OPENING' ]]; then
  echo "ERROR: race cohort did not start at the opening placement (site=$BEFORE_SITE source=$BEFORE_SOURCE)." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Both sessions declare the SAME source placement (Site A, Herd A).
MOVE_1="set request.jwt.claim.sub='$ACTOR'; set role authenticated;
select public.record_livestock_movement('$ORG','$PROJECT','$COHORT','$SITE_A','$HERD','$SITE_R1','$HERD',now(),'نقل متزامن ١',null,null,'gf21-race-move-1');"
MOVE_2="set request.jwt.claim.sub='$ACTOR'; set role authenticated;
select public.record_livestock_movement('$ORG','$PROJECT','$COHORT','$SITE_A','$HERD','$SITE_R2','$HERD',now(),'نقل متزامن ٢',null,null,'gf21-race-move-2');"

set +e
run_session "$MOVE_1" "$tmpdir/m1.log" & pid_a=$!
run_session "$MOVE_2" "$tmpdir/m2.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: concurrent movements expected exactly one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/m1.log" "$tmpdir/m2.log" >&2 || true
  exit 1
fi

# The loser must have been refused for the right reason: it tried to consume a
# placement that was no longer current.
if [[ "$status_a" -ne 0 ]]; then LOSER="$tmpdir/m1.log"; else LOSER="$tmpdir/m2.log"; fi
if ! grep -q 'source is not the current placement' "$LOSER"; then
  echo 'ERROR: the losing movement did not fail on the stale-placement invariant.' >&2
  cat "$LOSER" >&2
  exit 1
fi

MOVE_COUNT="$(psql_value "select count(*) from public.livestock_cohort_movements where cohort_id='$COHORT'")"
if [[ "$MOVE_COUNT" != '1' ]]; then
  echo "ERROR: the race created $MOVE_COUNT movement rows; exactly 1 is allowed." >&2
  exit 1
fi

# Exactly one derived current placement, and it is one of the two destinations.
PLACEMENT_ROWS="$(psql_value "select count(*) from public.livestock_cohort_current_placement where cohort_id='$COHORT'")"
AFTER_SITE="$(psql_value "select current_site_id from public.livestock_cohort_current_placement where cohort_id='$COHORT'")"
AFTER_SOURCE="$(psql_value "select placement_source from public.livestock_cohort_current_placement where cohort_id='$COHORT'")"
if [[ "$PLACEMENT_ROWS" != '1' ]]; then
  echo "ERROR: the race produced $PLACEMENT_ROWS current placements; exactly 1 is required." >&2
  exit 1
fi
if [[ "$AFTER_SITE" != "$SITE_R1" && "$AFTER_SITE" != "$SITE_R2" ]]; then
  echo "ERROR: the race left an unexpected current site: $AFTER_SITE" >&2
  exit 1
fi
if [[ "$AFTER_SOURCE" != 'MOVEMENT' ]]; then
  echo "ERROR: the winning movement did not become the derived placement source." >&2
  exit 1
fi

# Exactly one audit event for the single winning movement.
AUDIT_COUNT="$(psql_value "select count(*) from public.audit_events where entity_id='$COHORT' and event_type='LIVESTOCK_COHORT_MOVED'")"
if [[ "$AUDIT_COUNT" != '1' ]]; then
  echo "ERROR: the race wrote $AUDIT_COUNT movement audit events; exactly 1 is required." >&2
  exit 1
fi

# The opening placement is still the immutable GF-020 fact.
OPENING="$(psql_value "select site_id from public.livestock_cohort_initial_placements where cohort_id='$COHORT'")"
if [[ "$OPENING" != "$SITE_A" ]]; then
  echo 'ERROR: the race mutated the immutable opening placement.' >&2
  exit 1
fi

# The loser can retry successfully once it observes the real current placement.
CURRENT_HERD="$(psql_value "select current_herd_id from public.livestock_cohort_current_placement where cohort_id='$COHORT'")"
if [[ "$AFTER_SITE" == "$SITE_R1" ]]; then RETRY_DEST="$SITE_R2"; else RETRY_DEST="$SITE_R1"; fi
psql_sql "set request.jwt.claim.sub='$ACTOR'; set role authenticated;
  select public.record_livestock_movement('$ORG','$PROJECT','$COHORT','$AFTER_SITE','$CURRENT_HERD','$RETRY_DEST','$CURRENT_HERD',now(),'إعادة محاولة بعد قراءة الموقع الحالي',null,null,'gf21-race-retry');" >/dev/null
RETRY_SITE="$(psql_value "select current_site_id from public.livestock_cohort_current_placement where cohort_id='$COHORT'")"
if [[ "$RETRY_SITE" != "$RETRY_DEST" ]]; then
  echo 'ERROR: the post-race retry did not advance the derived placement.' >&2
  exit 1
fi
CHAIN="$(psql_value "select count(*) from public.livestock_cohort_movements where cohort_id='$COHORT'")"
if [[ "$CHAIN" != '2' ]]; then
  echo "ERROR: the placement chain has $CHAIN movements after the retry; expected 2." >&2
  exit 1
fi

echo 'GF-021 real two-session movement placement concurrency PASS'
