-- GF-008 / S5 — canonical allocation/distribution verification.
-- Runs after S6 tests against the same PostgreSQL 16 replay database.

create or replace function s5_expect_raise(p_user uuid,p_sql text,p_sqlstate text,p_message_like text default null)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
  return false;
exception when others then
  reset role;
  return sqlstate=p_sqlstate and (p_message_like is null or sqlerrm like p_message_like);
end $$;

create or replace function s5_expect_raise_admin(p_sql text,p_sqlstate text,p_message_like text default null)
returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return sqlstate=p_sqlstate and (p_message_like is null or sqlerrm like p_message_like);
end $$;

create or replace function s5_run(p_user uuid,p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
exception when others then
  reset role;
  raise;
end $$;

select id as s5_project,organization_id as s5_org,reporting_currency as s5_currency
from public.investment_projects where name='مشروع النخيل' limit 1 \gset
select id as s5_version from public.agreement_versions
where project_id=:'s5_project' and status='ACTIVE' limit 1 \gset

-- Choose the frozen close snapshot whose as-of ledger contains the S4 result.
select s.id as s5_snapshot,s.period_id as s5_source_period
from public.close_run_snapshots s
where s.organization_id=:'s5_org' and s.project_id=:'s5_project'
  and public.s5_realized_result_as_of_snapshot(s.organization_id,s.project_id,s.id)<>0
order by s.captured_at asc limit 1 \gset

select public.s5_realized_result_as_of_snapshot(:'s5_org',:'s5_project',:'s5_snapshot') as s5_source_amount \gset
select 1/case when :'s5_source_amount'::bigint>0 then 1 else 0 end as s5_positive_fixture_result;

-- Equal fixed shares are an independent allocation basis. Commitment terms are
-- used here only to identify the governing version's eligible investor set;
-- they are never used as allocation weights.
select array_agg(pp.party_id order by pp.party_id::text)::text as s5_parties,
       array_agg(1::bigint order by pp.party_id::text)::text as s5_weights,
       count(*)::bigint as s5_denominator
from public.commitment_terms ct
join public.project_participants pp on pp.id=ct.participant_id
where ct.organization_id=:'s5_org' and ct.agreement_version_id=:'s5_version'
  and pp.project_id=:'s5_project' and pp.role='INVESTOR' \gset
select 1/case when :'s5_denominator'::bigint>0 then 1 else 0 end as s5_investors_present;

select s5_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_configure_allocation_rules(%L,%L,%L,'FIXED_SHARES',%L::uuid[],%L::bigint[],%s,'S5-RULE-BASIS-EVIDENCE-001','s5-rules-fixed-001')$$,
  :'s5_org',:'s5_project',:'s5_version',:'s5_parties',:'s5_weights',:'s5_denominator'));
select id as s5_rule_set from public.s5_allocation_rule_sets
where organization_id=:'s5_org' and idempotency_key='s5-rules-fixed-001' \gset
select 1/case when (
  select count(*)=:'s5_denominator'::bigint and sum(weight_numerator)=weight_denominator*0+:'s5_denominator'::bigint
  from public.s5_allocation_rules where rule_set_id=:'s5_rule_set'
  group by weight_denominator
) then 1 else 0 end as s5_rule_set_complete;
select 1/case when (
  select basis_evidence_reference='S5-RULE-BASIS-EVIDENCE-001'
    and effective_from is not null
    and char_length(content_hash)=64
  from public.s5_allocation_rule_sets where id=:'s5_rule_set'
) then 1 else 0 end as s5_rule_basis_provenance_frozen;

-- Same retry key + same payload is one material effect.
select s5_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_configure_allocation_rules(%L,%L,%L,'FIXED_SHARES',%L::uuid[],%L::bigint[],%s,'S5-RULE-BASIS-EVIDENCE-001','s5-rules-fixed-001')$$,
  :'s5_org',:'s5_project',:'s5_version',:'s5_parties',:'s5_weights',:'s5_denominator'));
select 1/case when (select count(*) from public.s5_allocation_rule_sets where organization_id=:'s5_org' and idempotency_key='s5-rules-fixed-001')=1 then 1 else 0 end as s5_rules_retry_single_effect;

-- Frozen governing-version economics cannot be edited even by a privileged writer.
select 1/case when s5_expect_raise_admin(format(
  $$update public.s5_allocation_rules set weight_numerator=weight_numerator+1 where rule_set_id=%L$$,
  :'s5_rule_set'),'P0001','%append-only%') then 1 else 0 end as s5_rules_immutable;

select s5_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_prepare_allocation(%L,%L,%L,%L,'REALIZED_RESULT','s5-allocation-prepare-001')$$,
  :'s5_org',:'s5_project',:'s5_snapshot',:'s5_version'));
select id as s5_run_id from public.s5_allocation_runs
where organization_id=:'s5_org' and idempotency_key='s5-allocation-prepare-001' \gset

select 1/case when (select source_amount_minor_units=:'s5_source_amount'::bigint and snapshot_content_hash=(select content_hash from public.close_run_snapshots where id=:'s5_snapshot') and char_length(content_hash)=64 from public.s5_allocation_runs where id=:'s5_run_id') then 1 else 0 end as s5_snapshot_provenance_frozen;
select 1/case when (select sum(allocated_minor_units)=:'s5_source_amount'::bigint from public.s5_allocation_lines where run_id=:'s5_run_id') then 1 else 0 end as s5_rounding_preserves_total;
select 1/case when (select count(*)=:'s5_denominator'::bigint from public.s5_allocation_lines where run_id=:'s5_run_id') then 1 else 0 end as s5_allocation_line_count;
select 1/case when (select sum(rounding_award_minor_units)=(abs(:'s5_source_amount'::bigint)%:'s5_denominator'::bigint) from public.s5_allocation_lines where run_id=:'s5_run_id') then 1 else 0 end as s5_largest_remainder_awards_exact;
select 1/case when public.s5_allocation_lines_are_canonical(:'s5_run_id') then 1 else 0 end as s5_allocation_lines_canonical;

-- Re-running prepare is idempotent and cannot create duplicate lines.
select s5_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_prepare_allocation(%L,%L,%L,%L,'REALIZED_RESULT','s5-allocation-prepare-001')$$,
  :'s5_org',:'s5_project',:'s5_snapshot',:'s5_version'));
select 1/case when (select count(*) from public.s5_allocation_runs where id=:'s5_run_id')=1 and (select count(*) from public.s5_allocation_lines where run_id=:'s5_run_id')=:'s5_denominator'::bigint then 1 else 0 end as s5_prepare_retry_single_effect;

-- A closed source is provenance only: posting still requires an OPEN period.
select 1/case when s5_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_approve_allocation(%L,%L,date '1900-01-01','s5-allocation-approve-no-open')$$,
  :'s5_org',:'s5_run_id'),'P0001','%OPEN accounting period%') then 1 else 0 end as s5_no_open_period_posting_rejected;

select id as s5_open_period,start_date as s5_posting_date
from public.accounting_periods
where organization_id=:'s5_org' and project_id=:'s5_project' and status='OPEN'
order by version desc limit 1 \gset
select s5_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_approve_allocation(%L,%L,%L,'s5-allocation-approve-001')$$,
  :'s5_org',:'s5_run_id',:'s5_posting_date'));
select journal_batch_id as s5_allocation_batch from public.s5_allocation_runs where id=:'s5_run_id' \gset
select 1/case when (select status='APPROVED' and source_period_id=:'s5_source_period'::uuid and posting_date=:'s5_posting_date'::date from public.s5_allocation_runs where id=:'s5_run_id') then 1 else 0 end as s5_allocation_approved_with_closed_source_provenance;
select 1/case when (
  select sum(debit_minor_units)=sum(credit_minor_units) and sum(debit_minor_units)=abs(:'s5_source_amount'::bigint)
  from public.journal_lines where batch_id=:'s5_allocation_batch'
) then 1 else 0 end as s5_allocation_journal_balanced;
select 1/case when (select count(*) from public.journal_batches where id=:'s5_allocation_batch' and source_type='S5_ALLOCATION')=1 then 1 else 0 end as s5_allocation_uses_canonical_ledger;

-- Cross-tenant browser reads are denied by RLS; a leak makes the inner
-- assertion divide by zero and fails the test transaction.
select s5_run('00000000-0000-4000-8000-000000000002',format(
  $$select 1/case when (select count(*) from public.s5_allocation_runs_read where project_id=%L)=0 then 1 else 0 end$$,
  :'s5_project'));

-- Choose an investor with positive capital and a project cash account with cash.
select l.participant_party_id as s5_party
from public.s5_allocation_lines l
where l.run_id=:'s5_run_id' and l.allocated_minor_units>0
order by l.participant_party_id::text limit 1 \gset
select ca.id as s5_cash_account
from public.project_cash_accounts ca
where ca.organization_id=:'s5_org' and ca.project_id=:'s5_project' and ca.currency=:'s5_currency'
  and public.s5_cash_account_balance_internal(ca.organization_id,ca.project_id,ca.id,ca.currency)>0
order by ca.id limit 1 \gset
select 1/case when public.s5_project_distributable_cash_internal(:'s5_org',:'s5_project',:'s5_currency')>0 then 1 else 0 end as s5_positive_distributable_cash;

-- Prepare/approve/pay one minor unit. Approval is distinct from payment.
select s5_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_prepare_distribution(%L,%L,%L,%L,1,'S5-DIST-EVIDENCE-001','s5-dist-prepare-001')$$,
  :'s5_org',:'s5_project',:'s5_run_id',:'s5_party'));
select id as s5_distribution from public.s5_distributions where organization_id=:'s5_org' and idempotency_key='s5-dist-prepare-001' \gset
select 1/case when (select status='PREPARED' and approved_amount_minor_units is null from public.s5_distributions where id=:'s5_distribution') then 1 else 0 end as s5_distribution_prepare_not_payment;
select s5_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_approve_distribution(%L,%L,%L,'s5-dist-approve-001')$$,
  :'s5_org',:'s5_distribution',:'s5_posting_date'));
select approval_journal_batch_id as s5_distribution_batch from public.s5_distributions where id=:'s5_distribution' \gset
select 1/case when (
  select sum(debit_minor_units)=1 and sum(credit_minor_units)=1
  from public.journal_lines where batch_id=:'s5_distribution_batch'
) then 1 else 0 end as s5_distribution_approval_journal_balanced;
select 1/case when (select paid_minor_units='0' and outstanding_minor_units='1' and settlement_status='APPROVED' from public.s5_distributions_read where distribution_id=:'s5_distribution') then 1 else 0 end as s5_approved_payable_still_unpaid;

select s5_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_pay_distribution(%L,%L,%L,1,%L,'S5-PAY-EVIDENCE-001','s5-dist-pay-001')$$,
  :'s5_org',:'s5_distribution',:'s5_cash_account',:'s5_posting_date'));
select 1/case when (select paid_minor_units='1' and outstanding_minor_units='0' and settlement_status='PAID' from public.s5_distributions_read where distribution_id=:'s5_distribution') then 1 else 0 end as s5_distribution_payment_settles_payable;
select 1/case when s5_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_pay_distribution(%L,%L,%L,1,%L,'S5-PAY-EVIDENCE-OVER','s5-dist-pay-over')$$,
  :'s5_org',:'s5_distribution',:'s5_cash_account',:'s5_posting_date'),'P0001','%exceeds approved outstanding payable%') then 1 else 0 end as s5_overpayment_rejected;

-- Investor statement must reconcile exactly from canonical journal facts.
select 1/case when (
  select closing_capital_minor_units::bigint=
    opening_capital_minor_units::bigint+contributions_minor_units::bigint+
    allocated_income_minor_units::bigint-allocated_loss_minor_units::bigint-
    approved_distributions_minor_units::bigint
  from public.s5_partner_capital_statement_read
  where project_id=:'s5_project' and participant_party_id=:'s5_party'
) then 1 else 0 end as s5_partner_capital_rollforward_exact;

-- Prepare and approve another one-unit payable for the two-session shell race.
select s5_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_prepare_distribution(%L,%L,%L,%L,1,'S5-CONCURRENCY-EVIDENCE','s5-concurrency-dist-prepare')$$,
  :'s5_org',:'s5_project',:'s5_run_id',:'s5_party'));
select id as s5_concurrency_distribution from public.s5_distributions where organization_id=:'s5_org' and idempotency_key='s5-concurrency-dist-prepare' \gset
select s5_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s5_approve_distribution(%L,%L,%L,'s5-concurrency-dist-approve')$$,
  :'s5_org',:'s5_concurrency_distribution',:'s5_posting_date'));
select 1/case when (select outstanding_minor_units='1' from public.s5_distributions_read where distribution_id=:'s5_concurrency_distribution') then 1 else 0 end as s5_concurrency_fixture_ready;

select 'S5 allocation and distribution SQL PASS' as result;
