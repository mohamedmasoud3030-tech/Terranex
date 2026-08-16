-- GF-008 / S5 — canonical allocation/distribution verification.
-- Compact assertions cover accounting, tenancy, idempotency, provenance,
-- deterministic allocation, maker/checker SoD, and settlement invariants.

\set s5_checker '00000000-0000-4000-8000-000000000001'
\set s5_outsider '00000000-0000-4000-8000-000000000002'
\set s5_maker '00000000-0000-4000-8000-000000000003'

create or replace function s5_assert(p_ok boolean,p_message text)
returns void language plpgsql as $$
begin
  if not coalesce(p_ok,false) then
    raise exception 'S5 assertion failed: %',p_message;
  end if;
end $$;

create or replace function s5_expect_raise(
  p_user uuid,p_sql text,p_message_like text
) returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
  return false;
exception when others then
  reset role;
  return sqlerrm like p_message_like;
end $$;

create or replace function s5_expect_raise_admin(
  p_sql text,p_message_like text
) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return sqlerrm like p_message_like;
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

select id s5_project,organization_id s5_org,reporting_currency s5_currency
from public.investment_projects where name='مشروع النخيل' limit 1 \gset
select id s5_version from public.agreement_versions
where project_id=:'s5_project' and status='ACTIVE' limit 1 \gset
select s.id s5_snapshot,s.period_id s5_source_period
from public.close_run_snapshots s
where s.organization_id=:'s5_org' and s.project_id=:'s5_project'
  and public.s5_realized_result_as_of_snapshot(s.organization_id,s.project_id,s.id)<>0
order by s.captured_at limit 1 \gset
select public.s5_realized_result_as_of_snapshot(
  :'s5_org',:'s5_project',:'s5_snapshot') s5_source_amount \gset
select s5_assert(:'s5_source_amount'::bigint>0,'fixture must contain positive realized result');

-- Commitment rows identify eligible investors only; the independent fixed-share
-- basis deliberately does not use commitment amounts as allocation weights.
select array_agg(pp.party_id order by pp.party_id::text)::text s5_parties,
       array_agg(1::bigint order by pp.party_id::text)::text s5_weights,
       count(*)::bigint s5_denominator
from public.commitment_terms ct
join public.project_participants pp on pp.id=ct.participant_id
where ct.organization_id=:'s5_org'
  and ct.agreement_version_id=:'s5_version'
  and pp.project_id=:'s5_project' and pp.role='INVESTOR' \gset
select s5_assert(:'s5_denominator'::bigint>0,'governing version must contain investors');

select s5_run(:'s5_checker',format(
  $$select public.s5_configure_allocation_rules(%L,%L,%L,'FIXED_SHARES',%L::uuid[],%L::bigint[],%s,'S5-RULE-BASIS-EVIDENCE-001','s5-rules-fixed-001')$$,
  :'s5_org',:'s5_project',:'s5_version',:'s5_parties',:'s5_weights',:'s5_denominator'));
select id s5_rule_set from public.s5_allocation_rule_sets
where organization_id=:'s5_org' and idempotency_key='s5-rules-fixed-001' \gset

select s5_assert((
  select count(*)=:'s5_denominator'::bigint
    and sum(weight_numerator)=:'s5_denominator'::bigint
  from public.s5_allocation_rules where rule_set_id=:'s5_rule_set'
),'rule set must cover every investor and resolve to the denominator');
select s5_assert((
  select basis_evidence_reference='S5-RULE-BASIS-EVIDENCE-001'
    and effective_from is not null and char_length(basis_hash)=64
  from public.s5_allocation_rule_basis where rule_set_id=:'s5_rule_set'
),'allocation basis provenance must be frozen');
select s5_assert(s5_expect_raise_admin(format(
  $$update public.s5_allocation_rules set weight_numerator=weight_numerator+1 where rule_set_id=%L$$,
  :'s5_rule_set'),'%append-only%'),'frozen rules must reject mutation');

-- Retry the same configuration: one rule set, one basis fact.
select s5_run(:'s5_checker',format(
  $$select public.s5_configure_allocation_rules(%L,%L,%L,'FIXED_SHARES',%L::uuid[],%L::bigint[],%s,'S5-RULE-BASIS-EVIDENCE-001','s5-rules-fixed-001')$$,
  :'s5_org',:'s5_project',:'s5_version',:'s5_parties',:'s5_weights',:'s5_denominator'));
select s5_assert((select count(*)=1 from public.s5_allocation_rule_basis
  where rule_set_id=:'s5_rule_set'),'rule configuration retry must have one material effect');

-- OWNER 3 is the maker; OWNER 1 is the checker. Both are privileged to approve,
-- so the self-approval rejection below proves DB-enforced SoD rather than RBAC.
select s5_run(:'s5_maker',format(
  $$select public.s5_prepare_allocation(%L,%L,%L,%L,'REALIZED_RESULT','s5-allocation-prepare-001')$$,
  :'s5_org',:'s5_project',:'s5_snapshot',:'s5_version'));
select id s5_run_id from public.s5_allocation_runs
where organization_id=:'s5_org' and idempotency_key='s5-allocation-prepare-001' \gset
select s5_assert((select prepared_by=:'s5_maker'::uuid
  and source_amount_minor_units=:'s5_source_amount'::bigint
  and snapshot_content_hash=(select content_hash from public.close_run_snapshots where id=:'s5_snapshot')
  from public.s5_allocation_runs where id=:'s5_run_id'),'run must freeze maker and authoritative snapshot provenance');
select s5_assert(public.s5_allocation_lines_are_canonical(:'s5_run_id'),
  'stored lines must equal deterministic largest-remainder result');
select s5_assert((select sum(allocated_minor_units)=:'s5_source_amount'::bigint
  from public.s5_allocation_lines where run_id=:'s5_run_id'),'allocation total must equal source exactly');

select s5_assert(s5_expect_raise(:'s5_checker',format(
  $$select public.s5_approve_allocation(%L,%L,date '1900-01-01','s5-allocation-no-open')$$,
  :'s5_org',:'s5_run_id'),'%OPEN accounting period%'),'posting outside OPEN periods must fail');
select start_date s5_posting_date from public.accounting_periods
where organization_id=:'s5_org' and project_id=:'s5_project' and status='OPEN'
order by version desc limit 1 \gset
select s5_assert(s5_expect_raise(:'s5_maker',format(
  $$select public.s5_approve_allocation(%L,%L,%L,'s5-allocation-self-approve')$$,
  :'s5_org',:'s5_run_id',:'s5_posting_date'),'%s5_allocation_run_maker_checker_check%'),
  'allocation maker must not self-approve even when OWNER');
select s5_run(:'s5_checker',format(
  $$select public.s5_approve_allocation(%L,%L,%L,'s5-allocation-approve-001')$$,
  :'s5_org',:'s5_run_id',:'s5_posting_date'));
select journal_batch_id s5_allocation_batch from public.s5_allocation_runs
where id=:'s5_run_id' \gset
select s5_assert((select approved_by=:'s5_checker'::uuid and prepared_by<>approved_by
  from public.s5_allocation_runs where id=:'s5_run_id'),'allocation checker must differ from maker');
select s5_assert((select sum(debit_minor_units)=sum(credit_minor_units)
  and sum(debit_minor_units)=abs(:'s5_source_amount'::bigint)
  from public.journal_lines where batch_id=:'s5_allocation_batch'),
  'allocation journal must be balanced for the exact source amount');

-- Tenant B cannot see tenant A's S5 run.
select s5_run(:'s5_outsider',format(
  $$select public.s5_assert((select count(*)=0 from public.s5_allocation_runs_read where project_id=%L),'cross-tenant S5 rows leaked')$$,
  :'s5_project'));

select participant_party_id s5_party from public.s5_allocation_lines
where run_id=:'s5_run_id' and allocated_minor_units>0
order by participant_party_id::text limit 1 \gset
select ca.id s5_cash_account from public.project_cash_accounts ca
where ca.organization_id=:'s5_org' and ca.project_id=:'s5_project' and ca.currency=:'s5_currency'
  and public.s5_cash_account_balance_internal(ca.organization_id,ca.project_id,ca.id,ca.currency)>0
order by ca.id limit 1 \gset
select s5_assert(public.s5_project_distributable_cash_internal(
  :'s5_org',:'s5_project',:'s5_currency')>0,'fixture must have distributable cash');

select s5_run(:'s5_maker',format(
  $$select public.s5_prepare_distribution(%L,%L,%L,%L,1,'S5-DIST-EVIDENCE-001','s5-dist-prepare-001')$$,
  :'s5_org',:'s5_project',:'s5_run_id',:'s5_party'));
select id s5_distribution from public.s5_distributions
where organization_id=:'s5_org' and idempotency_key='s5-dist-prepare-001' \gset
select s5_assert(s5_expect_raise(:'s5_maker',format(
  $$select public.s5_approve_distribution(%L,%L,%L,'s5-dist-self-approve')$$,
  :'s5_org',:'s5_distribution',:'s5_posting_date'),'%s5_distribution_maker_checker_check%'),
  'distribution maker must not self-approve even when OWNER');
select s5_run(:'s5_checker',format(
  $$select public.s5_approve_distribution(%L,%L,%L,'s5-dist-approve-001')$$,
  :'s5_org',:'s5_distribution',:'s5_posting_date'));
select s5_assert((select prepared_by=:'s5_maker'::uuid and approved_by=:'s5_checker'::uuid
  and paid_minor_units='0' and outstanding_minor_units='1' and settlement_status='APPROVED'
  from public.s5_distributions_read where distribution_id=:'s5_distribution'),
  'distribution approval must enforce maker/checker SoD and create an unpaid payable');

select s5_run(:'s5_checker',format(
  $$select public.s5_pay_distribution(%L,%L,%L,1,%L,'S5-PAY-EVIDENCE-001','s5-dist-pay-001')$$,
  :'s5_org',:'s5_distribution',:'s5_cash_account',:'s5_posting_date'));
select s5_assert((select outstanding_minor_units='0' and settlement_status='PAID'
  from public.s5_distributions_read where distribution_id=:'s5_distribution'),
  'payment must settle the approved payable');
select s5_assert(s5_expect_raise(:'s5_checker',format(
  $$select public.s5_pay_distribution(%L,%L,%L,1,%L,'S5-PAY-OVER','s5-dist-pay-over')$$,
  :'s5_org',:'s5_distribution',:'s5_cash_account',:'s5_posting_date'),
  '%exceeds approved outstanding payable%'),'overpayment must be rejected');

select s5_assert((select closing_capital_minor_units::bigint=
  opening_capital_minor_units::bigint+contributions_minor_units::bigint+
  allocated_income_minor_units::bigint-allocated_loss_minor_units::bigint-
  approved_distributions_minor_units::bigint
  from public.s5_partner_capital_statement_read
  where project_id=:'s5_project' and participant_party_id=:'s5_party'),
  'partner-capital rollforward must reconcile exactly');

-- Leave one approved one-unit payable for the real two-session race in test 21.
select s5_run(:'s5_maker',format(
  $$select public.s5_prepare_distribution(%L,%L,%L,%L,1,'S5-CONCURRENCY-EVIDENCE','s5-concurrency-dist-prepare')$$,
  :'s5_org',:'s5_project',:'s5_run_id',:'s5_party'));
select id s5_concurrency_distribution from public.s5_distributions
where organization_id=:'s5_org' and idempotency_key='s5-concurrency-dist-prepare' \gset
select s5_run(:'s5_checker',format(
  $$select public.s5_approve_distribution(%L,%L,%L,'s5-concurrency-dist-approve')$$,
  :'s5_org',:'s5_concurrency_distribution',:'s5_posting_date'));
select s5_assert((select outstanding_minor_units='1' from public.s5_distributions_read
  where distribution_id=:'s5_concurrency_distribution'),'concurrency fixture must be ready');

select 'S5 allocation and distribution SQL PASS' result;
