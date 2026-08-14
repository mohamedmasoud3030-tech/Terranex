#!/usr/bin/env bash
set -euo pipefail

# Two concurrent identity commands target a one-head Cohort. The per-Cohort
# GF-022 quantity lock is reused by GF-023, so only one optional identity can be
# introduced at that effective instant. Identification itself changes quantity
# by zero.
DB="${TERRANEX_TEST_DB:-terranex_test}"
PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
CONTAINER="${TERRANEX_DB_CONTAINER:-}"
psql_sql() {
  local sql="$1"
  if [[ -n "$CONTAINER" ]]; then printf '%s\n' "$sql" | docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -q -U "$PGUSER" -d "$DB"
  else printf '%s\n' "$sql" | psql -v ON_ERROR_STOP=1 -q -d "$DB"; fi
}
psql_value() {
  local sql="$1"
  if [[ -n "$CONTAINER" ]]; then docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -Atq -U "$PGUSER" -d "$DB" -c "$sql"
  else psql -v ON_ERROR_STOP=1 -Atq -d "$DB" -c "$sql"; fi
}
run_session() { local sql="$1" log="$2"; psql_sql "$sql" >"$log" 2>&1; }

ORG='10000000-0000-4000-8000-000000000001'
ACTOR='00000000-0000-4000-8000-000000000001'
AUTH="set request.jwt.claim.sub='$ACTOR'; set role authenticated;"
PROJECT="$(psql_value "select id from investment_projects where internal_reference='GF020-LS-A' limit 1")"
HERD="$(psql_value "select id from livestock_herds where project_id='$PROJECT' and internal_reference='HERD-A' limit 1")"
SITE="$(psql_value "select id from livestock_sites where project_id='$PROJECT' and internal_reference='SITE-A' limit 1")"
[[ -n "$PROJECT" && -n "$HERD" && -n "$SITE" ]] || { echo 'ERROR: GF-023 concurrency fixtures missing.' >&2; exit 1; }

COHORT="$(psql_value "$AUTH select create_livestock_cohort('$ORG','$PROJECT','$HERD','$SITE','دفعة سباق التعريف','PURCHASED',current_date-1,1,null,null,null,null,null,'دليل',null,'gf23-race-cohort');")"
psql_sql "$AUTH select transition_livestock_cohort('$ORG','$PROJECT','$COHORT','PLANNED','ACTIVE','تفعيل سباق التعريف',null,'gf23-race-active');" >/dev/null
EFFECTIVE="$(psql_value "select current_date::timestamptz")"
A="$AUTH select identify_livestock_animal('$ORG','$PROJECT','$COHORT','EAR_TAG','RACE-023-A','UNKNOWN',null,null,'$EFFECTIVE','دليل أ',null,'gf23-race-animal-a');"
B="$AUTH select identify_livestock_animal('$ORG','$PROJECT','$COHORT','EAR_TAG','RACE-023-B','UNKNOWN',null,null,'$EFFECTIVE','دليل ب',null,'gf23-race-animal-b');"
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
set +e
run_session "$A" "$tmpdir/a.log" & pa=$!
run_session "$B" "$tmpdir/b.log" & pb=$!
wait "$pa"; sa=$?
wait "$pb"; sb=$?
set -e
if ! { [[ "$sa" -eq 0 && "$sb" -ne 0 ]] || [[ "$sa" -ne 0 && "$sb" -eq 0 ]]; }; then
  echo "ERROR: identity race expected exactly one success; A=$sa B=$sb" >&2
  cat "$tmpdir/a.log" "$tmpdir/b.log" >&2 || true
  exit 1
fi
loser="$tmpdir/a.log"; [[ "$sa" -eq 0 ]] && loser="$tmpdir/b.log"
grep -q 'identified Animal count exceeds Cohort quantity' "$loser" || { cat "$loser" >&2; exit 1; }
IDENTITIES="$(psql_value "select count(*) from livestock_animals where identification_cohort_id='$COHORT'")"
MEMBERSHIPS="$(psql_value "select count(*) from livestock_animal_memberships where cohort_id='$COHORT'")"
QUANTITY="$(psql_value "select current_quantity from livestock_cohort_quantity_rollforward where cohort_id='$COHORT'")"
[[ "$IDENTITIES" == 1 && "$MEMBERSHIPS" == 1 && "$QUANTITY" == 1 ]] || {
  echo "ERROR: race result identities=$IDENTITIES memberships=$MEMBERSHIPS quantity=$QUANTITY" >&2; exit 1;
}
echo 'GF-023 concurrency PASS: one of two identity commands wins, provenance is complete, and authoritative Cohort quantity remains one.'
