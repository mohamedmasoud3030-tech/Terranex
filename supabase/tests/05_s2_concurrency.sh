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

assert_both_ok() {
  local status_a="$1" status_b="$2" label="$3"
  if [[ "$status_a" -eq 0 && "$status_b" -eq 0 ]]; then
    return 0
  fi
  echo "ERROR: $label expected both idempotent sessions to succeed; got A=$status_a B=$status_b" >&2
  return 1
}

ORG='10000000-0000-4000-8000-000000000001'
USER_ID='00000000-0000-4000-8000-000000000001'
PROJECT="$(psql_value "select id from public.investment_projects where name='مشروع النخيل' limit 1")"
ACCOUNT="$(psql_value "select id from public.project_cash_accounts where name='حساب بنك المشروع' limit 1")"
OBL_RACE="$(psql_value "select id from public.cost_obligations where idempotency_key='s2-obl-race-0001' limit 1")"
PAY_RACE="$(psql_value "select id from public.project_payments where idempotency_key='s2-pay-race-01' limit 1")"
LINE_RECON="$(psql_value "select id from public.bank_statement_lines where provider_reference='TXN-RACE-RECON' limit 1")"
CONTRIB_A2="$(psql_value "select id from public.contributions where idempotency_key='contrib-main-a2-1' limit 1")"

for value in "$PROJECT" "$ACCOUNT" "$OBL_RACE" "$PAY_RACE" "$LINE_RECON" "$CONTRIB_A2"; do
  if [[ -z "$value" ]]; then
    echo 'ERROR: S2 SQL suite did not prepare concurrency fixtures.' >&2
    exit 1
  fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ---------------------------------------------------------------------------
# Race 1 — two simultaneous payments that together exceed the obligation.
# The production function holds the obligation row lock while its payment
# insert is delayed, so the second session must observe the first payment.
# Without row locking both sessions would pass the remaining-amount check.
# ---------------------------------------------------------------------------
psql_sql "
create or replace function public.s2_test_delay_payment_insert() returns trigger
language plpgsql as \$\$ begin perform pg_sleep(1); return new; end \$\$;
drop trigger if exists s2_test_delay_payment on public.project_payments;
create trigger s2_test_delay_payment before insert on public.project_payments
for each row execute function public.s2_test_delay_payment_insert();
"

SQL_PAY_A="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.pay_cost_obligation('$ORG','$OBL_RACE','$ACCOUNT',600000,date '2026-09-05','s2-race-pay-session-a');"
SQL_PAY_B="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.pay_cost_obligation('$ORG','$OBL_RACE','$ACCOUNT',600000,date '2026-09-05','s2-race-pay-session-b');"

set +e
run_session "$SQL_PAY_A" "$tmpdir/pay-a.log" & pid_a=$!
run_session "$SQL_PAY_B" "$tmpdir/pay-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
assert_one_success "$status_a" "$status_b" 'payment race'

PAID_TOTAL="$(psql_value "select coalesce(sum(pp.amount_minor_units),0) from public.project_payments pp
  join public.journal_batches jb on jb.source_type='PAYMENT' and jb.source_id=pp.id and jb.reversal_of_batch_id is null
  where pp.obligation_id='$OBL_RACE'")"
PAID_COUNT="$(psql_value "select count(*) from public.project_payments where obligation_id='$OBL_RACE'")"
if [[ "$PAID_TOTAL" != '1000000' || "$PAID_COUNT" != '2' ]]; then
  echo "ERROR: payment race produced total=$PAID_TOTAL count=$PAID_COUNT (expected 1000000/2)" >&2
  exit 1
fi

psql_sql "drop trigger if exists s2_test_delay_payment on public.project_payments;
drop function if exists public.s2_test_delay_payment_insert();"

# ---------------------------------------------------------------------------
# Race 2 — duplicate financial posting request (same idempotency key).
# Both sessions may enter concurrently; the advisory lock serializes them and
# the replay path returns the original batch to both. Exactly one effect.
# ---------------------------------------------------------------------------
psql_sql "
create or replace function public.s2_test_delay_batch_insert() returns trigger
language plpgsql as \$\$ begin perform pg_sleep(1); return new; end \$\$;
drop trigger if exists s2_test_delay_batch on public.journal_batches;
create trigger s2_test_delay_batch before insert on public.journal_batches
for each row execute function public.s2_test_delay_batch_insert();
"

SQL_ATTACH_A="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.attach_contribution_cash('$ORG','$PROJECT','$CONTRIB_A2','$ACCOUNT','s2-race-attach-key');"
SQL_ATTACH_B="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.attach_contribution_cash('$ORG','$PROJECT','$CONTRIB_A2','$ACCOUNT','s2-race-attach-key');"

set +e
run_session "$SQL_ATTACH_A" "$tmpdir/attach-a.log" & pid_a=$!
run_session "$SQL_ATTACH_B" "$tmpdir/attach-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
assert_both_ok "$status_a" "$status_b" 'duplicate posting race'

ATTACH_COUNT="$(psql_value "select count(*) from public.journal_batches
  where source_type='CONTRIBUTION_CASH_ATTRIBUTION' and source_id='$CONTRIB_A2'")"
if [[ "$ATTACH_COUNT" != '1' ]]; then
  echo "ERROR: duplicate posting race produced $ATTACH_COUNT batches (expected 1)" >&2
  exit 1
fi

psql_sql "drop trigger if exists s2_test_delay_batch on public.journal_batches;
drop function if exists public.s2_test_delay_batch_insert();"

# ---------------------------------------------------------------------------
# Race 3 — duplicate bank-statement fingerprint from two sessions.
# Different idempotency keys, same external fact: the unique fingerprint index
# admits exactly one line; the losing session is rejected.
# ---------------------------------------------------------------------------
psql_sql "
create or replace function public.s2_test_delay_statement_insert() returns trigger
language plpgsql as \$\$ begin perform pg_sleep(1); return new; end \$\$;
drop trigger if exists s2_test_delay_statement on public.bank_statement_lines;
create trigger s2_test_delay_statement before insert on public.bank_statement_lines
for each row execute function public.s2_test_delay_statement_insert();
"

SQL_IMPORT_A="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.import_bank_statement_lines('$ORG','$ACCOUNT',
  array[date '2026-09-06'], array['-777777'], array['EGP'],
  array['حركة سباق البصمة'], array['TXN-RACE-FP'], 's2-race-fp-session-a');"
SQL_IMPORT_B="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.import_bank_statement_lines('$ORG','$ACCOUNT',
  array[date '2026-09-06'], array['-777777'], array['EGP'],
  array['حركة سباق البصمة'], array['TXN-RACE-FP'], 's2-race-fp-session-b');"

set +e
run_session "$SQL_IMPORT_A" "$tmpdir/fp-a.log" & pid_a=$!
run_session "$SQL_IMPORT_B" "$tmpdir/fp-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
assert_one_success "$status_a" "$status_b" 'statement fingerprint race'

FP_COUNT="$(psql_value "select count(*) from public.bank_statement_lines
  where provider_reference='TXN-RACE-FP'")"
if [[ "$FP_COUNT" != '1' ]]; then
  echo "ERROR: fingerprint race produced $FP_COUNT lines (expected 1)" >&2
  exit 1
fi

psql_sql "drop trigger if exists s2_test_delay_statement on public.bank_statement_lines;
drop function if exists public.s2_test_delay_statement_insert();"

# ---------------------------------------------------------------------------
# Race 4 — simultaneous reconciliation attempts against the same statement
# line. Row locks on the payment and the statement line serialize the two
# sessions; exactly one active match can exist.
# ---------------------------------------------------------------------------
psql_sql "
create or replace function public.s2_test_delay_match_insert() returns trigger
language plpgsql as \$\$ begin perform pg_sleep(1); return new; end \$\$;
drop trigger if exists s2_test_delay_match on public.reconciliation_matches;
create trigger s2_test_delay_match before insert on public.reconciliation_matches
for each row execute function public.s2_test_delay_match_insert();
"

SQL_RECON_A="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.reconcile_payment('$ORG','$PAY_RACE','$LINE_RECON','s2-race-recon-session-a');"
SQL_RECON_B="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.reconcile_payment('$ORG','$PAY_RACE','$LINE_RECON','s2-race-recon-session-b');"

set +e
run_session "$SQL_RECON_A" "$tmpdir/recon-a.log" & pid_a=$!
run_session "$SQL_RECON_B" "$tmpdir/recon-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
assert_one_success "$status_a" "$status_b" 'reconciliation race'

RECON_COUNT="$(psql_value "select count(*) from public.reconciliation_matches
  where statement_line_id='$LINE_RECON' and voided_at is null")"
if [[ "$RECON_COUNT" != '1' ]]; then
  echo "ERROR: reconciliation race produced $RECON_COUNT active matches (expected 1)" >&2
  exit 1
fi

psql_sql "drop trigger if exists s2_test_delay_match on public.reconciliation_matches;
drop function if exists public.s2_test_delay_match_insert();"

echo 'S2 real two-session concurrency PASS'
