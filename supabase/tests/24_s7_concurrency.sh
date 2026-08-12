#!/usr/bin/env bash
set -euo pipefail

# GF-009 / S7 — real two-session races on the S7 commands that can post or
# freeze a financial fact:
#   1. concurrent approval/posting of the same opening import;
#   2. concurrent recording of the same reconciliation checkpoint;
#   3. concurrent sign-off of the same checkpoint.
#
# The existing projects already carry proven history that later suites depend
# on, so this suite provisions its own project inside the same tenant using
# only production commands, then races a genuine opening posting on it.

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
CHECKER='00000000-0000-4000-8000-000000000001'
MAKER='00000000-0000-4000-8000-000000000003'

PROJECT="$(psql_value "select id from public.investment_projects
  where organization_id='$ORG' and name='مشروع سباق الافتتاحي' limit 1")"
if [[ -z "$PROJECT" ]]; then
  psql_sql "set request.jwt.claim.sub='$CHECKER'; set role authenticated;
  select public.create_investment_project('$ORG','مشروع سباق الافتتاحي',null,null);"
  PROJECT="$(psql_value "select id from public.investment_projects
    where organization_id='$ORG' and name='مشروع سباق الافتتاحي' limit 1")"
fi
if [[ -z "$PROJECT" ]]; then
  echo 'ERROR: could not provision the S7 concurrency project.' >&2
  exit 1
fi

CURRENCY="$(psql_value "select reporting_currency from public.investment_projects where id='$PROJECT'")"
CASH="$(psql_value "select id from public.project_cash_accounts
  where organization_id='$ORG' and project_id='$PROJECT' and currency='$CURRENCY' order by id limit 1")"
if [[ -z "$CASH" ]]; then
  psql_sql "set request.jwt.claim.sub='$CHECKER'; set role authenticated;
  select public.create_project_cash_account('$ORG','$PROJECT','حساب سباق الافتتاحي','$CURRENCY');"
  CASH="$(psql_value "select id from public.project_cash_accounts
    where organization_id='$ORG' and project_id='$PROJECT' and currency='$CURRENCY' order by id limit 1")"
fi
INVESTOR="$(psql_value "select id from public.parties
  where organization_id='$ORG' and legal_name='مستثمر أول' limit 1")"
if [[ -z "$CASH" || -z "$INVESTOR" ]]; then
  echo "ERROR: S7 concurrency fixture incomplete: cash=${CASH:-missing} investor=${INVESTOR:-missing}" >&2
  exit 1
fi

# An opening position is an ordinary posting and therefore needs exactly one
# OPEN period. Open it through the production S6 command; never fabricate a
# period by direct DML.
OPEN_PERIOD="$(psql_value "select id from public.accounting_periods
  where organization_id='$ORG' and project_id='$PROJECT' and reporting_currency='$CURRENCY'
    and status='OPEN' order by version desc limit 1")"
if [[ -z "$OPEN_PERIOD" ]]; then
  psql_sql "set request.jwt.claim.sub='$CHECKER'; set role authenticated;
  select public.s6_create_accounting_period('$ORG','$PROJECT',current_date,current_date);"
  OPEN_PERIOD="$(psql_value "select id from public.accounting_periods
    where organization_id='$ORG' and project_id='$PROJECT' and reporting_currency='$CURRENCY'
      and status='OPEN' order by version desc limit 1")"
fi
if [[ -z "$OPEN_PERIOD" ]]; then
  echo 'ERROR: S7 concurrency could not establish an OPEN accounting period through S6.' >&2
  exit 1
fi
POSTING_DATE="$(psql_value "select start_date from public.accounting_periods where id='$OPEN_PERIOD'")"

ACTIVE_OPENING="$(psql_value "select count(*) from public.s7_opening_imports i
  where i.organization_id='$ORG' and i.project_id='$PROJECT' and i.status='POSTED'
    and not exists(select 1 from public.journal_batches rb
                   where rb.reversal_of_batch_id=i.journal_batch_id)")"
if [[ "$ACTIVE_OPENING" != '0' ]]; then
  echo "ERROR: the S7 concurrency project already holds $ACTIVE_OPENING active opening position(s)." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ---------------------------------------------------------------------------
# 1. Concurrent approval/posting of the same opening import.
# ---------------------------------------------------------------------------
psql_sql "set request.jwt.claim.sub='$MAKER'; set role authenticated;
select public.s7_stage_opening_import('$ORG','$PROJECT','S7.OPENING.V1','opening-race.csv',
  repeat('d',64),
  array['OPENING_BANK_CASH','OPENING_CONTRIBUTED_CAPITAL']::text[],
  array[null,'$INVESTOR']::uuid[],
  array['$CASH',null]::uuid[],
  array['700000','0']::text[],
  array['0','700000']::text[],
  array['نقدية افتتاحية للسباق','رأس مال افتتاحي للسباق']::text[],
  '700000','700000','s7-conc-stage-open-1');"
IMPORT="$(psql_value "select id from public.s7_opening_imports
  where organization_id='$ORG' and idempotency_key='s7-conc-stage-open-1'")"
psql_sql "set request.jwt.claim.sub='$MAKER'; set role authenticated;
select public.s7_validate_opening_import('$ORG','$IMPORT','s7-conc-validate-01');"
psql_sql "set request.jwt.claim.sub='$CHECKER'; set role authenticated;
select public.s7_review_opening_import('$ORG','$IMPORT',null,'s7-conc-review-0001');"

STATUS="$(psql_value "select status from public.s7_opening_imports where id='$IMPORT'")"
if [[ "$STATUS" != 'READY_FOR_APPROVAL' ]]; then
  echo "ERROR: the S7 concurrency import is not ready for approval (status=$STATUS)." >&2
  exit 1
fi

APPROVE_A="set request.jwt.claim.sub='$CHECKER'; set role authenticated;
select public.s7_approve_opening_import('$ORG','$IMPORT','$POSTING_DATE','s7-conc-approve-a');"
APPROVE_B="set request.jwt.claim.sub='$CHECKER'; set role authenticated;
select public.s7_approve_opening_import('$ORG','$IMPORT','$POSTING_DATE','s7-conc-approve-b');"

set +e
run_session "$APPROVE_A" "$tmpdir/approve-a.log" & pid_a=$!
run_session "$APPROVE_B" "$tmpdir/approve-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: concurrent opening approval expected exactly one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/approve-a.log" "$tmpdir/approve-b.log" >&2 || true
  exit 1
fi

POSTED_COUNT="$(psql_value "select count(*) from public.journal_batches
  where source_type='S7_OPENING_IMPORT' and source_id='$IMPORT'")"
LINE_IMBALANCE="$(psql_value "select coalesce(sum(jl.debit_minor_units)-sum(jl.credit_minor_units),1)
  from public.journal_lines jl
  join public.journal_batches jb on jb.id=jl.batch_id
  where jb.source_type='S7_OPENING_IMPORT' and jb.source_id='$IMPORT'")"
FINAL_STATUS="$(psql_value "select status from public.s7_opening_imports where id='$IMPORT'")"
if [[ "$POSTED_COUNT" != '1' || "$LINE_IMBALANCE" != '0' || "$FINAL_STATUS" != 'POSTED' ]]; then
  echo "ERROR: opening approval race invariant failed: batches=$POSTED_COUNT imbalance=$LINE_IMBALANCE status=$FINAL_STATUS" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Concurrent recording of the same reconciliation checkpoint.
# ---------------------------------------------------------------------------
CASH_TRUTH="$(psql_value "select public.s7_authoritative_checkpoint_value('$ORG','$PROJECT','PROJECT_CASH','$POSTING_DATE')")"
if [[ "$CASH_TRUTH" != '700000' ]]; then
  echo "ERROR: the posted opening cash position is $CASH_TRUTH, expected 700000." >&2
  exit 1
fi
RECORD_SQL="set request.jwt.claim.sub='$MAKER'; set role authenticated;
select public.s7_record_reconciliation_checkpoint('$ORG','$PROJECT','PROJECT_CASH','$POSTING_DATE',
  $CASH_TRUTH,'كشف بنك التزامن','BANK-RACE-EV',null,null,'s7-conc-recon-key');"

set +e
run_session "$RECORD_SQL" "$tmpdir/recon-a.log" & pid_a=$!
run_session "$RECORD_SQL" "$tmpdir/recon-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
if [[ "$status_a" -ne 0 && "$status_b" -ne 0 ]]; then
  echo "ERROR: concurrent checkpoint recording expected at least one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/recon-a.log" "$tmpdir/recon-b.log" >&2 || true
  exit 1
fi

RECON_COUNT="$(psql_value "select count(*) from public.s7_reconciliation_checkpoints
  where organization_id='$ORG' and idempotency_key='s7-conc-recon-key'")"
if [[ "$RECON_COUNT" != '1' ]]; then
  echo "ERROR: concurrent checkpoint recording produced $RECON_COUNT rows (expected 1)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Concurrent sign-off of the same checkpoint.
# ---------------------------------------------------------------------------
CHECKPOINT="$(psql_value "select id from public.s7_reconciliation_checkpoints
  where organization_id='$ORG' and idempotency_key='s7-conc-recon-key'")"
SIGN_A="set request.jwt.claim.sub='$CHECKER'; set role authenticated;
select public.s7_sign_off_reconciliation_checkpoint('$ORG','$CHECKPOINT','RACE-SIGNOFF-EV','s7-conc-signoff-a');"
SIGN_B="set request.jwt.claim.sub='$CHECKER'; set role authenticated;
select public.s7_sign_off_reconciliation_checkpoint('$ORG','$CHECKPOINT','RACE-SIGNOFF-EV','s7-conc-signoff-b');"

set +e
run_session "$SIGN_A" "$tmpdir/sign-a.log" & pid_a=$!
run_session "$SIGN_B" "$tmpdir/sign-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: concurrent sign-off expected exactly one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/sign-a.log" "$tmpdir/sign-b.log" >&2 || true
  exit 1
fi

SIGNED="$(psql_value "select status from public.s7_reconciliation_checkpoints where id='$CHECKPOINT'")"
SIGNER_COUNT="$(psql_value "select count(*) from public.s7_reconciliation_checkpoints
  where id='$CHECKPOINT' and signed_off_by is not null and signed_off_at is not null")"
if [[ "$SIGNED" != 'SIGNED_OFF' || "$SIGNER_COUNT" != '1' ]]; then
  echo "ERROR: sign-off race invariant failed: status=$SIGNED signed=$SIGNER_COUNT" >&2
  exit 1
fi

echo 'S7 opening import, reconciliation and sign-off concurrency PASS'
