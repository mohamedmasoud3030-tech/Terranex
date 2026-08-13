-- Phase 2C — focused financial-integrity attack suite (sequential cases).
-- Runtime proof of the highest-risk money invariants against the real
-- migration chain. Concurrency races live in 29_phase2c_concurrency.sh.
-- The suite builds one fresh tenant (organization 30000000-...0001) so every
-- assertion is deterministic and independent of earlier fixture state.

create or replace function p2c_assert(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if p_condition is distinct from true then
    raise exception 'Phase 2C assertion failed: %', p_message;
  end if;
end $$;

create or replace function p2c_run(p_user uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql;
  reset role;
end $$;

create or replace function p2c_expect_raise(p_user uuid, p_sql text, p_sqlstate text, p_message_like text default null)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql;
  reset role;
  return false;
exception when others then
  reset role;
  return sqlstate = p_sqlstate
    and (p_message_like is null or sqlerrm like p_message_like);
end $$;

create or replace function p2c_expect_raise_admin(p_sql text, p_sqlstate text, p_message_like text default null)
returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return sqlstate = p_sqlstate
    and (p_message_like is null or sqlerrm like p_message_like);
end $$;

-- ---------------------------------------------------------------------------
-- Test-only identity fixture (mirrors 19_s5_distribution_capacity_fixture.sql):
-- two OWNERs (maker/checker separation) and one plain MEMBER.
-- ---------------------------------------------------------------------------
insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000011'),
  ('00000000-0000-4000-8000-000000000012'),
  ('00000000-0000-4000-8000-000000000013')
on conflict (id) do nothing;
insert into public.organizations(id,name) values
  ('30000000-0000-4000-8000-000000000001','منظمة الفحص المالي 2C')
on conflict (id) do nothing;
insert into public.memberships(organization_id,user_id,role,status) values
  ('30000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000011','OWNER','ACTIVE'),
  ('30000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000012','OWNER','ACTIVE'),
  ('30000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000013','MEMBER','ACTIVE')
on conflict (organization_id,user_id) do update set role=excluded.role, status=excluded.status;

\set p2c_org '30000000-0000-4000-8000-000000000001'
\set p2c_owner1 '00000000-0000-4000-8000-000000000011'
\set p2c_owner2 '00000000-0000-4000-8000-000000000012'
\set p2c_member '00000000-0000-4000-8000-000000000013'
\set p2c_outsider '00000000-0000-4000-8000-000000000002'
\set p2c_sum_mismatch 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
\set p2c_sum_clean 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
\set p2c_sum_second 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'

-- ---------------------------------------------------------------------------
-- Project, parties, cash account, governing agreement with three investors.
-- ---------------------------------------------------------------------------
select p2c_run(:'p2c_owner1',
  $$select public.create_investment_project('30000000-0000-4000-8000-000000000001','مشروع الفحص المالي',null,null)$$);
select id as p2c_project from public.investment_projects where name='مشروع الفحص المالي' \gset

select p2c_run(:'p2c_owner1', $$select public.create_party('30000000-0000-4000-8000-000000000001','مورد الفحص','ORGANIZATION')$$);
select p2c_run(:'p2c_owner1', $$select public.create_party('30000000-0000-4000-8000-000000000001','مشتري الفحص','ORGANIZATION')$$);
select p2c_run(:'p2c_owner1', $$select public.create_party('30000000-0000-4000-8000-000000000001','مستثمر فحص أول','PERSON')$$);
select p2c_run(:'p2c_owner1', $$select public.create_party('30000000-0000-4000-8000-000000000001','مستثمر فحص ثانٍ','PERSON')$$);
select p2c_run(:'p2c_owner1', $$select public.create_party('30000000-0000-4000-8000-000000000001','مستثمر فحص ثالث','PERSON')$$);
select id as p2c_supplier from public.parties where legal_name='مورد الفحص' and organization_id=:'p2c_org' \gset
select id as p2c_buyer from public.parties where legal_name='مشتري الفحص' and organization_id=:'p2c_org' \gset
select id as p2c_inv1 from public.parties where legal_name='مستثمر فحص أول' and organization_id=:'p2c_org' \gset
select id as p2c_inv2 from public.parties where legal_name='مستثمر فحص ثانٍ' and organization_id=:'p2c_org' \gset
select id as p2c_inv3 from public.parties where legal_name='مستثمر فحص ثالث' and organization_id=:'p2c_org' \gset

select p2c_run(:'p2c_owner1', format(
  $$select public.create_project_cash_account('30000000-0000-4000-8000-000000000001',%L,'حساب فحص 2C','EGP')$$, :'p2c_project'));
select id as p2c_cash from public.project_cash_accounts where name='حساب فحص 2C' \gset

select p2c_run(:'p2c_owner1', format($$select public.add_project_participant('30000000-0000-4000-8000-000000000001',%L,%L)$$, :'p2c_project', :'p2c_inv1'));
select p2c_run(:'p2c_owner1', format($$select public.add_project_participant('30000000-0000-4000-8000-000000000001',%L,%L)$$, :'p2c_project', :'p2c_inv2'));
select p2c_run(:'p2c_owner1', format($$select public.add_project_participant('30000000-0000-4000-8000-000000000001',%L,%L)$$, :'p2c_project', :'p2c_inv3'));
select id as p2c_part1 from public.project_participants where party_id=:'p2c_inv1' \gset
select id as p2c_part2 from public.project_participants where party_id=:'p2c_inv2' \gset
select id as p2c_part3 from public.project_participants where party_id=:'p2c_inv3' \gset

select p2c_run(:'p2c_owner1', format(
  $$select public.create_agreement_draft('30000000-0000-4000-8000-000000000001',%L,date '2026-07-01',array[%L::uuid,%L::uuid,%L::uuid],array[334000,333000,333000]::bigint[],'p2c-agreement-0001')$$,
  :'p2c_project', :'p2c_part1', :'p2c_part2', :'p2c_part3'));
select id as p2c_version from public.agreement_versions where idempotency_key='p2c-agreement-0001' \gset
select p2c_run(:'p2c_owner1', format($$select public.activate_agreement_version('30000000-0000-4000-8000-000000000001',%L)$$, :'p2c_version'));

-- ---------------------------------------------------------------------------
-- S3 lifecycle to HELD with authoritative history and control evidence.
-- ---------------------------------------------------------------------------
select p2c_run(:'p2c_owner1', format($$select public.create_real_estate_profile('30000000-0000-4000-8000-000000000001',%L,'DEVELOP_SELL','القاهرة، مصر','p2c-profile-001')$$, :'p2c_project'));
select p2c_run(:'p2c_owner1', format($$select public.create_property_asset('30000000-0000-4000-8000-000000000001',%L,'أصل الفحص المالي','P2C-PROP-001','p2c-asset-0001')$$, :'p2c_project'));
select id as p2c_asset from public.property_assets where idempotency_key='p2c-asset-0001' \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.record_property_acquisition('30000000-0000-4000-8000-000000000001',%L,%L,'P2C-ACQ-001',500000,25000,'EGP',current_date-10,null,'عقد شراء موقع P2C-ACQ-001','p2c-acquisition-001')$$,
  :'p2c_asset', :'p2c_supplier'));
select p2c_run(:'p2c_owner1', format($$select public.transition_property_asset('30000000-0000-4000-8000-000000000001',%L,'CANDIDATE','DUE_DILIGENCE','بدء الفحص النافي للجهالة','مذكرة قرار P2C-DD','p2c-state-dd-0001')$$, :'p2c_asset'));
select p2c_run(:'p2c_owner1', format(
  $$select public.record_property_control('30000000-0000-4000-8000-000000000001',%L,null,'ACQUISITION_CHECK','فحص قانوني للعقد','PASSED',current_date-6,null,'لا توجد موانع مسجلة','00000000-0000-4000-8000-000000000011','P2C-DD-CHK-001','تمت مراجعة سلسلة العقود','p2c-control-dd-001')$$,
  :'p2c_asset'));
select p2c_run(:'p2c_owner1', format($$select public.transition_property_asset('30000000-0000-4000-8000-000000000001',%L,'DUE_DILIGENCE','ACQUIRING','اجتياز الفحص وتسجيل العقد','تقرير قانوني P2C-44','p2c-state-acq-001')$$, :'p2c_asset'));
select p2c_run(:'p2c_owner1', format(
  $$select public.record_property_control('30000000-0000-4000-8000-000000000001',%L,null,'TITLE','سند ملكية مسجل','PASSED',current_date-5,null,'السند يغطي الأصل','00000000-0000-4000-8000-000000000011','P2C-TITLE-ACQ',null,'p2c-control-title-acq')$$,
  :'p2c_asset'));
select p2c_run(:'p2c_owner1', format(
  $$select public.record_property_control('30000000-0000-4000-8000-000000000001',%L,null,'POSSESSION','حيازة فعلية عند الشراء','PASSED',current_date-5,null,'الحيازة مكتملة','00000000-0000-4000-8000-000000000011','P2C-POS-ACQ',null,'p2c-control-pos-acq')$$,
  :'p2c_asset'));
select p2c_run(:'p2c_owner1', format($$select public.transition_property_asset('30000000-0000-4000-8000-000000000001',%L,'ACQUIRING','HELD','إثبات السيطرة','سند مسجل P2C-TITLE-ACQ','p2c-state-held-001')$$, :'p2c_asset'));

-- ---------------------------------------------------------------------------
-- S2 obligations (all fixture postings dated current_date-5 so they fall
-- inside the first close period).
-- ---------------------------------------------------------------------------
select p2c_run(:'p2c_owner1', format(
  $$select public.create_cost_obligation('30000000-0000-4000-8000-000000000001',%L,%L,'أعمال تطوير الفحص',100000,'EGP',current_date-5,'EXPENSE','p2c-obl-main-0001')$$,
  :'p2c_project', :'p2c_supplier'));
select id as p2c_obligation from public.cost_obligations where idempotency_key='p2c-obl-main-0001' \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.authorize_cost_obligation('30000000-0000-4000-8000-000000000001',%L,'p2c-obl-auth-001')$$, :'p2c_obligation'));

select p2c_run(:'p2c_owner1', format(
  $$select public.create_cost_obligation('30000000-0000-4000-8000-000000000001',%L,%L,'تطوير رأسمالي للفحص',400000,'EGP',current_date-5,'CAPITALIZABLE_WIP','p2c-obl-wip-0001')$$,
  :'p2c_project', :'p2c_supplier'));
select id as p2c_wip_obligation from public.cost_obligations where idempotency_key='p2c-obl-wip-0001' \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.authorize_cost_obligation('30000000-0000-4000-8000-000000000001',%L,'p2c-wip-auth-001')$$, :'p2c_wip_obligation'));
select p2c_run(:'p2c_owner1', format(
  $$select public.classify_property_cost('30000000-0000-4000-8000-000000000001',%L,%L,null,null,'CONSTRUCTION','قرار رسملة WIP للفحص','p2c-cost-class-001')$$,
  :'p2c_wip_obligation', :'p2c_asset'));

-- ---------------------------------------------------------------------------
-- S4 sale chain with proceeds 1000001 (deliberately indivisible by 3 later).
-- Realized result will be 1000001 - 400000 carrying cost = 600001.
-- ---------------------------------------------------------------------------
select p2c_run(:'p2c_owner1', format(
  $$select public.create_property_disposition('30000000-0000-4000-8000-000000000001',%L,%L,%L,'P2C-DISP-001','عقد بيع موقع P2C-DISP-001',1000001,'EGP',current_date-8,current_date-5,'p2c-disposition-001')$$,
  :'p2c_project', :'p2c_asset', :'p2c_buyer'));
select id as p2c_disposition from public.property_dispositions where idempotency_key='p2c-disposition-001' \gset
select p2c_run(:'p2c_owner1', format($$select public.approve_property_disposition('30000000-0000-4000-8000-000000000001',%L,'p2c-disp-approve-01')$$, :'p2c_disposition'));
select p2c_run(:'p2c_owner1', format($$select public.transition_property_asset('30000000-0000-4000-8000-000000000001',%L,'HELD','EXITING','بدء تخارج الفحص','P2C-DISP-001','p2c-state-exiting-01')$$, :'p2c_asset'));
select p2c_run(:'p2c_owner1', format(
  $$select public.record_property_control('30000000-0000-4000-8000-000000000001',%L,null,'TITLE','سند ملكية عند التخارج','PASSED',current_date-5,null,'السند يغطي الأصل كاملًا','00000000-0000-4000-8000-000000000011','P2C-TITLE-EXIT',null,'p2c-control-title-exit')$$,
  :'p2c_asset'));
select p2c_run(:'p2c_owner1', format(
  $$select public.record_property_control('30000000-0000-4000-8000-000000000001',%L,null,'POSSESSION','حيازة عند التخارج','PASSED',current_date-5,null,'الحيازة مكتملة','00000000-0000-4000-8000-000000000011','P2C-POS-EXIT',null,'p2c-control-pos-exit')$$,
  :'p2c_asset'));
select p2c_run(:'p2c_owner1', format(
  $$select public.confirm_property_control_transfer('30000000-0000-4000-8000-000000000001',%L,current_date-5,'محضر تسليم الفحص P2C','p2c-transfer-001')$$,
  :'p2c_disposition'));
select p2c_run(:'p2c_owner1', format(
  $$select public.recognize_property_sale('30000000-0000-4000-8000-000000000001',%L,current_date-5,'p2c-recognize-001')$$,
  :'p2c_disposition'));
select id as p2c_recognition from public.property_sale_recognitions where disposition_id=:'p2c_disposition' \gset

-- ---------------------------------------------------------------------------
-- S6: close the first period, capture the snapshot, then reopen so later
-- postings have an OPEN authoritative period.
-- ---------------------------------------------------------------------------
select p2c_run(:'p2c_owner1', format(
  $$select public.s6_create_accounting_period('30000000-0000-4000-8000-000000000001',%L,current_date-15,current_date-1)$$, :'p2c_project'));
select id as p2c_period1 from public.accounting_periods where project_id=:'p2c_project' and status='OPEN' \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.s6_prepare_close_run('30000000-0000-4000-8000-000000000001',%L,%L,'p2c close v1')$$, :'p2c_project', :'p2c_period1'));
select id as p2c_close_run1 from public.close_runs where period_id=:'p2c_period1' and version=1 \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.s6_approve_close_run('30000000-0000-4000-8000-000000000001',%L,'p2c-close-approve-01')$$, :'p2c_close_run1'));
select p2c_assert((select status='CLOSED' from public.accounting_periods where id=:'p2c_period1'),
  'period v1 must be CLOSED after approval');
select id as p2c_snapshot from public.close_run_snapshots where close_run_id=:'p2c_close_run1' \gset
select p2c_assert(
  (select public.s5_realized_result_as_of_snapshot(:'p2c_org', :'p2c_project', :'p2c_snapshot')) = 600001,
  'closed snapshot realized result must be exactly 600001 minor units');

select p2c_run(:'p2c_owner1', format(
  $$select public.s6_reopen_period('30000000-0000-4000-8000-000000000001',%L,%L,'reopen for post-close activity','p2c-reopen-evidence-01')$$,
  :'p2c_project', :'p2c_period1'));
select id as p2c_period2 from public.accounting_periods where project_id=:'p2c_project' and status='OPEN' \gset
select p2c_assert((select supersedes_period_id=:'p2c_period1' from public.accounting_periods where id=:'p2c_period2'),
  'reopened period must supersede the closed one');

-- ---------------------------------------------------------------------------
-- Item 9: posting into the CLOSED period is rejected at the journal boundary.
-- ---------------------------------------------------------------------------
select p2c_assert(p2c_expect_raise_admin(format(
  $sql$insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    '30000000-0000-4000-8000-000000000001', %L, 'COST_OBLIGATION',
    gen_random_uuid(), current_date-5,
    'p2c-closed-period-posting-01', repeat('a', 64), '00000000-0000-4000-8000-000000000011'
  )$sql$, :'p2c_project'), 'P0001', '%no open accounting period%'),
  'posting dated inside the CLOSED period must be rejected');
select p2c_assert((select count(*)=0 from public.journal_batches where idempotency_key='p2c-closed-period-posting-01'),
  'rejected closed-period posting must leave no batch residue');

-- ---------------------------------------------------------------------------
-- Item 8: an unbalanced journal batch is rejected by the canonical trigger.
-- ---------------------------------------------------------------------------
select p2c_assert(p2c_expect_raise_admin(format(
  $outer$do $inner$
  declare v_batch uuid; v_bank uuid;
  begin
    v_bank := (select id from public.semantic_accounts where role='BANK_CASH');
    insert into public.journal_batches(
      organization_id, project_id, source_type, source_id, transaction_date,
      idempotency_key, request_hash, posted_by
    ) values (
      '30000000-0000-4000-8000-000000000001', %L, 'COST_OBLIGATION', gen_random_uuid(),
      current_date, 'p2c-unbalanced-batch-001', repeat('b', 64), '00000000-0000-4000-8000-000000000011'
    ) returning id into v_batch;
    insert into public.journal_lines(
      batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, transaction_date
    ) values
      (v_batch, '30000000-0000-4000-8000-000000000001', %L, v_bank, 100, 0, 'EGP', current_date),
      (v_batch, '30000000-0000-4000-8000-000000000001', %L, v_bank, 0, 99, 'EGP', current_date);
  end $inner$$outer$,
  :'p2c_project', :'p2c_project', :'p2c_project'), 'P0001', '%unbalanced%'),
  'unbalanced journal batch must be rejected');
select p2c_assert((select count(*)=0 from public.journal_batches where idempotency_key='p2c-unbalanced-batch-001'),
  'rejected unbalanced batch must leave no residue');

-- ---------------------------------------------------------------------------
-- Item 7: a mixed-currency journal batch is rejected by the canonical trigger.
-- ---------------------------------------------------------------------------
select p2c_assert(p2c_expect_raise_admin(format(
  $outer$do $inner$
  declare v_batch uuid; v_bank uuid;
  begin
    v_bank := (select id from public.semantic_accounts where role='BANK_CASH');
    insert into public.journal_batches(
      organization_id, project_id, source_type, source_id, transaction_date,
      idempotency_key, request_hash, posted_by
    ) values (
      '30000000-0000-4000-8000-000000000001', %L, 'COST_OBLIGATION', gen_random_uuid(),
      current_date, 'p2c-mixed-currency-batch-01', repeat('c', 64), '00000000-0000-4000-8000-000000000011'
    ) returning id into v_batch;
    insert into public.journal_lines(
      batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, transaction_date
    ) values
      (v_batch, '30000000-0000-4000-8000-000000000001', %L, v_bank, 100, 0, 'EGP', current_date),
      (v_batch, '30000000-0000-4000-8000-000000000001', %L, v_bank, 0, 100, 'USD', current_date);
  end $inner$$outer$,
  :'p2c_project', :'p2c_project', :'p2c_project'), 'P0001', '%mixes currencies%'),
  'mixed-currency journal batch must be rejected');
select p2c_assert((select count(*)=0 from public.journal_batches where idempotency_key='p2c-mixed-currency-batch-01'),
  'rejected mixed-currency batch must leave no residue');

-- ---------------------------------------------------------------------------
-- Item 12: foreign-project / foreign-organization references are rejected.
-- ---------------------------------------------------------------------------
select id as p2c_foreign_project from public.investment_projects where name='مشروع النخيل' \gset
select id as p2c_foreign_party from public.parties where legal_name='مورد منظمة باء' \gset

select p2c_assert(p2c_expect_raise(:'p2c_owner1', format(
  $$select public.create_cost_obligation('30000000-0000-4000-8000-000000000001',%L,%L,'التزام خارج النطاق',5000,'EGP',current_date,'EXPENSE','p2c-foreign-project-obl')$$,
  :'p2c_foreign_project', :'p2c_supplier'), 'P0001'),
  'obligation creation against a foreign project must be rejected');
select p2c_assert(p2c_expect_raise(:'p2c_owner1', format(
  $$select public.create_property_disposition('30000000-0000-4000-8000-000000000001',%L,%L,%L,'P2C-BAD-BUYER','محاولة بيع لطرف خارجي',100000,'EGP',current_date,current_date,'p2c-foreign-buyer-001')$$,
  :'p2c_project', :'p2c_asset', :'p2c_foreign_party'), 'P0001'),
  'disposition with a foreign-organization buyer must be rejected');
select p2c_assert(p2c_expect_raise(:'p2c_owner1', format(
  $$select public.pay_cost_obligation('30000000-0000-4000-8000-000000000001',%L,%L,1000,current_date,'p2c-foreign-cash-pay1')$$,
  :'p2c_obligation',
  (select id from public.project_cash_accounts where name='حساب مشروع ثانٍ' limit 1)), 'P0001'),
  'payment through a foreign-project cash account must be rejected');
select p2c_assert(p2c_expect_raise_admin(format(
  $outer$do $inner$
  declare v_batch uuid; v_bank uuid;
  begin
    v_bank := (select id from public.semantic_accounts where role='BANK_CASH');
    insert into public.journal_batches(
      organization_id, project_id, source_type, source_id, transaction_date,
      idempotency_key, request_hash, posted_by
    ) values (
      '30000000-0000-4000-8000-000000000001', %L, 'COST_OBLIGATION', gen_random_uuid(),
      current_date, 'p2c-foreign-party-batch-01', repeat('d', 64), '00000000-0000-4000-8000-000000000011'
    ) returning id into v_batch;
    insert into public.journal_lines(
      batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, party_id, transaction_date
    ) values
      (v_batch, '30000000-0000-4000-8000-000000000001', %L, v_bank, 100, 0, 'EGP', %L, current_date),
      (v_batch, '30000000-0000-4000-8000-000000000001', %L, v_bank, 0, 100, 'EGP', null, current_date);
  end $inner$$outer$,
  :'p2c_project', :'p2c_project', :'p2c_foreign_party', :'p2c_project'), 'P0001', '%party must belong to the line organization%'),
  'journal line with a foreign-organization party must be rejected');
select p2c_assert((select count(*)=0 from public.journal_batches where idempotency_key='p2c-foreign-party-batch-01'),
  'rejected foreign-party batch must leave no residue');
select p2c_assert(p2c_expect_raise(:'p2c_outsider', format(
  $$select public.s5_prepare_allocation('20000000-0000-4000-8000-000000000002',%L,%L,%L,'REALIZED_RESULT','p2c-foreign-snapshot-001')$$,
  :'p2c_project', :'p2c_snapshot', :'p2c_version'), 'P0001'),
  'another organization must not be able to allocate from this close snapshot');

-- ---------------------------------------------------------------------------
-- Items 1, 2, 5: payment idempotency, payload binding, and overpay rejection.
-- ---------------------------------------------------------------------------
select p2c_run(:'p2c_owner1', format(
  $$select public.pay_cost_obligation('30000000-0000-4000-8000-000000000001',%L,%L,40000,current_date,'p2c-pay-main-01')$$,
  :'p2c_obligation', :'p2c_cash'));
select id as p2c_payment1 from public.project_payments where idempotency_key='p2c-pay-main-01' \gset

select p2c_run(:'p2c_owner1', format(
  $$select public.pay_cost_obligation('30000000-0000-4000-8000-000000000001',%L,%L,40000,current_date,'p2c-pay-main-01')$$,
  :'p2c_obligation', :'p2c_cash'));
select p2c_assert((select count(*)=1 from public.project_payments where idempotency_key='p2c-pay-main-01'),
  'idempotent payment replay with identical payload must reuse the same fact');
select p2c_assert((select count(*)=1 from public.journal_batches
  where source_type='PAYMENT' and source_id=:'p2c_payment1'),
  'idempotent payment replay must not duplicate the journal effect');

select p2c_assert(p2c_expect_raise(:'p2c_owner1', format(
  $$select public.pay_cost_obligation('30000000-0000-4000-8000-000000000001',%L,%L,40001,current_date,'p2c-pay-main-01')$$,
  :'p2c_obligation', :'p2c_cash'), 'P0001', '%idempotency key payload mismatch%'),
  'same idempotency key with an altered payload must hard-fail');
select p2c_assert((select count(*)=1 from public.project_payments where obligation_id=:'p2c_obligation'),
  'payload-mismatch replay must leave exactly one payment fact');

select p2c_run(:'p2c_owner1', format(
  $$select public.pay_cost_obligation('30000000-0000-4000-8000-000000000001',%L,%L,60000,current_date,'p2c-pay-main-02')$$,
  :'p2c_obligation', :'p2c_cash'));
select id as p2c_payment2 from public.project_payments where idempotency_key='p2c-pay-main-02' \gset
select p2c_assert(p2c_expect_raise(:'p2c_owner1', format(
  $$select public.pay_cost_obligation('30000000-0000-4000-8000-000000000001',%L,%L,1,current_date,'p2c-pay-main-03')$$,
  :'p2c_obligation', :'p2c_cash'), 'P0001', '%payment exceeds remaining payable%'),
  'payment greater than the remaining obligation must be rejected');

-- ---------------------------------------------------------------------------
-- Item 6: collection cannot exceed the outstanding receivable.
-- ---------------------------------------------------------------------------
select p2c_assert(p2c_expect_raise(:'p2c_owner1', format(
  $$select public.collect_property_sale_receivable('30000000-0000-4000-8000-000000000001',%L,%L,1000002,current_date,'دليل تحصيل زائد','p2c-overcollect-001')$$,
  :'p2c_recognition', :'p2c_cash'), 'P0001', '%collection exceeds outstanding receivable%'),
  'collection greater than the remaining receivable must be rejected');
select p2c_run(:'p2c_owner1', format(
  $$select public.collect_property_sale_receivable('30000000-0000-4000-8000-000000000001',%L,%L,600000,current_date,'دليل تحصيل جزئي','p2c-collect-main-01')$$,
  :'p2c_recognition', :'p2c_cash'));
select id as p2c_collection1 from public.property_sale_collections where idempotency_key='p2c-collect-main-01' \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.collect_property_sale_receivable('30000000-0000-4000-8000-000000000001',%L,%L,600000,current_date,'دليل تحصيل جزئي','p2c-collect-main-01')$$,
  :'p2c_recognition', :'p2c_cash'));
select p2c_assert((select count(*)=1 from public.property_sale_collections where recognition_id=:'p2c_recognition'),
  'idempotent collection replay must reuse the same fact without duplicate posting');
select p2c_assert(p2c_expect_raise(:'p2c_owner1', format(
  $$select public.collect_property_sale_receivable('30000000-0000-4000-8000-000000000001',%L,%L,400002,current_date,'دليل تحصيل متبقٍ','p2c-collect-main-02')$$,
  :'p2c_recognition', :'p2c_cash'), 'P0001', '%collection exceeds outstanding receivable%'),
  'a second collection beyond the remaining receivable must be rejected');

-- ---------------------------------------------------------------------------
-- Item 11: duplicate reversal is rejected; identical replay is idempotent.
-- ---------------------------------------------------------------------------
select id as p2c_pay2_batch from public.journal_batches
where source_type='PAYMENT' and source_id=:'p2c_payment2' \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.reverse_journal_batch('30000000-0000-4000-8000-000000000001',%L,'إلغاء دفعة لأغراض الفحص','p2c-reverse-pay2-001')$$,
  :'p2c_pay2_batch'));
select id as p2c_reversal1 from public.journal_batches where source_type='REVERSAL' and source_id=:'p2c_pay2_batch' \gset
select p2c_assert(p2c_expect_raise(:'p2c_owner1', format(
  $$select public.reverse_journal_batch('30000000-0000-4000-8000-000000000001',%L,'محاولة إلغاء ثانية','p2c-reverse-pay2-002')$$,
  :'p2c_pay2_batch'), 'P0001', '%already reversed%'),
  'a second reversal with a different key must be rejected');
select p2c_run(:'p2c_owner1', format(
  $$select public.reverse_journal_batch('30000000-0000-4000-8000-000000000001',%L,'إلغاء دفعة لأغراض الفحص','p2c-reverse-pay2-001')$$,
  :'p2c_pay2_batch'));
select p2c_assert((select count(*)=1 from public.journal_batches where source_type='REVERSAL' and source_id=:'p2c_pay2_batch'),
  'identical reversal replay must be idempotent and never double-reverse');
select p2c_assert((
  select coalesce(sum(jl.debit_minor_units - jl.credit_minor_units),0)=0
  from public.journal_lines jl
  where jl.batch_id in (:'p2c_pay2_batch', :'p2c_reversal1')),
  'payment plus its exact reversal must net to zero on every account');

-- ---------------------------------------------------------------------------
-- Item 15: indivisible S5 remainder — exact integer conservation.
-- Source 600001 with weights 334/333/333 over denominator 1000:
-- floors 200400/199800/199800 (=600000) plus one awarded unit to the
-- largest remainder. No minor unit may be lost or created.
-- ---------------------------------------------------------------------------
select p2c_run(:'p2c_owner1', format(
  $$select public.s5_configure_allocation_rules('30000000-0000-4000-8000-000000000001',%L,%L,'FIXED_SHARES',array[%L::uuid,%L::uuid,%L::uuid],array[334,333,333]::bigint[],1000,'P2C-RULE-BASIS-EVIDENCE','p2c-rules-0001')$$,
  :'p2c_project', :'p2c_version', :'p2c_inv1', :'p2c_inv2', :'p2c_inv3'));
select p2c_run(:'p2c_owner2', format(
  $$select public.s5_prepare_allocation('30000000-0000-4000-8000-000000000001',%L,%L,%L,'REALIZED_RESULT','p2c-alloc-prepare-01')$$,
  :'p2c_project', :'p2c_snapshot', :'p2c_version'));
select id as p2c_alloc_run from public.s5_allocation_runs where idempotency_key='p2c-alloc-prepare-01' \gset

select p2c_assert((select count(*)=3 from public.s5_allocation_lines where run_id=:'p2c_alloc_run'),
  'allocation must produce one line per participant (3 participants)');
select p2c_assert((select sum(allocated_minor_units) from public.s5_allocation_lines where run_id=:'p2c_alloc_run')
  = (select source_amount_minor_units from public.s5_allocation_runs where id=:'p2c_alloc_run'),
  'SUM(allocation_lines.allocated_minor_units) must equal the authoritative source minor units');
select p2c_assert((select source_amount_minor_units from public.s5_allocation_runs where id=:'p2c_alloc_run') = 600001,
  'allocation source must be the exact realized result 600001');
select p2c_assert((
  select count(*)=3 from public.s5_allocation_lines l
  where l.run_id=:'p2c_alloc_run'
    and ((l.participant_party_id=:'p2c_inv1' and l.exact_floor_minor_units=200400 and l.rounding_award_minor_units=1 and l.allocated_minor_units=200401)
      or (l.participant_party_id=:'p2c_inv2' and l.exact_floor_minor_units=199800 and l.rounding_award_minor_units=0 and l.allocated_minor_units=199800)
      or (l.participant_party_id=:'p2c_inv3' and l.exact_floor_minor_units=199800 and l.rounding_award_minor_units=0 and l.allocated_minor_units=199800))),
  'largest-remainder allocation must conserve every minor unit exactly (200401+199800+199800=600001)');

-- Maker/checker: the preparer cannot self-approve the allocation.
select p2c_assert(p2c_expect_raise(:'p2c_owner2', format(
  $$select public.s5_approve_allocation('30000000-0000-4000-8000-000000000001',%L,current_date,'p2c-alloc-selfapprove')$$,
  :'p2c_alloc_run'), '23514'),
  'allocation self-approval by the preparer must violate maker/checker');

-- ---------------------------------------------------------------------------
-- Item 13: S7 opening import with a declared-total mismatch is rejected
-- before posting; a clean import reaches READY_FOR_APPROVAL and is left for
-- the approval race in 29_phase2c_concurrency.sh.
-- ---------------------------------------------------------------------------
select p2c_run(:'p2c_owner2', format(
  $$select public.s7_stage_opening_import('30000000-0000-4000-8000-000000000001',%L,'S7.OPENING.V1','opening-p2c-mismatch.csv',%L,
    array['OPENING_BANK_CASH','OPENING_SUPPLIER_PAYABLE']::text[],
    array[null,%L]::uuid[], array[%L,null]::uuid[],
    array['400000','0']::text[], array['0','400000']::text[],
    array['رصيد بنكي افتتاحي','رصيد مورد افتتاحي']::text[],
    '400001','400000','p2c-opening-mismatch-01')$$,
  :'p2c_project', :'p2c_sum_mismatch', :'p2c_supplier', :'p2c_cash'));
select id as p2c_import_mismatch from public.s7_opening_imports where idempotency_key='p2c-opening-mismatch-01' \gset
select p2c_run(:'p2c_owner2', format(
  $$select public.s7_validate_opening_import('30000000-0000-4000-8000-000000000001',%L,'p2c-validate-mismatch1')$$,
  :'p2c_import_mismatch'));
select p2c_assert((select status='REJECTED' and debit_variance_minor_units=-1 and credit_variance_minor_units=0
    and computed_debit_total_minor_units=400000
  from public.s7_opening_imports where id=:'p2c_import_mismatch'),
  'declared-total mismatch must reject the import before posting with an exact variance');
select p2c_assert((select count(*)=0 from public.journal_batches
  where source_type='S7_OPENING_IMPORT' and source_id=:'p2c_import_mismatch'),
  'rejected opening import must never post');

select p2c_run(:'p2c_owner2', format(
  $$select public.s7_stage_opening_import('30000000-0000-4000-8000-000000000001',%L,'S7.OPENING.V1','opening-p2c-clean.csv',%L,
    array['OPENING_BANK_CASH','OPENING_SUPPLIER_PAYABLE','OPENING_CONTRIBUTED_CAPITAL']::text[],
    array[null,%L,%L]::uuid[], array[%L,null,null]::uuid[],
    array['700000','0','0']::text[], array['0','200000','500000']::text[],
    array['رصيد بنكي افتتاحي','رصيد مورد افتتاحي','رأس مال افتتاحي']::text[],
    '700000','700000','p2c-opening-clean-0001')$$,
  :'p2c_project', :'p2c_sum_clean', :'p2c_supplier', :'p2c_inv1', :'p2c_cash'));
select id as p2c_import_clean from public.s7_opening_imports where idempotency_key='p2c-opening-clean-0001' \gset
select p2c_run(:'p2c_owner2', format(
  $$select public.s7_validate_opening_import('30000000-0000-4000-8000-000000000001',%L,'p2c-validate-clean-01')$$,
  :'p2c_import_clean'));
select p2c_assert((select status='VALIDATED' and control_totals_match
  from public.s7_opening_imports_read where import_id=:'p2c_import_clean'),
  'clean opening import must validate with zero variance');
select p2c_run(:'p2c_owner2', format(
  $$select public.s7_review_opening_import('30000000-0000-4000-8000-000000000001',%L,'مراجعة أرصدة افتتاحية مكتملة','p2c-review-clean-001')$$,
  :'p2c_import_clean'));
select p2c_assert((select status='READY_FOR_APPROVAL' from public.s7_opening_imports where id=:'p2c_import_clean'),
  'clean opening import must reach READY_FOR_APPROVAL for the race suite');
select p2c_assert(p2c_expect_raise(:'p2c_owner2', format(
  $$select public.s7_approve_opening_import('30000000-0000-4000-8000-000000000001',%L,current_date,'p2c-approve-self-001')$$,
  :'p2c_import_clean'), '23514'),
  'opening import self-approval by the stager must violate maker/checker');

-- A second fully valid opening import is staged for the same project. After
-- the first import posts in 29_phase2c_concurrency.sh, approving this second
-- one must be refused (no destructive overwrite of an opening position).
select p2c_run(:'p2c_owner2', format(
  $$select public.s7_stage_opening_import('30000000-0000-4000-8000-000000000001',%L,'S7.OPENING.V1','opening-p2c-second.csv',%L,
    array['OPENING_BANK_CASH','OPENING_CONTRIBUTED_CAPITAL']::text[],
    array[null,%L]::uuid[], array[%L,null]::uuid[],
    array['700000','0']::text[], array['0','700000']::text[],
    array['رصيد بنكي افتتاحي بديل','رأس مال افتتاحي بديل']::text[],
    '700000','700000','p2c-opening-second-01')$$,
  :'p2c_project', :'p2c_sum_second', :'p2c_inv1', :'p2c_cash'));
select id as p2c_import_second from public.s7_opening_imports where idempotency_key='p2c-opening-second-01' \gset
select p2c_run(:'p2c_owner2', format(
  $$select public.s7_validate_opening_import('30000000-0000-4000-8000-000000000001',%L,'p2c-validate-second-01')$$,
  :'p2c_import_second'));
select p2c_run(:'p2c_owner2', format(
  $$select public.s7_review_opening_import('30000000-0000-4000-8000-000000000001',%L,'مراجعة أرصدة افتتاحية ثانية','p2c-review-second-01')$$,
  :'p2c_import_second'));
select p2c_assert((select status='READY_FOR_APPROVAL' from public.s7_opening_imports where id=:'p2c_import_second'),
  'second opening import must reach READY_FOR_APPROVAL before the race suite');

-- ---------------------------------------------------------------------------
-- Concurrency fixtures consumed by 29_phase2c_concurrency.sh:
--  * p2c-obl-race-01: full-amount duplicate payment race.
--  * race project with a prepared close run: posting-versus-close race.
-- ---------------------------------------------------------------------------
select p2c_run(:'p2c_owner1', format(
  $$select public.create_cost_obligation('30000000-0000-4000-8000-000000000001',%L,%L,'التزام سباق الدفع',120000,'EGP',current_date,'EXPENSE','p2c-obl-race-01')$$,
  :'p2c_project', :'p2c_supplier'));
select id as p2c_race_obligation from public.cost_obligations where idempotency_key='p2c-obl-race-01' \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.authorize_cost_obligation('30000000-0000-4000-8000-000000000001',%L,'p2c-race-obl-auth-01')$$, :'p2c_race_obligation'));

select p2c_run(:'p2c_owner1',
  $$select public.create_investment_project('30000000-0000-4000-8000-000000000001','مشروع سباق الإغلاق',null,null)$$);
select id as p2c_race_project from public.investment_projects where name='مشروع سباق الإغلاق' \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.create_project_cash_account('30000000-0000-4000-8000-000000000001',%L,'حساب سباق الإغلاق','EGP')$$, :'p2c_race_project'));
select id as p2c_race_cash from public.project_cash_accounts where name='حساب سباق الإغلاق' \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.create_cost_obligation('30000000-0000-4000-8000-000000000001',%L,%L,'التزام سباق الإغلاق',90000,'EGP',current_date,'EXPENSE','p2c-obl-raceclose-01')$$,
  :'p2c_race_project', :'p2c_supplier'));
select id as p2c_raceclose_obligation from public.cost_obligations where idempotency_key='p2c-obl-raceclose-01' \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.authorize_cost_obligation('30000000-0000-4000-8000-000000000001',%L,'p2c-raceclose-auth-01')$$, :'p2c_raceclose_obligation'));
select p2c_run(:'p2c_owner1', format(
  $$select public.s6_create_accounting_period('30000000-0000-4000-8000-000000000001',%L,current_date-2,current_date)$$, :'p2c_race_project'));
select id as p2c_race_period from public.accounting_periods where project_id=:'p2c_race_project' and status='OPEN' \gset
select p2c_run(:'p2c_owner1', format(
  $$select public.s6_prepare_close_run('30000000-0000-4000-8000-000000000001',%L,%L,'race close prepare')$$,
  :'p2c_race_project', :'p2c_race_period'));
select id as p2c_race_close_run from public.close_runs where period_id=:'p2c_race_period' and status='PREPARED' \gset

select 'Phase 2C financial integrity SQL suite fixture and sequential cases PASS' as result;
