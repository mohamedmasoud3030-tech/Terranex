#!/usr/bin/env bash
set -euo pipefail

# Phase 2C — real two-session PostgreSQL concurrency races against the
# fixtures built by 28_phase2c_financial_integrity.sql:
#   Race 1: duplicate payment of the same obligation (no overpayment).
#   Race 2: duplicate S5 allocation approval (exactly one posting).
#   Race 3: posting racing a period close (no silent close-boundary crossing).
#   Race 4: duplicate S7 opening-import approval (exactly one posting).
# Overlap is forced with test-only delay triggers that are dropped at the end.

P2C_DB="${TERRANEX_TEST_DB:-terranex_test}"
P2C_PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
export PGPASSWORD
P2C_CONTAINER="${TERRANEX_DB_CONTAINER:-}"

p2c_sql() {
  local sql="$1"
  if [[ -n "$P2C_CONTAINER" ]]; then
    printf '%s\n' "$sql" | docker exec -i "$P2C_CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$P2C_PGUSER" -d "$P2C_DB"
  else
    printf '%s\n' "$sql" | psql -q -v ON_ERROR_STOP=1 -d "$P2C_DB"
  fi
}
p2c_value() {
  local sql="$1"
  if [[ -n "$P2C_CONTAINER" ]]; then
    docker exec -i "$P2C_CONTAINER" psql -Atq -v ON_ERROR_STOP=1 -U "$P2C_PGUSER" -d "$P2C_DB" -c "$sql"
  else
    psql -Atq -v ON_ERROR_STOP=1 -d "$P2C_DB" -c "$sql"
  fi
}
p2c_session() {
  local sql="$1" log="$2"
  if p2c_sql "$sql" >"$log" 2>&1; then return 0; fi
  return 1
}
p2c_fail() {
  echo "ERROR: $1" >&2
  exit 1
}

ORG='30000000-0000-4000-8000-000000000001'
OWNER1='00000000-0000-4000-8000-000000000011'
OWNER2='00000000-0000-4000-8000-000000000012'

PROJECT="$(p2c_value "select id from public.investment_projects where organization_id='$ORG' and name='مشروع الفحص المالي' limit 1")"
CASH="$(p2c_value "select id from public.project_cash_accounts where organization_id='$ORG' and name='حساب فحص 2C' limit 1")"
RACE_OBL="$(p2c_value "select id from public.cost_obligations where organization_id='$ORG' and idempotency_key='p2c-obl-race-01' limit 1")"
ALLOC_RUN="$(p2c_value "select id from public.s5_allocation_runs where organization_id='$ORG' and idempotency_key='p2c-alloc-prepare-01' limit 1")"
RACE_PROJECT="$(p2c_value "select id from public.investment_projects where organization_id='$ORG' and name='مشروع سباق الإغلاق' limit 1")"
RACE_CASH="$(p2c_value "select id from public.project_cash_accounts where organization_id='$ORG' and name='حساب سباق الإغلاق' limit 1")"
RACECLOSE_OBL="$(p2c_value "select id from public.cost_obligations where organization_id='$ORG' and idempotency_key='p2c-obl-raceclose-01' limit 1")"
RACE_CLOSE_RUN="$(p2c_value "select id from public.close_runs where organization_id='$ORG' and project_id='$RACE_PROJECT' and status='PREPARED' limit 1")"
RACE_PERIOD="$(p2c_value "select period_id from public.close_runs where id='$RACE_CLOSE_RUN'")"
CLEAN_IMPORT="$(p2c_value "select id from public.s7_opening_imports where organization_id='$ORG' and idempotency_key='p2c-opening-clean-0001' limit 1")"

for value in "$PROJECT" "$CASH" "$RACE_OBL" "$ALLOC_RUN" "$RACE_PROJECT" "$RACE_CASH" "$RACECLOSE_OBL" "$RACE_CLOSE_RUN" "$RACE_PERIOD" "$CLEAN_IMPORT"; do
  if [[ -z "$value" ]]; then
    p2c_fail 'Phase 2C SQL suite (28) did not prepare the concurrency fixtures.'
  fi
done

POSTING_DATE="$(p2c_value "select end_date::text from public.accounting_periods where organization_id='$ORG' and project_id='$PROJECT' and status='OPEN' order by version desc limit 1")"
[[ -n "$POSTING_DATE" ]] || p2c_fail 'Phase 2C project has no OPEN accounting period.'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ---------------------------------------------------------------------------
# Race 1 — two simultaneous full-amount payments of the same obligation.
# The delay widens the window between the obligation row lock and the
# payment insert so both sessions truly overlap.
# ---------------------------------------------------------------------------
p2c_sql "
create or replace function public.p2c_test_delay_payment_insert() returns trigger
language plpgsql as \$\$ begin perform pg_sleep(1); return new; end \$\$;
drop trigger if exists p2c_test_delay_payment on public.project_payments;
create trigger p2c_test_delay_payment before insert on public.project_payments
for each row execute function public.p2c_test_delay_payment_insert();
"

p2c_sql "set request.jwt.claim.sub='$OWNER2'; set role authenticated;
select public.prepare_cost_payment('$ORG','$RACE_OBL','$CASH',120000,date '$POSTING_DATE','p2c-race-proposal-session-a');
select public.prepare_cost_payment('$ORG','$RACE_OBL','$CASH',120000,date '$POSTING_DATE','p2c-race-proposal-session-b');"
PROPOSAL_A="$(p2c_value "select id from public.cost_payment_proposals where idempotency_key='p2c-race-proposal-session-a'")"
PROPOSAL_B="$(p2c_value "select id from public.cost_payment_proposals where idempotency_key='p2c-race-proposal-session-b'")"
SQL_PAY_A="set request.jwt.claim.sub='$OWNER1'; set role authenticated;
select public.approve_cost_payment('$ORG','$PROPOSAL_A','p2c-race-pay-session-a');"
SQL_PAY_B="set request.jwt.claim.sub='$OWNER1'; set role authenticated;
select public.approve_cost_payment('$ORG','$PROPOSAL_B','p2c-race-pay-session-b');"

set +e
p2c_session "$SQL_PAY_A" "$tmpdir/pay-a.log" & pid_a=$!
p2c_session "$SQL_PAY_B" "$tmpdir/pay-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
if [[ "$status_a" -eq 0 && "$status_b" -eq 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -ne 0 ]]; then
  echo '--- pay A log:' >&2; cat "$tmpdir/pay-a.log" >&2
  echo '--- pay B log:' >&2; cat "$tmpdir/pay-b.log" >&2
  p2c_fail "payment race expected exactly one winner; got A=$status_a B=$status_b"
fi

PAY_ROWS="$(p2c_value "select count(*) from public.project_payments where obligation_id='$RACE_OBL'")"
PAY_BATCHES="$(p2c_value "select count(*) from public.journal_batches jb
  where jb.source_type='PAYMENT' and jb.reversal_of_batch_id is null
    and jb.source_id in (select id from public.project_payments where obligation_id='$RACE_OBL')")"
PAID_TOTAL="$(p2c_value "select coalesce(sum(amount_minor_units),0) from public.project_payments where obligation_id='$RACE_OBL'")"
[[ "$PAY_ROWS" == '1' ]] || p2c_fail "payment race left $PAY_ROWS payment rows; expected exactly 1"
[[ "$PAY_BATCHES" == '1' ]] || p2c_fail "payment race left $PAY_BATCHES journal batches; expected exactly 1"
[[ "$PAID_TOTAL" == '120000' ]] || p2c_fail "payment race posted $PAID_TOTAL; expected exactly 120000 (no overpayment)"
echo "Race 1 PASS: duplicate obligation payment race produced exactly one payment of exactly 120000"

# ---------------------------------------------------------------------------
# Race 2 — two simultaneous S5 allocation approvals of the same run with
# different idempotency keys. The delay holds the winner inside the run row
# lock so the second session genuinely overlaps.
# ---------------------------------------------------------------------------
p2c_sql "
create or replace function public.p2c_test_delay_alloc_update() returns trigger
language plpgsql as \$\$ begin perform pg_sleep(1); return new; end \$\$;
drop trigger if exists p2c_test_delay_alloc on public.s5_allocation_runs;
create trigger p2c_test_delay_alloc before update on public.s5_allocation_runs
for each row execute function public.p2c_test_delay_alloc_update();
"

SQL_ALLOC_A="set request.jwt.claim.sub='$OWNER1'; set role authenticated;
select public.s5_approve_allocation('$ORG','$ALLOC_RUN',date '$POSTING_DATE','p2c-race-alloc-session-a');"
SQL_ALLOC_B="set request.jwt.claim.sub='$OWNER1'; set role authenticated;
select public.s5_approve_allocation('$ORG','$ALLOC_RUN',date '$POSTING_DATE','p2c-race-alloc-session-b');"

set +e
p2c_session "$SQL_ALLOC_A" "$tmpdir/alloc-a.log" & pid_a=$!
p2c_session "$SQL_ALLOC_B" "$tmpdir/alloc-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
if [[ "$status_a" -eq 0 && "$status_b" -eq 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -ne 0 ]]; then
  echo '--- alloc A log:' >&2; cat "$tmpdir/alloc-a.log" >&2
  echo '--- alloc B log:' >&2; cat "$tmpdir/alloc-b.log" >&2
  p2c_fail "allocation approval race expected exactly one winner; got A=$status_a B=$status_b"
fi

ALLOC_STATUS="$(p2c_value "select status from public.s5_allocation_runs where id='$ALLOC_RUN'")"
ALLOC_BATCHES="$(p2c_value "select count(*) from public.journal_batches where source_type='S5_ALLOCATION' and source_id='$ALLOC_RUN' and reversal_of_batch_id is null")"
ALLOC_CREDIT="$(p2c_value "select coalesce(sum(jl.credit_minor_units),0) from public.journal_lines jl
  join public.journal_batches jb on jb.id=jl.batch_id
  where jb.source_type='S5_ALLOCATION' and jb.source_id='$ALLOC_RUN'")"
ALLOC_BALANCED="$(p2c_value "select count(*) from public.journal_batches jb
  where jb.source_type='S5_ALLOCATION' and jb.source_id='$ALLOC_RUN'
    and (select sum(debit_minor_units) from public.journal_lines where batch_id=jb.id)
      = (select sum(credit_minor_units) from public.journal_lines where batch_id=jb.id)")"
ALLOC_EVENTS="$(p2c_value "select count(*) from public.audit_events where organization_id='$ORG' and event_type='S5_ALLOCATION_APPROVED' and entity_id='$ALLOC_RUN'")"
[[ "$ALLOC_STATUS" == 'APPROVED' ]] || p2c_fail "allocation run status is $ALLOC_STATUS after race; expected APPROVED"
[[ "$ALLOC_BATCHES" == '1' ]] || p2c_fail "allocation race left $ALLOC_BATCHES journal batches; expected exactly 1"
[[ "$ALLOC_BALANCED" == '1' ]] || p2c_fail 'allocation race journal batch is not balanced'
[[ "$ALLOC_CREDIT" == '600001' ]] || p2c_fail "allocation posting credited $ALLOC_CREDIT; expected exactly 600001"
[[ "$ALLOC_EVENTS" == '1' ]] || p2c_fail "allocation race left $ALLOC_EVENTS approval audit events; expected 1"
echo "Race 2 PASS: duplicate S5 allocation approval race produced exactly one balanced posting of exactly 600001"

# ---------------------------------------------------------------------------
# Race 3 — a posting racing the period close. The AFTER-insert delay holds
# session A's transaction open across the batch period-lock check, so the
# close can commit while A is mid-posting. The only acceptable final states:
#   (a) A committed before the close lock and the posting is inside the
#       captured snapshot totals, or
#   (b) A was rejected by the period lock and left zero residue.
# A posting inside the closed period that the snapshot does not contain is a
# silent close-boundary crossing and fails this suite.
# ---------------------------------------------------------------------------
p2c_sql "
drop trigger if exists p2c_test_delay_payment on public.project_payments;
create or replace function public.p2c_test_delay_lines_after() returns trigger
language plpgsql as \$\$ begin perform pg_sleep(3); return null; end \$\$;
drop trigger if exists p2c_test_delay_lines on public.journal_lines;
create trigger p2c_test_delay_lines after insert on public.journal_lines
for each row execute function public.p2c_test_delay_lines_after();
"

p2c_sql "set request.jwt.claim.sub='$OWNER2'; set role authenticated;
select public.prepare_cost_payment('$ORG','$RACECLOSE_OBL','$RACE_CASH',90000,date '$POSTING_DATE','p2c-race-close-proposal');"
RACE_PROPOSAL="$(p2c_value "select id from public.cost_payment_proposals where idempotency_key='p2c-race-close-proposal'")"
SQL_POST="set request.jwt.claim.sub='$OWNER1'; set role authenticated;
select public.approve_cost_payment('$ORG','$RACE_PROPOSAL','p2c-race-close-payment');"
SQL_CLOSE="set request.jwt.claim.sub='$OWNER1'; set role authenticated;
select public.s6_approve_close_run('$ORG','$RACE_CLOSE_RUN','p2c-race-close-approve');"

set +e
p2c_session "$SQL_POST" "$tmpdir/post-a.log" & pid_a=$!
sleep 1
p2c_session "$SQL_CLOSE" "$tmpdir/close-b.log" & pid_b=$!
wait "$pid_a"; status_post=$?
wait "$pid_b"; status_close=$?
set -e
[[ "$status_close" -eq 0 ]] || { cat "$tmpdir/close-b.log" >&2; p2c_fail 'close approval must succeed in the posting-versus-close race'; }

RACE_PERIOD_STATUS="$(p2c_value "select status from public.accounting_periods where id='$RACE_PERIOD'")"
[[ "$RACE_PERIOD_STATUS" == 'CLOSED' ]] || p2c_fail "race period status is $RACE_PERIOD_STATUS; expected CLOSED"

RACE_PAY_ROWS="$(p2c_value "select count(*) from public.project_payments where obligation_id='$RACECLOSE_OBL'")"
RACE_PAY_BATCHES="$(p2c_value "select count(*) from public.journal_batches jb
  where jb.source_type='PAYMENT' and jb.reversal_of_batch_id is null
    and jb.project_id='$RACE_PROJECT'
    and jb.source_id in (select id from public.project_payments where obligation_id='$RACECLOSE_OBL')")"
RACE_SNAPSHOT_CASH="$(p2c_value "select s.totals->>'cash_minor_units' from public.close_run_snapshots s
  where s.close_run_id='$RACE_CLOSE_RUN'")"

if [[ "$status_post" -eq 0 ]]; then
  [[ "$RACE_PAY_ROWS" == '1' && "$RACE_PAY_BATCHES" == '1' ]] \
    || p2c_fail "posting won the race but left rows=$RACE_PAY_ROWS batches=$RACE_PAY_BATCHES"
  [[ "$RACE_SNAPSHOT_CASH" == '0' ]] \
    || p2c_fail "posting crossed the close boundary silently: batch inside CLOSED period but snapshot cash is $RACE_SNAPSHOT_CASH (expected 0 after funded payment)"
  echo "Race 3 PASS: funded payment committed before the close lock and is captured in the close snapshot (cash 0)"
else
  grep -q "no open accounting period" "$tmpdir/post-a.log" \
    || { cat "$tmpdir/post-a.log" >&2; p2c_fail "posting lost the race for an unexpected reason"; }
  [[ "$RACE_PAY_ROWS" == '0' && "$RACE_PAY_BATCHES" == '0' ]] \
    || p2c_fail "rejected posting left residue: rows=$RACE_PAY_ROWS batches=$RACE_PAY_BATCHES"
  [[ "$RACE_SNAPSHOT_CASH" == '90000' ]] \
    || p2c_fail "snapshot cash is $RACE_SNAPSHOT_CASH although no payment crossed the boundary (expected funded cash 90000)"
  echo "Race 3 PASS: posting racing the close was rejected deterministically with zero residue"
fi

# ---------------------------------------------------------------------------
# Race 4 — two simultaneous S7 opening-import approvals. The delay holds the
# winner inside the import row lock so the second session genuinely overlaps.
# ---------------------------------------------------------------------------
p2c_sql "
drop trigger if exists p2c_test_delay_lines on public.journal_lines;
create or replace function public.p2c_test_delay_import_update() returns trigger
language plpgsql as \$\$ begin perform pg_sleep(1); return new; end \$\$;
drop trigger if exists p2c_test_delay_import on public.s7_opening_imports;
create trigger p2c_test_delay_import before update on public.s7_opening_imports
for each row execute function public.p2c_test_delay_import_update();
"

SQL_IMPORT_A="set request.jwt.claim.sub='$OWNER1'; set role authenticated;
select public.s7_approve_opening_import('$ORG','$CLEAN_IMPORT',date '$POSTING_DATE','p2c-race-import-session-a');"
SQL_IMPORT_B="set request.jwt.claim.sub='$OWNER1'; set role authenticated;
select public.s7_approve_opening_import('$ORG','$CLEAN_IMPORT',date '$POSTING_DATE','p2c-race-import-session-b');"

set +e
p2c_session "$SQL_IMPORT_A" "$tmpdir/import-a.log" & pid_a=$!
p2c_session "$SQL_IMPORT_B" "$tmpdir/import-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
if [[ "$status_a" -eq 0 && "$status_b" -eq 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -ne 0 ]]; then
  echo '--- import A log:' >&2; cat "$tmpdir/import-a.log" >&2
  echo '--- import B log:' >&2; cat "$tmpdir/import-b.log" >&2
  p2c_fail "opening-import approval race expected exactly one winner; got A=$status_a B=$status_b"
fi

IMPORT_STATUS="$(p2c_value "select status from public.s7_opening_imports where id='$CLEAN_IMPORT'")"
IMPORT_BATCHES="$(p2c_value "select count(*) from public.journal_batches where source_type='S7_OPENING_IMPORT' and source_id='$CLEAN_IMPORT' and reversal_of_batch_id is null")"
IMPORT_DEBIT="$(p2c_value "select coalesce(sum(debit_minor_units),0) from public.journal_lines jl
  join public.journal_batches jb on jb.id=jl.batch_id
  where jb.source_type='S7_OPENING_IMPORT' and jb.source_id='$CLEAN_IMPORT'")"
IMPORT_CREDIT="$(p2c_value "select coalesce(sum(credit_minor_units),0) from public.journal_lines jl
  join public.journal_batches jb on jb.id=jl.batch_id
  where jb.source_type='S7_OPENING_IMPORT' and jb.source_id='$CLEAN_IMPORT'")"
IMPORT_LINES="$(p2c_value "select count(*) from public.journal_lines jl
  join public.journal_batches jb on jb.id=jl.batch_id
  where jb.source_type='S7_OPENING_IMPORT' and jb.source_id='$CLEAN_IMPORT'")"
[[ "$IMPORT_STATUS" == 'POSTED' ]] || p2c_fail "opening import status is $IMPORT_STATUS after race; expected POSTED"
[[ "$IMPORT_BATCHES" == '1' ]] || p2c_fail "opening-import race left $IMPORT_BATCHES journal batches; expected exactly 1"
[[ "$IMPORT_LINES" == '3' ]] || p2c_fail "opening-import race left $IMPORT_LINES journal lines; expected exactly 3"
[[ "$IMPORT_DEBIT" == '700000' && "$IMPORT_CREDIT" == '700000' ]] \
  || p2c_fail "opening-import posting is not exactly balanced at 700000 (debit=$IMPORT_DEBIT credit=$IMPORT_CREDIT)"

# Idempotent replay of the winning key returns the same batch and a new key
# is refused; no duplicate opening fact can be created.
WINNER_KEY=''
if [[ "$status_a" -eq 0 ]]; then WINNER_KEY='p2c-race-import-session-a'; else WINNER_KEY='p2c-race-import-session-b'; fi
REPLAY_BATCH="$(p2c_value "set request.jwt.claim.sub='$OWNER1'; set role authenticated;
select public.s7_approve_opening_import('$ORG','$CLEAN_IMPORT',date '$POSTING_DATE','$WINNER_KEY');")"
CURRENT_BATCH="$(p2c_value "select id from public.journal_batches where source_type='S7_OPENING_IMPORT' and source_id='$CLEAN_IMPORT' and reversal_of_batch_id is null")"
[[ "$REPLAY_BATCH" == "$CURRENT_BATCH" ]] || p2c_fail 'idempotent approval replay must return the existing posting batch'
IMPORT_BATCHES_AFTER="$(p2c_value "select count(*) from public.journal_batches where source_type='S7_OPENING_IMPORT' and source_id='$CLEAN_IMPORT' and reversal_of_batch_id is null")"
[[ "$IMPORT_BATCHES_AFTER" == '1' ]] || p2c_fail 'idempotent approval replay must not duplicate the opening journal fact'
set +e
LATE_OUT="$(p2c_sql "set request.jwt.claim.sub='$OWNER1'; set role authenticated;
select public.s7_approve_opening_import('$ORG','$CLEAN_IMPORT',date '$POSTING_DATE','p2c-race-import-late-key');" 2>&1)"
late_status=$?
set -e
[[ "$late_status" -ne 0 ]] || p2c_fail 'a fresh-key approval after posting must be refused'
echo "$LATE_OUT" | grep -q "already posted" || p2c_fail "unexpected late-approval error: $LATE_OUT"

# A second fully prepared opening import must NOT be able to overwrite the
# active posted opening position of the same project.
SECOND_IMPORT="$(p2c_value "select id from public.s7_opening_imports where organization_id='$ORG' and idempotency_key='p2c-opening-second-01' limit 1")"
[[ -n "$SECOND_IMPORT" ]] || p2c_fail 'second opening import fixture is missing'
set +e
SECOND_OUT="$(p2c_sql "set request.jwt.claim.sub='$OWNER1'; set role authenticated;
select public.s7_approve_opening_import('$ORG','$SECOND_IMPORT',date '$POSTING_DATE','p2c-race-import-second');" 2>&1)"
second_status=$?
set -e
[[ "$second_status" -ne 0 ]] || p2c_fail 'a second opening import approval must be refused while an active posted opening exists'
echo "$SECOND_OUT" | grep -q "active posted opening import" || p2c_fail "unexpected second-import error: $SECOND_OUT"
SECOND_BATCHES="$(p2c_value "select count(*) from public.journal_batches where source_type='S7_OPENING_IMPORT' and project_id='$PROJECT' and reversal_of_batch_id is null")"
[[ "$SECOND_BATCHES" == '1' ]] || p2c_fail "project holds $SECOND_BATCHES opening journal facts; expected exactly 1"
echo "Race 4 PASS: duplicate opening-import approval race produced exactly one balanced posting of exactly 700000"

# Cleanup: drop every test-only trigger so the database returns to the
# production configuration.
p2c_sql "
drop trigger if exists p2c_test_delay_payment on public.project_payments;
drop trigger if exists p2c_test_delay_alloc on public.s5_allocation_runs;
drop trigger if exists p2c_test_delay_lines on public.journal_lines;
drop trigger if exists p2c_test_delay_import on public.s7_opening_imports;
drop function if exists public.p2c_test_delay_payment_insert();
drop function if exists public.p2c_test_delay_alloc_update();
drop function if exists public.p2c_test_delay_lines_after();
drop function if exists public.p2c_test_delay_import_update();
"

echo "Phase 2C concurrency suite PASS"
