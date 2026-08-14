#!/usr/bin/env bash
set -euo pipefail

# Real two-session race against an as-of balance. A later birth must not be
# spendable by two backdated mortality commands, while both commands serialize
# on the same Cohort quantity lock.
DB="${TERRANEX_TEST_DB:-terranex_test}"
PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
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
  echo 'ERROR: GF-022 as-of concurrency prerequisites missing.' >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

COHORT="$(psql_value "$AUTH select public.create_livestock_cohort('$ORG','$PROJECT','$HERD','$SITE','دفعة سباق الرصيد الزمني','PURCHASED',date '2026-08-01',10,null,null,null,null,null,null,null,'gf22-race-asof');")"
psql_sql "$AUTH select public.transition_livestock_cohort('$ORG','$PROJECT','$COHORT','PLANNED','ACTIVE','تفعيل سباق الرصيد الزمني',null,'gf22-race-asof-active');" >/dev/null
psql_sql "$AUTH select public.record_livestock_birth('$ORG','$PROJECT','$COHORT',5,current_timestamp + interval '6 hours',null,null,'gf22-race-asof-future-birth');" >/dev/null

MORT_7="$AUTH
select public.record_livestock_mortality('$ORG','$PROJECT','$COHORT',7,current_timestamp - interval '1 hour','DISEASE',null,null,null,'gf22-race-asof-7');"
MORT_6="$AUTH
select public.record_livestock_mortality('$ORG','$PROJECT','$COHORT',6,current_timestamp - interval '1 hour','INJURY',null,null,null,'gf22-race-asof-6');"

set +e
run_session "$MORT_7" "$tmpdir/m7.log" & pid_a=$!
run_session "$MORT_6" "$tmpdir/m6.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: as-of mortality race expected exactly one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/m7.log" "$tmpdir/m6.log" >&2 || true
  exit 1
fi
if [[ "$status_a" -ne 0 ]]; then LOSER="$tmpdir/m7.log"; else LOSER="$tmpdir/m6.log"; fi
if ! grep -q 'exceeds the current derived quantity' "$LOSER"; then
  echo 'ERROR: losing as-of mortality did not fail on the effective-time balance.' >&2
  cat "$LOSER" >&2
  exit 1
fi

CURRENT="$(psql_value "select current_quantity from public.livestock_cohort_quantity_rollforward where cohort_id='$COHORT'")"
if [[ "$CURRENT" != '3' && "$CURRENT" != '4' ]]; then
  echo "ERROR: current as-of balance was changed by the future birth or overdrawn: $CURRENT" >&2
  exit 1
fi
EVENTS="$(psql_value "select count(*) from public.livestock_quantity_events where cohort_id='$COHORT' and event_type='MORTALITY'")"
if [[ "$EVENTS" != '1' ]]; then
  echo "ERROR: as-of mortality race wrote $EVENTS mortality events; exactly one is allowed." >&2
  exit 1
fi
FUTURE="$(psql_value "select public.livestock_cohort_quantity_as_of('$COHORT', current_timestamp + interval '7 hours')")"
if [[ "$FUTURE" != '8' && "$FUTURE" != '9' ]]; then
  echo "ERROR: future as-of balance did not include the scheduled birth correctly: $FUTURE" >&2
  exit 1
fi

echo 'GF-022 as-of concurrency PASS: one backdated mortality wins, the future birth is excluded from current, and the future as-of balance includes it.'
