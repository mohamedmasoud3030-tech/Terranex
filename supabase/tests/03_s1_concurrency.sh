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
  if psql_sql "$sql" >"$log" 2>&1; then
    return 0
  fi
  return 1
}

assert_one_success() {
  local status_a="$1" status_b="$2" label="$3"
  if [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; then
    return 0
  fi
  echo "ERROR: $label expected exactly one concurrent session to succeed; got A=$status_a B=$status_b" >&2
  return 1
}

ORG='10000000-0000-4000-8000-000000000001'
USER_ID='00000000-0000-4000-8000-000000000001'
PROJECT="$(psql_value "select id from public.investment_projects where name='مشروع النخيل' limit 1")"
VERSION="$(psql_value "select id from public.agreement_versions where project_id='$PROJECT' and status='ACTIVE' limit 1")"
PART1="$(psql_value "select pp.id from public.project_participants pp join public.parties p on p.id=pp.party_id where pp.project_id='$PROJECT' and p.legal_name='مستثمر أول' limit 1")"
PART2="$(psql_value "select pp.id from public.project_participants pp join public.parties p on p.id=pp.party_id where pp.project_id='$PROJECT' and p.legal_name='مستثمر ثانٍ' limit 1")"
CALL_RACE="$(psql_value "select id from public.capital_calls where project_id='$PROJECT' and reference='CALL-RACE' limit 1")"

for value in "$PROJECT" "$VERSION" "$PART1" "$PART2" "$CALL_RACE"; do
  if [[ -z "$value" ]]; then
    echo 'ERROR: S1 SQL suite did not prepare concurrency fixtures.' >&2
    exit 1
  fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Delay actual insert while the production function holds its call-line lock.
# Without the lock, both sessions can pass the same precheck and overpay.
psql_sql "
create or replace function public.s1_test_delay_contribution_insert() returns trigger
language plpgsql as \$\$ begin perform pg_sleep(1); return new; end \$\$;
drop trigger if exists s1_test_delay_contribution on public.contributions;
create trigger s1_test_delay_contribution before insert on public.contributions
for each row execute function public.s1_test_delay_contribution_insert();
"

SQL_CONTRIB_A="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.record_contribution('$ORG','$PROJECT','$PART1','$VERSION','$CALL_RACE',300000,'EGP',date '2026-10-01','race-contrib-session-a');"
SQL_CONTRIB_B="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.record_contribution('$ORG','$PROJECT','$PART1','$VERSION','$CALL_RACE',300000,'EGP',date '2026-10-01','race-contrib-session-b');"

set +e
run_session "$SQL_CONTRIB_A" "$tmpdir/contrib-a.log" & pid_a=$!
run_session "$SQL_CONTRIB_B" "$tmpdir/contrib-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
assert_one_success "$status_a" "$status_b" 'contribution race'

CONTRIB_COUNT="$(psql_value "select count(*) from public.contributions where capital_call_id='$CALL_RACE'")"
CONTRIB_SUM="$(psql_value "select coalesce(sum(contribution_minor_units),0) from public.contributions where capital_call_id='$CALL_RACE'")"
if [[ "$CONTRIB_COUNT" != '1' || "$CONTRIB_SUM" != '300000' ]]; then
  echo "ERROR: contribution race produced count=$CONTRIB_COUNT sum=$CONTRIB_SUM" >&2
  exit 1
fi

psql_sql "drop trigger if exists s1_test_delay_contribution on public.contributions; drop function if exists public.s1_test_delay_contribution_insert();"

# Delay call insert while the production function holds commitment rows. Without
# commitment locking, both sessions can observe the same called total and over-call.
psql_sql "
create or replace function public.s1_test_delay_call_insert() returns trigger
language plpgsql as \$\$ begin perform pg_sleep(1); return new; end \$\$;
drop trigger if exists s1_test_delay_call on public.capital_calls;
create trigger s1_test_delay_call before insert on public.capital_calls
for each row execute function public.s1_test_delay_call_insert();
"

SQL_CALL_A="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.create_capital_call('$ORG','$PROJECT','$VERSION',date '2026-10-10','CALL-CONCURRENT-A',array['$PART2'::uuid],array[200000]::bigint[],'race-call-session-a');"
SQL_CALL_B="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.create_capital_call('$ORG','$PROJECT','$VERSION',date '2026-10-10','CALL-CONCURRENT-B',array['$PART2'::uuid],array[200000]::bigint[],'race-call-session-b');"

set +e
run_session "$SQL_CALL_A" "$tmpdir/call-a.log" & pid_a=$!
run_session "$SQL_CALL_B" "$tmpdir/call-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
assert_one_success "$status_a" "$status_b" 'capital-call race'

RACE_CALL_COUNT="$(psql_value "select count(*) from public.capital_calls where reference in ('CALL-CONCURRENT-A','CALL-CONCURRENT-B')")"
PART2_CALLED="$(psql_value "select coalesce(sum(ccl.amount_minor_units),0) from public.capital_call_lines ccl join public.capital_calls cc on cc.id=ccl.capital_call_id where cc.status='ISSUED' and cc.agreement_version_id='$VERSION' and ccl.participant_id='$PART2'")"
if [[ "$RACE_CALL_COUNT" != '1' || "$PART2_CALLED" != '400000' ]]; then
  echo "ERROR: capital-call race produced race_calls=$RACE_CALL_COUNT total_called=$PART2_CALLED" >&2
  exit 1
fi

psql_sql "drop trigger if exists s1_test_delay_call on public.capital_calls; drop function if exists public.s1_test_delay_call_insert();"

echo 'S1 real two-session concurrency PASS'
