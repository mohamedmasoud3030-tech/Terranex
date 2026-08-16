-- R5 — basic held-property rental income behavioral/security gate.
-- Fresh replay is supplied by scripts/db-test.sh. This suite creates its own
-- organization/project/property so it is independent of earlier S3/S4 fixture
-- lifecycle changes.

create or replace function r5_expect_raise(p_user uuid,p_sql text,p_sqlstate text default 'P0001')
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
  return false;
exception when others then
  reset role;
  return sqlstate=p_sqlstate;
end $$;

create or replace function r5_run(p_user uuid,p_sql text)
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

create or replace function r5_count_as(p_user uuid,p_sql text)
returns bigint language plpgsql as $$
declare v bigint;
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql into v;
  reset role;
  return v;
exception when others then
  reset role;
  raise;
end $$;

-- ---------------------------------------------------------------------------
-- Security/shape contract
-- ---------------------------------------------------------------------------
do $$
declare p record;
begin
  if not exists(select 1 from public.semantic_accounts where role='REAL_ESTATE_RENTAL_REVENUE') then
    raise exception 'R5 ASSERTION FAILED: rental revenue semantic account missing';
  end if;
  if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='property_rental_income_read' and c.relkind='v') then
    raise exception 'R5 ASSERTION FAILED: rental income read model missing';
  end if;
  if has_table_privilege('anon','public.property_rental_income_recognitions','select')
     or has_table_privilege('anon','public.property_rental_income_read','select') then
    raise exception 'R5 ASSERTION FAILED: anon can read rental facts';
  end if;
  if has_table_privilege('authenticated','public.property_rental_income_recognitions','insert')
     or has_table_privilege('authenticated','public.property_rental_collections','insert') then
    raise exception 'R5 ASSERTION FAILED: authenticated can bypass rental command RPCs';
  end if;

  for p in
    select n.nspname,p.proname,p.oid
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
      and p.proname in ('recognize_property_rental_income','collect_property_rental_receivable','reconcile_property_rental_collection')
  loop
    if has_function_privilege('public',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute') then
      raise exception 'R5 ASSERTION FAILED: %.% is executable by PUBLIC/anon',p.nspname,p.proname;
    end if;
    if not has_function_privilege('authenticated',p.oid,'execute') then
      raise exception 'R5 ASSERTION FAILED: %.% is not executable by authenticated',p.nspname,p.proname;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Independent fixture: OWNER, MEMBER and hostile tenant
-- ---------------------------------------------------------------------------
insert into auth.users(id) values
  ('e5000000-0000-4000-8000-0000000000a1'),
  ('e5000000-0000-4000-8000-0000000000a2'),
  ('e5000000-0000-4000-8000-0000000000a3')
on conflict(id) do nothing;
insert into public.organizations(id,name) values
  ('e5000000-0000-4000-8000-000000000001','منظمة R5 للإيجار'),
  ('e5000000-0000-4000-8000-000000000002','منظمة R5 المعزولة')
on conflict(id) do nothing;
insert into public.memberships(organization_id,user_id,role,status) values
  ('e5000000-0000-4000-8000-000000000001','e5000000-0000-4000-8000-0000000000a1','OWNER','ACTIVE'),
  ('e5000000-0000-4000-8000-000000000001','e5000000-0000-4000-8000-0000000000a2','MEMBER','ACTIVE'),
  ('e5000000-0000-4000-8000-000000000002','e5000000-0000-4000-8000-0000000000a3','OWNER','ACTIVE')
on conflict(organization_id,user_id) do update set role=excluded.role,status=excluded.status;

select r5_run('e5000000-0000-4000-8000-0000000000a1',
  $$select public.create_investment_project('e5000000-0000-4000-8000-000000000001','مشروع R5 احتفاظ وإيجار','R5-RENT','اختبار إيجار مستقل','REAL_ESTATE')$$);
select id as r5_project from public.investment_projects
where organization_id='e5000000-0000-4000-8000-000000000001' and name='مشروع R5 احتفاظ وإيجار' \gset

select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.create_real_estate_profile('e5000000-0000-4000-8000-000000000001',%L,'ACQUIRE_HOLD','مسقط، عُمان','r5-rent-profile-001')$$,:'r5_project'));
select r5_run('e5000000-0000-4000-8000-0000000000a2',format(
  $$select public.create_property_asset('e5000000-0000-4000-8000-000000000001',%L,'أصل R5 مؤجر','R5-PROP-001','r5-rent-asset-0001')$$,:'r5_project'));
select id as r5_asset from public.property_assets where idempotency_key='r5-rent-asset-0001' \gset

select r5_run('e5000000-0000-4000-8000-0000000000a1',
  $$select public.create_party('e5000000-0000-4000-8000-000000000001','بائع R5','ORGANIZATION')$$);
select r5_run('e5000000-0000-4000-8000-0000000000a1',
  $$select public.create_party('e5000000-0000-4000-8000-000000000001','مستأجر R5','ORGANIZATION')$$);
select id as r5_seller from public.parties where organization_id='e5000000-0000-4000-8000-000000000001' and legal_name='بائع R5' \gset
select id as r5_tenant from public.parties where organization_id='e5000000-0000-4000-8000-000000000001' and legal_name='مستأجر R5' \gset

-- Reach HELD through the production lifecycle/evidence commands. Acquisition,
-- title and possession remain independent facts; no payment is inferred.
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.transition_property_asset('e5000000-0000-4000-8000-000000000001',%L,'CANDIDATE','DUE_DILIGENCE','بدء الفحص','R5-DD','r5-rent-dd-00001')$$,:'r5_asset'));
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.record_property_acquisition('e5000000-0000-4000-8000-000000000001',%L,%L,'R5-ACQ-001',5000000,50000,'EGP',current_date-30,null,'R5-ACQ-EVIDENCE','r5-rent-acq-0001')$$,:'r5_asset',:'r5_seller'));
select r5_run('e5000000-0000-4000-8000-0000000000a2',format(
  $$select public.record_property_control('e5000000-0000-4000-8000-000000000001',%L,null,'ACQUISITION_CHECK','فحص R5','PASSED',current_date-20,null,'ناجح','e5000000-0000-4000-8000-0000000000a2','R5-DD-PASS',null,'r5-rent-dd-pass')$$,:'r5_asset'));
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.transition_property_asset('e5000000-0000-4000-8000-000000000001',%L,'DUE_DILIGENCE','ACQUIRING','اجتاز الفحص','R5-DD-PASS','r5-rent-acquiring')$$,:'r5_asset'));
select r5_run('e5000000-0000-4000-8000-0000000000a2',format(
  $$select public.record_property_control('e5000000-0000-4000-8000-000000000001',%L,null,'TITLE','سند R5','PASSED',current_date-10,null,'ساري','e5000000-0000-4000-8000-0000000000a2','R5-TITLE',null,'r5-rent-title-01')$$,:'r5_asset'));
select r5_run('e5000000-0000-4000-8000-0000000000a2',format(
  $$select public.record_property_control('e5000000-0000-4000-8000-000000000001',%L,null,'POSSESSION','استلام R5','PASSED',current_date-9,null,'تم الاستلام','e5000000-0000-4000-8000-0000000000a2','R5-POSSESSION',null,'r5-rent-pos-0001')$$,:'r5_asset'));
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.transition_property_asset('e5000000-0000-4000-8000-000000000001',%L,'ACQUIRING','HELD','اكتمل السند والاستلام','R5-TITLE + R5-POSSESSION','r5-rent-held-001')$$,:'r5_asset'));
select 1/case when public.s3_current_property_state(:'r5_asset')='HELD' then 1 else 0 end as r5_property_is_held;

select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.create_project_cash_account('e5000000-0000-4000-8000-000000000001',%L,'حساب R5','EGP')$$,:'r5_project'));
select id as r5_cash from public.project_cash_accounts where project_id=:'r5_project' and name='حساب R5' \gset

-- MEMBER cannot recognize economic truth: material recognition is OWNER-only.
select 1/case when r5_expect_raise('e5000000-0000-4000-8000-0000000000a2',format(
  $$select public.recognize_property_rental_income('e5000000-0000-4000-8000-000000000001',%L,%L,%L,'R5-LEASE-001',current_date-5,current_date,120000,'EGP',current_date,'R5-LEASE-EVIDENCE','r5-rent-recognize-member')$$,
  :'r5_project',:'r5_asset',:'r5_tenant')) then 1 else 0 end as r5_recognition_owner_only;

-- Recognition creates exactly one receivable/revenue posting. It does not
-- create cash and it does not reuse sale revenue.
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.recognize_property_rental_income('e5000000-0000-4000-8000-000000000001',%L,%L,%L,'R5-LEASE-001',current_date-5,current_date,120000,'EGP',current_date,'R5-LEASE-EVIDENCE','r5-rent-recognize-01')$$,
  :'r5_project',:'r5_asset',:'r5_tenant'));
select id as r5_recognition from public.property_rental_income_recognitions where idempotency_key='r5-rent-recognize-01' \gset
select journal_batch_id as r5_recognition_batch from public.property_rental_income_recognitions where id=:'r5_recognition' \gset
select 1/case when (
  select count(*)=2 and sum(debit_minor_units)=120000 and sum(credit_minor_units)=120000
  from public.journal_lines where batch_id=:'r5_recognition_batch'
) then 1 else 0 end as r5_recognition_balanced;
select 1/case when (
  select count(*)=2 from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=:'r5_recognition_batch'
    and ((sa.role='CUSTOMER_RECEIVABLE' and jl.debit_minor_units=120000 and jl.credit_minor_units=0)
      or (sa.role='REAL_ESTATE_RENTAL_REVENUE' and jl.credit_minor_units=120000 and jl.debit_minor_units=0))
) then 1 else 0 end as r5_recognition_exact_accounts;

-- Same key/same payload is one effect; same key/different payload and duplicate
-- active business period are rejected.
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.recognize_property_rental_income('e5000000-0000-4000-8000-000000000001',%L,%L,%L,'R5-LEASE-001',current_date-5,current_date,120000,'EGP',current_date,'R5-LEASE-EVIDENCE','r5-rent-recognize-01')$$,
  :'r5_project',:'r5_asset',:'r5_tenant'));
select 1/case when (select count(*) from public.property_rental_income_recognitions where idempotency_key='r5-rent-recognize-01')=1
  and (select count(*) from public.journal_batches where source_type='PROPERTY_RENTAL_RECOGNITION' and source_id=:'r5_recognition')=1
  then 1 else 0 end as r5_recognition_retry_single_effect;
select 1/case when r5_expect_raise('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.recognize_property_rental_income('e5000000-0000-4000-8000-000000000001',%L,%L,%L,'R5-LEASE-001',current_date-5,current_date,120001,'EGP',current_date,'R5-LEASE-EVIDENCE','r5-rent-recognize-01')$$,
  :'r5_project',:'r5_asset',:'r5_tenant')) then 1 else 0 end as r5_idempotency_payload_mismatch_rejected;
select 1/case when r5_expect_raise('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.recognize_property_rental_income('e5000000-0000-4000-8000-000000000001',%L,%L,%L,'R5-LEASE-001',current_date-5,current_date,120000,'EGP',current_date,'R5-LEASE-EVIDENCE','r5-rent-recognize-02')$$,
  :'r5_project',:'r5_asset',:'r5_tenant')) then 1 else 0 end as r5_duplicate_active_period_rejected;

-- F9 and the R8 sector roll-up see rent as recognized revenue while cash stays
-- zero before collection. This prevents a disconnected rental sub-ledger.
select 1/case when (
  select revenue_recognized_minor_units='120000' and receivable_open_minor_units='120000'
    and cash_balance_minor_units='0'
  from public.project_financial_position_read where project_id=:'r5_project'
) then 1 else 0 end as r5_f9_includes_rent_before_collection;
select 1/case when exists(
  select 1 from public.sector_performance_read
  where organization_id='e5000000-0000-4000-8000-000000000001'
    and sector='REAL_ESTATE' and currency='EGP' and revenue_recognized_minor_units='120000'
) then 1 else 0 end as r5_r8_sector_rollup_includes_rent;

-- Partial collection is independent from recognition and reduces receivable.
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.collect_property_rental_receivable('e5000000-0000-4000-8000-000000000001',%L,%L,70000,current_date,'R5-BANK-RECEIPT-1','r5-rent-collect-001')$$,
  :'r5_recognition',:'r5_cash'));
select id as r5_collection from public.property_rental_collections where idempotency_key='r5-rent-collect-001' \gset
select 1/case when (
  select collected_minor_units='70000' and outstanding_receivable_minor_units='50000'
  from public.property_rental_income_read where recognition_id=:'r5_recognition'
) then 1 else 0 end as r5_partial_collection_rollforward;
select 1/case when (
  select revenue_recognized_minor_units='120000' and receivable_open_minor_units='50000'
    and cash_balance_minor_units='70000'
  from public.project_financial_position_read where project_id=:'r5_project'
) then 1 else 0 end as r5_collection_changes_cash_not_revenue;

-- Concurrent ceiling is serialized by the recognition row lock in the command;
-- deterministic over-collection must fail and leave no half-posting.
select count(*) as r5_batches_before_overcollect from public.journal_batches \gset
select 1/case when r5_expect_raise('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.collect_property_rental_receivable('e5000000-0000-4000-8000-000000000001',%L,%L,50001,current_date,'R5-BANK-RECEIPT-OVER','r5-rent-collect-over')$$,
  :'r5_recognition',:'r5_cash')) then 1 else 0 end as r5_overcollection_rejected;
select 1/case when (select count(*) from public.journal_batches)=:'r5_batches_before_overcollect' then 1 else 0 end as r5_failed_overcollection_atomic;

-- External bank fact fixture, then the production reconciliation RPC. The
-- shared reservation primitive proves the bank line has one active economic
-- match across payment/property-sale/rental types.
insert into public.bank_statement_imports(
  organization_id,project_id,cash_account_id,line_count,idempotency_key,request_hash,imported_by
) values(
  'e5000000-0000-4000-8000-000000000001',:'r5_project',:'r5_cash',1,
  'r5-bank-import-001',repeat('a',64),'e5000000-0000-4000-8000-0000000000a1'
) returning id as r5_import \gset
insert into public.bank_statement_lines(
  organization_id,project_id,cash_account_id,import_id,provider_reference,transaction_date,
  amount_minor_units,currency,description,fingerprint
) values(
  'e5000000-0000-4000-8000-000000000001',:'r5_project',:'r5_cash',:'r5_import',
  'R5-BANK-LINE-1',current_date,70000,'EGP','تحصيل إيجار R5',repeat('b',64)
) returning id as r5_statement_line \gset

select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.reconcile_property_rental_collection('e5000000-0000-4000-8000-000000000001',%L,%L,'r5-rent-reconcile-01')$$,
  :'r5_collection',:'r5_statement_line'));
select 1/case when exists(
  select 1 from public.bank_statement_reconciliation_allocations
  where statement_line_id=:'r5_statement_line' and match_type='PROPERTY_RENTAL_COLLECTION'
) then 1 else 0 end as r5_bank_line_reserved_by_rental;
select 1/case when (select is_reconciled from public.property_rental_collections_read where collection_id=:'r5_collection')
  then 1 else 0 end as r5_collection_reconciled;
select 1/case when r5_expect_raise('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.reconcile_property_rental_collection('e5000000-0000-4000-8000-000000000001',%L,%L,'r5-rent-reconcile-02')$$,
  :'r5_collection',:'r5_statement_line')) then 1 else 0 end as r5_second_reconciliation_rejected;

-- Hostile organization sees no read rows and cannot invoke a command against
-- the other tenant's recognition.
select 1/case when r5_count_as('e5000000-0000-4000-8000-0000000000a3',format(
  $$select count(*) from public.property_rental_income_read where recognition_id=%L$$,:'r5_recognition'))=0
  then 1 else 0 end as r5_cross_tenant_read_hidden;
select 1/case when r5_expect_raise('e5000000-0000-4000-8000-0000000000a3',format(
  $$select public.collect_property_rental_receivable('e5000000-0000-4000-8000-000000000001',%L,%L,1,current_date,'hostile','r5-hostile-collect')$$,
  :'r5_recognition',:'r5_cash')) then 1 else 0 end as r5_cross_tenant_command_denied;

-- Browser direct DML remains denied even for a legitimate tenant member.
do $$
begin
  perform set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-0000000000a2',true);
  execute 'set role authenticated';
  begin
    insert into public.property_rental_collections(
      organization_id,project_id,recognition_id,cash_account_id,amount_minor_units,currency,
      collection_date,evidence_reference,journal_batch_id,collected_by,idempotency_key,request_hash
    ) values(
      'e5000000-0000-4000-8000-000000000001',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),1,
      'EGP',current_date,'bad',gen_random_uuid(),'e5000000-0000-4000-8000-0000000000a2','r5-direct-dml',repeat('c',64));
    raise exception 'direct rental browser DML unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;

select 'R5 basic property rental income PASS' as result;
