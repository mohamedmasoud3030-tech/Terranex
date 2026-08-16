-- S5 test-only capacity and segregation-of-duties fixture.
-- Earlier S2/S4 scenarios are intentionally free to consume project cash and
-- leave supplier payables. S5 payment verification needs a positive capacity
-- without changing the already frozen S6 allocation source. The fixture also
-- adds a second OWNER so maker/checker separation is exercised with two users
-- who both have approval authority. This file is test data, never a production path.

insert into auth.users(id) values ('00000000-0000-4000-8000-000000000003')
on conflict (id) do nothing;
insert into public.memberships(organization_id,user_id,role,status)
values (
  '10000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000003',
  'OWNER',
  'ACTIVE'
)
on conflict (organization_id,user_id) do update
set role='OWNER',status='ACTIVE';

-- Synthetic policy activation: S5 allocation/distribution writes now require an
-- approved INVESTOR_ECONOMICS policy. TEST DATA only; the migration schema ships
-- with an EMPTY policy_authority (policy-inert) and no target-company row.
insert into public.policy_authority(organization_id,scope,policy_version,evidence_reference,approved_by)
values ('10000000-0000-4000-8000-000000000001','INVESTOR_ECONOMICS','S5-MECHANISM-TEST-V1','S5-TEST-SYNTHETIC-POLICY','00000000-0000-4000-8000-000000000001')
on conflict (organization_id,scope) do nothing;

do $$
declare
  v_org uuid := '10000000-0000-4000-8000-000000000001';
  v_user uuid := '00000000-0000-4000-8000-000000000001';
  v_project uuid;
  v_currency text;
  v_party uuid;
  v_cash_account uuid;
  v_posting_date date;
  v_bank uuid;
  v_capital uuid;
  v_batch uuid;
  v_cash numeric := 0;
  v_supplier numeric := 0;
  v_distribution numeric := 0;
  v_topup bigint;
begin
  select id,reporting_currency into v_project,v_currency
  from public.investment_projects where organization_id=v_org and name='مشروع النخيل' limit 1;
  select pp.party_id into v_party
  from public.project_participants pp
  join public.commitment_terms ct on ct.participant_id=pp.id and ct.organization_id=pp.organization_id
  join public.agreement_versions av on av.id=ct.agreement_version_id and av.status='ACTIVE'
  where pp.organization_id=v_org and pp.project_id=v_project and pp.role='INVESTOR'
  order by pp.party_id limit 1;
  select id into v_cash_account from public.project_cash_accounts
  where organization_id=v_org and project_id=v_project and currency=v_currency order by id limit 1;
  select start_date into v_posting_date from public.accounting_periods
  where organization_id=v_org and project_id=v_project and status='OPEN'
  order by version desc limit 1;
  select id into v_bank from public.semantic_accounts where role='BANK_CASH';
  select id into v_capital from public.semantic_accounts where role='CONTRIBUTED_CAPITAL';

  if v_project is null or v_party is null or v_cash_account is null or v_posting_date is null then
    raise exception 'S5 capacity fixture prerequisites are missing';
  end if;

  select
    coalesce(sum(case when sa.role='BANK_CASH' then jl.debit_minor_units::numeric-jl.credit_minor_units::numeric else 0 end),0),
    coalesce(sum(case when sa.role='SUPPLIER_PAYABLE' then jl.credit_minor_units::numeric-jl.debit_minor_units::numeric else 0 end),0),
    coalesce(sum(case when sa.role='DISTRIBUTION_PAYABLE' then jl.credit_minor_units::numeric-jl.debit_minor_units::numeric else 0 end),0)
  into v_cash,v_supplier,v_distribution
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.organization_id=v_org and jl.project_id=v_project and jl.currency=v_currency;

  v_topup := (greatest(greatest(v_supplier,0)+greatest(v_distribution,0)-v_cash,0)+1000)::bigint;
  if v_topup>0 then
    insert into public.journal_batches(
      organization_id,project_id,source_type,source_id,transaction_date,
      idempotency_key,request_hash,posted_by
    ) values(
      v_org,v_project,'CONTRIBUTION_CASH_ATTRIBUTION','f5000000-0000-4000-8000-000000000019',v_posting_date,
      's5-test-capacity-fixture',repeat('5',64),v_user
    ) returning id into v_batch;

    insert into public.journal_lines(
      batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,
      currency,cash_account_id,party_id,transaction_date
    ) values
      (v_batch,v_org,v_project,v_bank,v_topup,0,v_currency,v_cash_account,null,v_posting_date),
      (v_batch,v_org,v_project,v_capital,0,v_topup,v_currency,null,v_party,v_posting_date);
  end if;
end $$;

select 1/case when public.s5_project_distributable_cash_internal(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.investment_projects where organization_id='10000000-0000-4000-8000-000000000001' and name='مشروع النخيل' limit 1),
  (select reporting_currency from public.investment_projects where organization_id='10000000-0000-4000-8000-000000000001' and name='مشروع النخيل' limit 1)
)>0 then 1 else 0 end as s5_distribution_capacity_fixture_ready;
