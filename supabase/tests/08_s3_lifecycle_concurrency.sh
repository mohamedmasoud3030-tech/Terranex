#!/usr/bin/env bash
set -euo pipefail

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
OWNER='00000000-0000-4000-8000-000000000001'
PROJECT="$(psql_value "select id from public.investment_projects where name='مشروع النخيل' limit 1")"

psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.create_property_asset('$ORG','$PROJECT','أصل اختبار تزامن الحالة','RACE-ASSET','s3-race-asset-0001');"
ASSET="$(psql_value "select id from public.property_assets where idempotency_key='s3-race-asset-0001'")"
if [[ -z "$ASSET" ]]; then
  echo 'ERROR: lifecycle race asset was not created.' >&2
  exit 1
fi

SQL_A="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.transition_property_asset('$ORG','$ASSET','CANDIDATE','DUE_DILIGENCE','قرار جلسة متزامنة أ',null,'s3-race-state-key-a');"
SQL_B="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.transition_property_asset('$ORG','$ASSET','CANDIDATE','DUE_DILIGENCE','قرار جلسة متزامنة ب',null,'s3-race-state-key-b');"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
set +e
run_session "$SQL_A" "$tmpdir/a.log" & pid_a=$!
run_session "$SQL_B" "$tmpdir/b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: lifecycle race expected exactly one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/a.log" "$tmpdir/b.log" >&2
  exit 1
fi

COUNT="$(psql_value "select count(*) from public.property_asset_state_history where property_asset_id='$ASSET' and new_state='DUE_DILIGENCE'")"
STATE="$(psql_value "select public.s3_current_property_state('$ASSET')")"
if [[ "$COUNT" != '1' || "$STATE" != 'DUE_DILIGENCE' ]]; then
  echo "ERROR: lifecycle race left count=$COUNT state=$STATE" >&2
  exit 1
fi

echo 'S3 lifecycle two-session concurrency PASS'
