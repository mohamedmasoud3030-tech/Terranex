#!/usr/bin/env bash
set -euo pipefail

# Supplemental audit/balance gate. This runs after 29_phase2c_concurrency.sh
# because shell suites are executed in lexical order by scripts/db-test.sh.

DB="${TERRANEX_TEST_DB:-terranex_test}"
PGUSER_LOCAL="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
export PGPASSWORD
CONTAINER="${TERRANEX_DB_CONTAINER:-}"

sql() {
  local statement="$1"
  if [[ -n "$CONTAINER" ]]; then
    printf '%s\n' "$statement" | docker exec -i "$CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER_LOCAL" -d "$DB"
  else
    printf '%s\n' "$statement" | psql -q -v ON_ERROR_STOP=1 -d "$DB"
  fi
}
value() {
  local statement="$1"
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" psql -Atq -v ON_ERROR_STOP=1 -U "$PGUSER_LOCAL" -d "$DB" -c "$statement"
  else
    psql -Atq -v ON_ERROR_STOP=1 -d "$DB" -c "$statement"
  fi
}
fail() { echo "ERROR: $1" >&2; exit 1; }
assert_eq() {
  local actual="$1" expected="$2" message="$3"
  [[ "$actual" == "$expected" ]] || fail "$message (actual=$actual expected=$expected)"
}

ORG='30000000-0000-4000-8000-000000000001'
OWNER1='00000000-0000-4000-8000-000000000011'
PROJECT="$(value "select id from public.investment_projects where organization_id='$ORG' and name='مشروع الفحص المالي' limit 1")"
[[ -n "$PROJECT" ]] || fail 'Phase 2C fixture project is missing'

# ---------------------------------------------------------------------------
# 1. audit_events is append-only even through a privileged direct SQL path.
# ---------------------------------------------------------------------------
AUDIT_ID="$(value "insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
values('$ORG','$OWNER1','PHASE2D_AUDIT_IMMUTABILITY_PROBE','investment_project','$PROJECT','{\"probe\":true}'::jsonb)
returning id")"
[[ -n "$AUDIT_ID" ]] || fail 'legitimate audit INSERT did not create a row'
assert_eq "$(value "select count(*) from public.audit_events where id='$AUDIT_ID'")" '1' 'audit probe insert is not durable'

set +e
UPDATE_OUT="$(sql "update public.audit_events set payload='{\"tampered\":true}'::jsonb where id='$AUDIT_ID';" 2>&1)"
UPDATE_STATUS=$?
DELETE_OUT="$(sql "delete from public.audit_events where id='$AUDIT_ID';" 2>&1)"
DELETE_STATUS=$?
set -e
[[ "$UPDATE_STATUS" -ne 0 ]] || fail 'audit event UPDATE unexpectedly succeeded'
[[ "$DELETE_STATUS" -ne 0 ]] || fail 'audit event DELETE unexpectedly succeeded'
echo "$UPDATE_OUT" | grep -q 'audit events are append-only' || fail "unexpected audit UPDATE error: $UPDATE_OUT"
echo "$DELETE_OUT" | grep -q 'audit events are append-only' || fail "unexpected audit DELETE error: $DELETE_OUT"
assert_eq "$(value "select count(*) from public.audit_events where id='$AUDIT_ID' and payload->>'probe'='true'")" '1' 'audit probe changed after rejected mutation'
echo 'Audit append-only PASS'

# ---------------------------------------------------------------------------
# 2. Approval evidence is durable and maker/checker identity is reproducible.
# ---------------------------------------------------------------------------
ALLOC_RUN="$(value "select id from public.s5_allocation_runs where organization_id='$ORG' and idempotency_key='p2c-alloc-prepare-01' limit 1")"
[[ -n "$ALLOC_RUN" ]] || fail 'approved allocation fixture missing'
assert_eq "$(value "select count(*) from public.s5_allocation_runs r
where r.id='$ALLOC_RUN' and r.status='APPROVED' and r.prepared_by<>r.approved_by and r.journal_batch_id is not null")" '1' 'allocation maker/checker or journal linkage is not reproducible'
assert_eq "$(value "select count(*) from public.audit_events ae
join public.s5_allocation_runs r on r.id=ae.entity_id
where r.id='$ALLOC_RUN' and ae.organization_id='$ORG' and ae.event_type='S5_ALLOCATION_APPROVED'
  and ae.actor_id=r.approved_by")" '1' 'allocation approval audit evidence does not match authoritative approver'
assert_eq "$(value "select count(*) from public.journal_batches jb
join public.s5_allocation_runs r on r.journal_batch_id=jb.id
where r.id='$ALLOC_RUN' and jb.organization_id='$ORG' and jb.source_type='S5_ALLOCATION' and jb.source_id=r.id")" '1' 'allocation approval cannot be traced to its canonical journal batch'
echo 'Approval/audit trace PASS'

# ---------------------------------------------------------------------------
# 3. Canonical journal remains globally balanced.
# ---------------------------------------------------------------------------
UNBALANCED="$(value "select count(*) from (
  select jb.id
  from public.journal_batches jb
  join public.journal_lines jl on jl.batch_id=jb.id
  group by jb.id
  having sum(jl.debit_minor_units)<>sum(jl.credit_minor_units)
) q")"
assert_eq "$UNBALANCED" '0' 'one or more canonical journal batches are unbalanced'

# ---------------------------------------------------------------------------
# 4. Reproduce the Phase 2C project positions directly from posted facts.
#    These exact values include the completed concurrency races from suite 29.
# ---------------------------------------------------------------------------
CASH="$(value "select coalesce(sum(jl.debit_minor_units-jl.credit_minor_units),0)
from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
where jl.organization_id='$ORG' and jl.project_id='$PROJECT' and sa.role='BANK_CASH'")"
PAYABLE="$(value "select coalesce(sum(jl.credit_minor_units-jl.debit_minor_units),0)
from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
where jl.organization_id='$ORG' and jl.project_id='$PROJECT' and sa.role='SUPPLIER_PAYABLE'")"
RECEIVABLE="$(value "select coalesce(sum(jl.debit_minor_units-jl.credit_minor_units),0)
from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
where jl.organization_id='$ORG' and jl.project_id='$PROJECT' and sa.role='CUSTOMER_RECEIVABLE'")"
REALIZED="$(value "select
  coalesce(sum(case when sa.role='REAL_ESTATE_SALE_REVENUE' then jl.credit_minor_units-jl.debit_minor_units else 0 end),0)
- coalesce(sum(case when sa.role='REAL_ESTATE_COST_OF_SALE' then jl.debit_minor_units-jl.credit_minor_units else 0 end),0)
from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
where jl.organization_id='$ORG' and jl.project_id='$PROJECT'")"
OPENING_CAPITAL="$(value "select coalesce(sum(jl.credit_minor_units-jl.debit_minor_units),0)
from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
where jl.organization_id='$ORG' and jl.project_id='$PROJECT' and sa.role='CONTRIBUTED_CAPITAL'")"
PARTNER_CAPITAL="$(value "select coalesce(sum(jl.credit_minor_units-jl.debit_minor_units),0)
from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
where jl.organization_id='$ORG' and jl.project_id='$PROJECT' and sa.role='PARTNER_CAPITAL'")"

assert_eq "$CASH" '1140000' 'project cash does not reproduce from journal facts'
assert_eq "$PAYABLE" '660000' 'supplier payable does not reproduce from journal facts'
assert_eq "$RECEIVABLE" '400001' 'customer receivable does not reproduce from journal facts'
assert_eq "$REALIZED" '600001' 'realized result does not reproduce from revenue/cost journal facts'
assert_eq "$OPENING_CAPITAL" '500000' 'opening contributed capital does not reproduce from journal facts'
assert_eq "$PARTNER_CAPITAL" '600001' 'partner capital does not reproduce from the approved allocation posting'

echo 'Canonical balance reproduction PASS: cash=1140000 payable=660000 receivable=400001 realized=600001 opening_capital=500000 partner_capital=600001'

# Exact participant allocation positions remain conserved and deterministic.
ALLOC_VECTOR="$(value "select string_agg(allocated_minor_units::text,',' order by allocated_minor_units desc, participant_party_id::text)
from public.s5_allocation_lines where run_id='$ALLOC_RUN'")"
assert_eq "$ALLOC_VECTOR" '200401,199800,199800' 'partner allocation vector changed or lost a minor unit'

# ---------------------------------------------------------------------------
# 5. Reversal and close-snapshot reproduction.
# ---------------------------------------------------------------------------
PAYMENT2="$(value "select id from public.project_payments where organization_id='$ORG' and idempotency_key='p2c-pay-main-02' limit 1")"
[[ -n "$PAYMENT2" ]] || fail 'reversed payment fixture missing'
ORIGINAL_BATCH="$(value "select id from public.journal_batches where organization_id='$ORG' and source_type='PAYMENT' and source_id='$PAYMENT2' limit 1")"
REVERSAL_BATCH="$(value "select id from public.journal_batches where organization_id='$ORG' and source_type='REVERSAL' and reversal_of_batch_id='$ORIGINAL_BATCH' limit 1")"
[[ -n "$ORIGINAL_BATCH" && -n "$REVERSAL_BATCH" ]] || fail 'linked reversal chain is incomplete'
assert_eq "$(value "select coalesce(sum(debit_minor_units-credit_minor_units),0) from public.journal_lines where batch_id in ('$ORIGINAL_BATCH','$REVERSAL_BATCH')")" '0' 'original plus reversal does not net to zero'

SNAPSHOT="$(value "select close_snapshot_id from public.s5_allocation_runs where id='$ALLOC_RUN'")"
[[ -n "$SNAPSHOT" ]] || fail 'allocation run has no close snapshot provenance'
assert_eq "$(value "select public.s5_realized_result_as_of_snapshot('$ORG','$PROJECT','$SNAPSHOT')")" '600001' 'closed snapshot does not reproduce the exact realized result'
assert_eq "$(value "select count(*) from public.close_run_snapshots where id='$SNAPSHOT' and char_length(content_hash)=64")" '1' 'close snapshot hash/provenance missing'
echo 'Reversal and close-snapshot reproduction PASS'

# ---------------------------------------------------------------------------
# 6. Non-authoritative import states never contaminate posted statements.
# ---------------------------------------------------------------------------
MISMATCH_IMPORT="$(value "select id from public.s7_opening_imports where organization_id='$ORG' and idempotency_key='p2c-opening-mismatch-01' limit 1")"
SECOND_IMPORT="$(value "select id from public.s7_opening_imports where organization_id='$ORG' and idempotency_key='p2c-opening-second-01' limit 1")"
assert_eq "$(value "select count(*) from public.journal_batches where organization_id='$ORG' and source_type='S7_OPENING_IMPORT' and source_id='$MISMATCH_IMPORT'")" '0' 'rejected opening import contaminated the journal'
assert_eq "$(value "select count(*) from public.journal_batches where organization_id='$ORG' and source_type='S7_OPENING_IMPORT' and source_id='$SECOND_IMPORT'")" '0' 'unapproved second opening import contaminated the journal'

echo 'Phase 2D supplemental audit and balance-reproduction suite PASS'
