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
  local status_a="$1" status_b="$2"
  if [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; then
    return 0
  fi
  echo "ERROR: different-key source-posting race expected exactly one success; got A=$status_a B=$status_b" >&2
  return 1
}

ORG='10000000-0000-4000-8000-000000000001'
USER_ID='00000000-0000-4000-8000-000000000001'
PROJECT="$(psql_value "select id from public.investment_projects where name='مشروع النخيل' limit 1")"
ACCOUNT="$(psql_value "select id from public.project_cash_accounts where name='حساب بنك المشروع' limit 1")"
CONTRIB="$(psql_value "select id from public.contributions where idempotency_key='contrib-main-a2-1' limit 1")"
ACTIVE_BATCH="$(psql_value "select jb.id from public.journal_batches jb
  where jb.organization_id='$ORG'
    and jb.source_type='CONTRIBUTION_CASH_ATTRIBUTION'
    and jb.source_id='$CONTRIB'
    and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id)
  limit 1")"

for value in "$PROJECT" "$ACCOUNT" "$CONTRIB" "$ACTIVE_BATCH"; do
  if [[ -z "$value" ]]; then
    echo 'ERROR: S2 fixtures are missing for the integrity concurrency regression.' >&2
    exit 1
  fi
done

# Free the contribution source through the supported correction path, so two
# fresh requests can race to become its next active posting.
psql_sql "set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.reverse_journal_batch(
  '$ORG',
  '$ACTIVE_BATCH',
  'تهيئة سباق مصدر مالي',
  's2-hardening-reverse-a2'
);"

# Delay after the production source guard. PostgreSQL fires same-kind triggers
# alphabetically: journal_batches_one_active_source_guard runs before this
# zz_* trigger. Without the source-scoped advisory lock both sessions can pass
# the guard before either commits; with the fix, session B waits and then sees
# session A's committed active posting.
psql_sql "
create or replace function public.s2_test_delay_after_source_guard() returns trigger
language plpgsql as \$\$ begin perform pg_sleep(1); return new; end \$\$;
drop trigger if exists zz_s2_test_delay_after_source_guard on public.journal_batches;
create trigger zz_s2_test_delay_after_source_guard before insert on public.journal_batches
for each row execute function public.s2_test_delay_after_source_guard();
"

SQL_A="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.attach_contribution_cash('$ORG','$PROJECT','$CONTRIB','$ACCOUNT','s2-source-race-key-a');"
SQL_B="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.attach_contribution_cash('$ORG','$PROJECT','$CONTRIB','$ACCOUNT','s2-source-race-key-b');"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

set +e
run_session "$SQL_A" "$tmpdir/source-a.log" & pid_a=$!
run_session "$SQL_B" "$tmpdir/source-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

assert_one_success "$status_a" "$status_b"

ACTIVE_COUNT="$(psql_value "select count(*) from public.journal_batches jb
  where jb.organization_id='$ORG'
    and jb.source_type='CONTRIBUTION_CASH_ATTRIBUTION'
    and jb.source_id='$CONTRIB'
    and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id)")"

if [[ "$ACTIVE_COUNT" != '1' ]]; then
  echo "ERROR: source-posting race left $ACTIVE_COUNT active batches (expected 1)" >&2
  exit 1
fi

psql_sql "drop trigger if exists zz_s2_test_delay_after_source_guard on public.journal_batches;
drop function if exists public.s2_test_delay_after_source_guard();"

echo 'S2 different-key source concurrency PASS'
