-- Phase 2C — focused financial-integrity attack suite (sequential cases).
-- Runtime proof of the highest-risk money invariants against the real
-- migration chain. Concurrency races live in 29_phase2c_concurrency.sh.
-- The suite builds one fresh tenant (organization 30000000-...0001) so every
-- assertion is deterministic and independent of earlier fixture state.

\set p2c_org_lit '30000000-0000-4000-8000-000000000001'
\set p2c_owner1 '00000000-0000-4000-8000-000000000011'
\set p2c_owner2 '00000000-0000-4000-8000-000000000012'
\set p2c_member '00000000-0000-4000-8000-000000000013'
\set p2c_outsider '00000000-0000-4000-8000-000000000002'
\set p2c_sum_mismatch 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
\set p2c_sum_clean 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
\set p2c_sum_second 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'

create or replace function p2c_assert(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if p_condition is distinct from true then
    raise exception 'Phase 2C assertion failed: %', p_message;
  end if;
end $$;

-- Constant accessor so embedded command calls never repeat the tenant literal.
create or replace function p2c_org() returns uuid
language sql immutable as $$ select '30000000-0000-4000-8000-000000000001'::uuid $$;

create or replace function p2c_run(p_user uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql;
  reset role;
end $$;

create or replace function p2c_owner1_run(p_sql text) returns void
language plpgsql as $$ begin perform public.p2c_run('00000000-0000-4000-8000-000000000011', p_sql); end $$;
create or replace function p2c_owner2_run(p_sql text) returns void
language plpgsql as $$ begin perform public.p2c_run('00000000-0000-4000-8000-000000000012', p_sql); end $$;

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

create or replace function p2c_owner1_raises(p_sql text, p_sqlstate text, p_message_like text default null)
returns boolean language plpgsql as $$
begin return public.p2c_expect_raise('00000000-0000-4000-8000-000000000011', p_sql, p_sqlstate, p_message_like); end $$;
create or replace function p2c_owner2_raises(p_sql text, p_sqlstate text, p_message_like text default null)
returns boolean language plpgsql as $$
begin return public.p2c_expect_raise('00000000-0000-4000-8000-000000000012', p_sql, p_sqlstate, p_message_like); end $$;
create or replace function p2c_outsider_raises(p_sql text, p_sqlstate text, p_message_like text default null)
returns boolean language plpgsql as $$
begin return public.p2c_expect_raise('00000000-0000-4000-8000-000000000002', p_sql, p_sqlstate, p_message_like); end $$;

create or replace function p2c_expect_raise_admin(p_sql text, p_sqlstate text, p_message_like text default null)
returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return sqlstate = p_sqlstate
    and (p_message_like is null or sqlerrm like p_message_like);
end $$;

-- Compact command vocabulary: each wrapper binds the tenant so call sites do
-- not repeat long identical token sequences.
create or replace function p2c_pay(p_obligation uuid, p_cash uuid, p_amount bigint, p_date date, p_key text)
returns uuid language plpgsql as $$
declare v_approver uuid:='00000000-0000-4000-8000-000000000011'; v_proposal uuid;
begin
  perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000013',true);
  v_proposal:=public.prepare_cost_payment(public.p2c_org(),p_obligation,p_cash,p_amount,p_date,'proposal-'||p_key);
  perform set_config('request.jwt.claim.sub',v_approver::text,true);
  return public.approve_cost_payment(public.p2c_org(),v_proposal,p_key);
end $$;
create or replace function p2c_authorize_obl(p_obligation uuid, p_key text) returns uuid
language plpgsql as $$ begin return public.authorize_cost_obligation(public.p2c_org(), p_obligation, p_key); end $$;
create or replace function p2c_create_obl(p_project uuid, p_party uuid, p_desc text, p_amount bigint, p_date date, p_treatment text, p_key text)
returns uuid language plpgsql as $$
begin return public.create_cost_obligation(public.p2c_org(), p_project, p_party, p_desc, p_amount, 'EGP', p_date, p_treatment, p_key); end $$;
create or replace function p2c_collect(p_recognition uuid, p_cash uuid, p_amount bigint, p_date date, p_evidence text, p_key text)
returns uuid language plpgsql as $$
begin return public.collect_property_sale_receivable(public.p2c_org(), p_recognition, p_cash, p_amount, p_date, p_evidence, p_key); end $$;
create or replace function p2c_reverse(p_batch uuid, p_reason text, p_key text) returns uuid
language plpgsql as $$ begin return public.reverse_journal_batch(public.p2c_org(), p_batch, p_reason, p_key); end $$;
create or replace function p2c_transition(p_asset uuid, p_from text, p_to text, p_reason text, p_evidence text, p_key text)
returns uuid language plpgsql as $$
begin return public.transition_property_asset(public.p2c_org(), p_asset, p_from, p_to, p_reason, p_evidence, p_key); end $$;
create or replace function p2c_control(p_asset uuid, p_record_type text, p_name text, p_result text, p_date date, p_evidence text, p_notes text, p_key text)
returns uuid language plpgsql as $$
begin
  return public.record_property_control(public.p2c_org(), p_asset, null, p_record_type, p_name, 'PASSED',
    p_date, null, p_result, '00000000-0000-4000-8000-000000000011', p_evidence, p_notes, p_key);
end $$;
create or replace function p2c_stage(p_project uuid, p_file text, p_checksum text, p_codes text[], p_parties uuid[], p_cash uuid[],
  p_debits text[], p_credits text[], p_descs text[], p_declared_debit text, p_declared_credit text, p_key text)
returns uuid language plpgsql as $$
begin
  return public.s7_stage_opening_import(public.p2c_org(), p_project, 'S7.OPENING.V1', p_file, p_checksum,
    p_codes, p_parties, p_cash, p_debits, p_credits, p_descs, p_declared_debit, p_declared_credit, p_key);
end $$;
create or replace function p2c_validate_import(p_import uuid, p_key text) returns text
language plpgsql as $$ begin return public.s7_validate_opening_import(public.p2c_org(), p_import, p_key); end $$;
create or replace function p2c_review_import(p_import uuid, p_notes text, p_key text) returns uuid
language plpgsql as $$ begin return public.s7_review_opening_import(public.p2c_org(), p_import, p_notes, p_key); end $$;
create or replace function p2c_approve_import(p_import uuid, p_date date, p_key text) returns uuid
language plpgsql as $$ begin return public.s7_approve_opening_import(public.p2c_org(), p_import, p_date, p_key); end $$;

-- Test-only batch insert used by the direct-writer journal attacks.
create or replace function p2c_make_batch(p_key text, p_hash_seed text, p_date date)
returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    public.p2c_org(),
    (select id from public.investment_projects where organization_id = public.p2c_org() and name = 'مشروع الفحص المالي'),
    'COST_OBLIGATION', gen_random_uuid(), p_date,
    p_key, repeat(p_hash_seed, 64), '00000000-0000-4000-8000-000000000011'
  ) returning id into v_id;
  return v_id;
end $$;

-- Explicit balanced test funding; this is fixture setup, not a product command
-- or an opening-balance shortcut exposed to application roles.
create or replace function p2c_fund_cash(
  p_project uuid, p_cash uuid, p_amount bigint, p_date date, p_key text
) returns void language plpgsql as $$
declare v_batch uuid; v_bank uuid; v_capital uuid;
begin
  select id into v_bank from public.semantic_accounts where role='BANK_CASH';
  select id into v_capital from public.semantic_accounts where role='CONTRIBUTED_CAPITAL';
  insert into public.journal_batches(
    organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by
  ) values (
    public.p2c_org(),p_project,'CONTRIBUTION_CASH_ATTRIBUTION',gen_random_uuid(),p_date,
    p_key,repeat('f',64),'00000000-0000-4000-8000-000000000011'
  ) returning id into v_batch;
  insert into public.journal_lines(
    batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,
    currency,cash_account_id,transaction_date
  ) values
    (v_batch,public.p2c_org(),p_project,v_bank,p_amount,0,'EGP',p_cash,p_date),
    (v_batch,public.p2c_org(),p_project,v_capital,0,p_amount,'EGP',null,p_date);
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
  (:'p2c_org_lit', 'منظمة الفحص المالي 2C')
on conflict (id) do nothing;
insert into public.memberships(organization_id,user_id,role,status) values
  (:'p2c_org_lit', :'p2c_owner1', 'OWNER','ACTIVE'),
  (:'p2c_org_lit', :'p2c_owner2', 'OWNER','ACTIVE'),
  (:'p2c_org_lit', :'p2c_member', 'MEMBER','ACTIVE')
on conflict (organization_id,user_id) do update set role=excluded.role, status=excluded.status;

-- ---------------------------------------------------------------------------
-- Project, parties, cash account, governing agreement with three investors.
-- ---------------------------------------------------------------------------
select p2c_owner1_run($$select public.create_investment_project(public.p2c_org(),'مشروع الفحص المالي',null,null)$$);
select id as p2c_project from public.investment_projects where name='مشروع الفحص المالي' \gset

select p2c_owner1_run($$select public.create_party(public.p2c_org(),'مورد الفحص','ORGANIZATION')$$);
select p2c_owner1_run($$select public.create_party(public.p2c_org(),'مشتري الفحص','ORGANIZATION')$$);
select p2c_owner1_run($$select public.create_party(public.p2c_org(),'مستثمر فحص أول','PERSON')$$);
select p2c_owner1_run($$select public.create_party(public.p2c_org(),'مستثمر فحص ثانٍ','PERSON')$$);
select p2c_owner1_run($$select public.create_party(public.p2c_org(),'مستثمر فحص ثالث','PERSON')$$);
select id as p2c_supplier from public.parties where legal_name='مورد الفحص' and organization_id=:'p2c_org_lit' \gset
select id as p2c_buyer from public.parties where legal_name='مشتري الفحص' and organization_id=:'p2c_org_lit' \gset
select id as p2c_inv1 from public.parties where legal_name='مستثمر فحص أول' and organization_id=:'p2c_org_lit' \gset
select id as p2c_inv2 from public.parties where legal_name='مستثمر فحص ثانٍ' and organization_id=:'p2c_org_lit' \gset
select id as p2c_inv3 from public.parties where legal_name='مستثمر فحص ثالث' and organization_id=:'p2c_org_lit' \gset

select p2c_owner1_run(format($$select public.create_project_cash_account(public.p2c_org(),%L,'حساب فحص 2C','EGP')$$, :'p2c_project'));
select id as p2c_cash from public.project_cash_accounts where name='حساب فحص 2C' \gset
select p2c_fund_cash(:'p2c_project', :'p2c_cash', 200000, current_date, 'p2c-fixture-cash-main');

select p2c_owner1_run(format($$select public.add_project_participant(public.p2c_org(),%L,%L)$$, :'p2c_project', :'p2c_inv1'));
select p2c_owner1_run(format($$select public.add_project_participant(public.p2c_org(),%L,%L)$$, :'p2c_project', :'p2c_inv2'));
select p2c_owner1_run(format($$select public.add_project_participant(public.p2c_org(),%L,%L)$$, :'p2c_project', :'p2c_inv3'));
select id as p2c_part1 from public.project_participants where party_id=:'p2c_inv1' \gset
select id as p2c_part2 from public.project_participants where party_id=:'p2c_inv2' \gset
select id as p2c_part3 from public.project_participants where party_id=:'p2c_inv3' \gset

select p2c_owner1_run(format(
  $$select public.create_agreement_draft(public.p2c_org(),%L,date '2026-07-01',array[%L::uuid,%L::uuid,%L::uuid],array[334000,333000,333000]::bigint[],'p2c-agreement-0001')$$,
  :'p2c_project', :'p2c_part1', :'p2c_part2', :'p2c_part3'));
select id as p2c_version from public.agreement_versions where idempotency_key='p2c-agreement-0001' \gset
select p2c_owner1_run(format($$select public.activate_agreement_version(public.p2c_org(),%L)$$, :'p2c_version'));

-- ---------------------------------------------------------------------------
-- S3 lifecycle to HELD with authoritative history and control evidence.
-- ---------------------------------------------------------------------------
select p2c_owner1_run(format($$select public.create_real_estate_profile(public.p2c_org(),%L,'DEVELOP_SELL','القاهرة، مصر','p2c-profile-001')$$, :'p2c_project'));
select p2c_owner1_run(format($$select public.create_property_asset(public.p2c_org(),%L,'أصل الفحص المالي','P2C-PROP-001','p2c-asset-0001')$$, :'p2c_project'));
select id as p2c_asset from public.property_assets where idempotency_key='p2c-asset-0001' \gset
select p2c_owner1_run(format(
  $$select public.record_property_acquisition(public.p2c_org(),%L,%L,'P2C-ACQ-001',500000,25000,'EGP',current_date-10,null,'عقد شراء موقع P2C-ACQ-001','p2c-acquisition-001')$$,
  :'p2c_asset', :'p2c_supplier'));
select p2c_owner1_run(format($$select public.p2c_transition(%L,'CANDIDATE','DUE_DILIGENCE','بدء الفحص النافي للجهالة','مذكرة قرار P2C-DD','p2c-state-dd-0001')$$, :'p2c_asset'));
select p2c_owner1_run(format(
  $$select public.p2c_control(%L,'ACQUISITION_CHECK','فحص قانوني للعقد','لا توجد موانع مسجلة',current_date-6,'P2C-DD-CHK-001','تمت مراجعة سلسلة العقود','p2c-control-dd-001')$$,
  :'p2c_asset'));
select p2c_owner1_run(format($$select public.p2c_transition(%L,'DUE_DILIGENCE','ACQUIRING','اجتياز الفحص وتسجيل العقد','تقرير قانوني P2C-44','p2c-state-acq-001')$$, :'p2c_asset'));
select p2c_owner1_run(format(
  $$select public.p2c_control(%L,'TITLE','سند ملكية مسجل','السند يغطي الأصل',current_date-5,'P2C-TITLE-ACQ',null,'p2c-control-title-acq')$$,
  :'p2c_asset'));
select p2c_owner1_run(format(
  $$select public.p2c_control(%L,'POSSESSION','حيازة فعلية عند الشراء','الحيازة مكتملة',current_date-5,'P2C-POS-ACQ',null,'p2c-control-pos-acq')$$,
  :'p2c_asset'));
select p2c_owner1_run(format($$select public.p2c_transition(%L,'ACQUIRING','HELD','إثبات السيطرة','سند مسجل P2C-TITLE-ACQ','p2c-state-held-001')$$, :'p2c_asset'));

-- ---------------------------------------------------------------------------
-- S2 obligations (all fixture postings dated current_date-5 so they fall
-- inside the first close period).
-- ---------------------------------------------------------------------------
select p2c_owner1_run(format(
  $$select public.p2c_create_obl(%L,%L,'أعمال تطوير الفحص',100000,current_date-5,'EXPENSE','p2c-obl-main-0001')$$,
  :'p2c_project', :'p2c_supplier'));
select id as p2c_obligation from public.cost_obligations where idempotency_key='p2c-obl-main-0001' \gset
select p2c_owner1_run(format($$select public.p2c_authorize_obl(%L,'p2c-obl-auth-001')$$, :'p2c_obligation'));

select p2c_owner1_run(format(
  $$select public.p2c_create_obl(%L,%L,'تطوير رأسمالي للفحص',400000,current_date-5,'CAPITALIZABLE_WIP','p2c-obl-wip-0001')$$,
  :'p2c_project', :'p2c_supplier'));
select id as p2c_wip_obligation from public.cost_obligations where idempotency_key='p2c-obl-wip-0001' \gset
select p2c_owner1_run(format($$select public.p2c_authorize_obl(%L,'p2c-wip-auth-001')$$, :'p2c_wip_obligation'));
select p2c_owner1_run(format(
  $$select public.classify_property_cost(public.p2c_org(),%L,%L,null,null,'CONSTRUCTION','قرار رسملة WIP للفحص','p2c-cost-class-001')$$,
  :'p2c_wip_obligation', :'p2c_asset'));

-- ---------------------------------------------------------------------------
-- S4 sale chain with proceeds 1000001 (deliberately indivisible by 3 later).
-- Realized result will be 1000001 - 400000 carrying cost = 600001.
-- ---------------------------------------------------------------------------
select p2c_owner1_run(format(
  $$select public.create_property_disposition(public.p2c_org(),%L,%L,%L,'P2C-DISP-001','عقد بيع موقع P2C-DISP-001',1000001,'EGP',current_date-8,current_date-5,'p2c-disposition-001')$$,
  :'p2c_project', :'p2c_asset', :'p2c_buyer'));
select id as p2c_disposition from public.property_dispositions where idempotency_key='p2c-disposition-001' \gset
select p2c_owner1_run(format($$select public.approve_property_disposition(public.p2c_org(),%L,'p2c-disp-approve-01')$$, :'p2c_disposition'));
select p2c_owner1_run(format($$select public.p2c_transition(%L,'HELD','EXITING','بدء تخارج الفحص','P2C-DISP-001','p2c-state-exiting-01')$$, :'p2c_asset'));
select p2c_owner1_run(format(
  $$select public.p2c_control(%L,'TITLE','سند ملكية عند التخارج','السند يغطي الأصل كاملًا',current_date-5,'P2C-TITLE-EXIT',null,'p2c-control-title-exit')$$,
  :'p2c_asset'));
select p2c_owner1_run(format(
  $$select public.p2c_control(%L,'POSSESSION','حيازة عند التخارج','الحيازة مكتملة',current_date-5,'P2C-POS-EXIT',null,'p2c-control-pos-exit')$$,
  :'p2c_asset'));
select p2c_owner1_run(format(
  $$select public.confirm_property_control_transfer(public.p2c_org(),%L,current_date-5,'محضر تسليم الفحص P2C','p2c-transfer-001')$$,
  :'p2c_disposition'));
select p2c_owner1_run(format($$select public.recognize_property_sale(public.p2c_org(),%L,current_date-5,'p2c-recognize-001')$$, :'p2c_disposition'));
select id as p2c_recognition from public.property_sale_recognitions where disposition_id=:'p2c_disposition' \gset

-- ---------------------------------------------------------------------------
-- S6: close the first period, capture the snapshot, then reopen so later
-- postings have an OPEN authoritative period.
-- ---------------------------------------------------------------------------
select p2c_owner1_run(format($$select public.s6_create_accounting_period(public.p2c_org(),%L,current_date-15,current_date-1)$$, :'p2c_project'));
select id as p2c_period1 from public.accounting_periods where project_id=:'p2c_project' and status='OPEN' \gset
select p2c_owner1_run(format($$select public.s6_prepare_close_run(public.p2c_org(),%L,%L,'p2c close v1')$$, :'p2c_project', :'p2c_period1'));
select id as p2c_close_run1 from public.close_runs where period_id=:'p2c_period1' and version=1 \gset
select p2c_owner1_run(format($$select public.s6_approve_close_run(public.p2c_org(),%L,'p2c-close-approve-01')$$, :'p2c_close_run1'));
select p2c_assert((select status='CLOSED' from public.accounting_periods where id=:'p2c_period1'),
  'period v1 must be CLOSED after approval');
select id as p2c_snapshot from public.close_run_snapshots where close_run_id=:'p2c_close_run1' \gset
select p2c_assert(
  (select public.s5_realized_result_as_of_snapshot(p2c_org(), :'p2c_project', :'p2c_snapshot')) = 600001,
  'closed snapshot realized result must be exactly 600001 minor units');

select p2c_owner1_run(format(
  $$select public.s6_reopen_period(public.p2c_org(),%L,%L,'reopen for post-close activity','p2c-reopen-evidence-01')$$,
  :'p2c_project', :'p2c_period1'));
select id as p2c_period2 from public.accounting_periods where project_id=:'p2c_project' and status='OPEN' \gset
select p2c_assert((select supersedes_period_id=:'p2c_period1' from public.accounting_periods where id=:'p2c_period2'),
  'reopened period must supersede the closed one');

-- ---------------------------------------------------------------------------
-- Item 9: posting into the CLOSED period is rejected at the journal boundary.
-- ---------------------------------------------------------------------------
select p2c_assert(p2c_expect_raise_admin(
  $$select public.p2c_make_batch('p2c-closed-period-posting-01','a',current_date-5)$$,
  'P0001', '%no open accounting period%'),
  'posting dated inside the CLOSED period must be rejected');
select p2c_assert((select count(*)=0 from public.journal_batches where idempotency_key='p2c-closed-period-posting-01'),
  'rejected closed-period posting must leave no batch residue');

-- ---------------------------------------------------------------------------
-- Item 8: an unbalanced journal batch is rejected by the canonical trigger.
-- ---------------------------------------------------------------------------
select p2c_assert(p2c_expect_raise_admin(
  $outer$do $inner$
  declare v_batch uuid; v_bank uuid; v_project uuid;
  begin
    v_bank := (select id from public.semantic_accounts where role='BANK_CASH');
    v_project := (select id from public.investment_projects where organization_id=public.p2c_org() and name='مشروع الفحص المالي');
    v_batch := public.p2c_make_batch('p2c-unbalanced-batch-001','b',current_date);
    insert into public.journal_lines(
      batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, transaction_date
    ) values
      (v_batch, public.p2c_org(), v_project, v_bank, 100, 0, 'EGP', current_date),
      (v_batch, public.p2c_org(), v_project, v_bank, 0, 99, 'EGP', current_date);
  end $inner$$outer$,
  'P0001', '%unbalanced%'),
  'unbalanced journal batch must be rejected');
select p2c_assert((select count(*)=0 from public.journal_batches where idempotency_key='p2c-unbalanced-batch-001'),
  'rejected unbalanced batch must leave no residue');

-- ---------------------------------------------------------------------------
-- Item 7: a mixed-currency journal batch is rejected by the canonical trigger.
-- ---------------------------------------------------------------------------
select p2c_assert(p2c_expect_raise_admin(
  $outer$do $inner$
  declare v_batch uuid; v_bank uuid; v_project uuid;
  begin
    v_bank := (select id from public.semantic_accounts where role='BANK_CASH');
    v_project := (select id from public.investment_projects where organization_id=public.p2c_org() and name='مشروع الفحص المالي');
    v_batch := public.p2c_make_batch('p2c-mixed-currency-batch-01','c',current_date);
    insert into public.journal_lines(
      batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, transaction_date
    ) values
      (v_batch, public.p2c_org(), v_project, v_bank, 100, 0, 'EGP', current_date),
      (v_batch, public.p2c_org(), v_project, v_bank, 0, 100, 'USD', current_date);
  end $inner$$outer$,
  'P0001', '%mixes currencies%'),
  'mixed-currency journal batch must be rejected');
select p2c_assert((select count(*)=0 from public.journal_batches where idempotency_key='p2c-mixed-currency-batch-01'),
  'rejected mixed-currency batch must leave no residue');

-- ---------------------------------------------------------------------------
-- Item 12: foreign-project / foreign-organization references are rejected.
-- ---------------------------------------------------------------------------
select id as p2c_foreign_project from public.investment_projects where name='مشروع النخيل' \gset
select id as p2c_foreign_party from public.parties where legal_name='مورد منظمة باء' \gset

select p2c_assert(p2c_owner1_raises(format(
  $$select public.p2c_create_obl(%L,%L,'التزام خارج النطاق',5000,current_date,'EXPENSE','p2c-foreign-project-obl')$$,
  :'p2c_foreign_project', :'p2c_supplier'), 'P0001'),
  'obligation creation against a foreign project must be rejected');
select p2c_assert(p2c_owner1_raises(format(
  $$select public.create_property_disposition(public.p2c_org(),%L,%L,%L,'P2C-BAD-BUYER','محاولة بيع لطرف خارجي',100000,'EGP',current_date,current_date,'p2c-foreign-buyer-001')$$,
  :'p2c_project', :'p2c_asset', :'p2c_foreign_party'), 'P0001'),
  'disposition with a foreign-organization buyer must be rejected');
select p2c_assert(p2c_owner1_raises(format(
  $$select public.p2c_pay(%L,%L,1000,current_date,'p2c-foreign-cash-pay1')$$,
  :'p2c_obligation',
  (select id from public.project_cash_accounts where name='حساب مشروع ثانٍ' limit 1)), 'P0001'),
  'payment through a foreign-project cash account must be rejected');
select p2c_assert(p2c_expect_raise_admin(
  $outer$do $inner$
  declare v_batch uuid; v_bank uuid; v_project uuid;
  begin
    v_bank := (select id from public.semantic_accounts where role='BANK_CASH');
    v_project := (select id from public.investment_projects where organization_id=public.p2c_org() and name='مشروع الفحص المالي');
    v_batch := public.p2c_make_batch('p2c-foreign-party-batch-01','d',current_date);
    insert into public.journal_lines(
      batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, party_id, transaction_date
    ) values
      (v_batch, public.p2c_org(), v_project, v_bank, 100, 0, 'EGP',
       (select id from public.parties where legal_name='مورد منظمة باء'), current_date),
      (v_batch, public.p2c_org(), v_project, v_bank, 0, 100, 'EGP', null, current_date);
  end $inner$$outer$,
  'P0001', '%party must belong to the line organization%'),
  'journal line with a foreign-organization party must be rejected');
select p2c_assert((select count(*)=0 from public.journal_batches where idempotency_key='p2c-foreign-party-batch-01'),
  'rejected foreign-party batch must leave no residue');
select p2c_assert(p2c_outsider_raises(format(
  $$select public.s5_prepare_allocation('20000000-0000-4000-8000-000000000002',%L,%L,%L,'REALIZED_RESULT','p2c-foreign-snapshot-001')$$,
  :'p2c_project', :'p2c_snapshot', :'p2c_version'), 'P0001'),
  'another organization must not be able to allocate from this close snapshot');

-- ---------------------------------------------------------------------------
-- Items 1, 2, 5: payment idempotency, payload binding, and overpay rejection.
-- ---------------------------------------------------------------------------
select p2c_owner1_run(format(
  $$select public.p2c_pay(%L,%L,40000,current_date,'p2c-pay-main-01')$$,
  :'p2c_obligation', :'p2c_cash'));
select id as p2c_payment1 from public.project_payments where idempotency_key='p2c-pay-main-01' \gset

select p2c_owner1_run(format(
  $$select public.p2c_pay(%L,%L,40000,current_date,'p2c-pay-main-01')$$,
  :'p2c_obligation', :'p2c_cash'));
select p2c_assert((select count(*)=1 from public.project_payments where idempotency_key='p2c-pay-main-01'),
  'idempotent payment replay with identical payload must reuse the same fact');
select p2c_assert((select count(*)=1 from public.journal_batches
  where source_type='PAYMENT' and source_id=:'p2c_payment1'),
  'idempotent payment replay must not duplicate the journal effect');

select p2c_assert(p2c_owner1_raises(format(
  $$select public.p2c_pay(%L,%L,40001,current_date,'p2c-pay-main-01')$$,
  :'p2c_obligation', :'p2c_cash'), 'P0001', '%idempotency key payload mismatch%'),
  'same idempotency key with an altered payload must hard-fail');
select p2c_assert((select count(*)=1 from public.project_payments where obligation_id=:'p2c_obligation'),
  'payload-mismatch replay must leave exactly one payment fact');

select p2c_owner1_run(format(
  $$select public.p2c_pay(%L,%L,60000,current_date,'p2c-pay-main-02')$$,
  :'p2c_obligation', :'p2c_cash'));
select id as p2c_payment2 from public.project_payments where idempotency_key='p2c-pay-main-02' \gset
select p2c_assert(p2c_owner1_raises(format(
  $$select public.p2c_pay(%L,%L,1,current_date,'p2c-pay-main-03')$$,
  :'p2c_obligation', :'p2c_cash'), 'P0001', '%payment exceeds remaining payable%'),
  'payment greater than the remaining obligation must be rejected');

-- ---------------------------------------------------------------------------
-- Item 6: collection cannot exceed the outstanding receivable.
-- ---------------------------------------------------------------------------
select p2c_assert(p2c_owner1_raises(format(
  $$select public.p2c_collect(%L,%L,1000002,current_date,'دليل تحصيل زائد','p2c-overcollect-001')$$,
  :'p2c_recognition', :'p2c_cash'), 'P0001', '%collection exceeds outstanding receivable%'),
  'collection greater than the remaining receivable must be rejected');
select p2c_owner1_run(format(
  $$select public.p2c_collect(%L,%L,600000,current_date,'دليل تحصيل جزئي','p2c-collect-main-01')$$,
  :'p2c_recognition', :'p2c_cash'));
select id as p2c_collection1 from public.property_sale_collections where idempotency_key='p2c-collect-main-01' \gset
select p2c_owner1_run(format(
  $$select public.p2c_collect(%L,%L,600000,current_date,'دليل تحصيل جزئي','p2c-collect-main-01')$$,
  :'p2c_recognition', :'p2c_cash'));
select p2c_assert((select count(*)=1 from public.property_sale_collections where recognition_id=:'p2c_recognition'),
  'idempotent collection replay must reuse the same fact without duplicate posting');
select p2c_assert(p2c_owner1_raises(format(
  $$select public.p2c_collect(%L,%L,400002,current_date,'دليل تحصيل متبقٍ','p2c-collect-main-02')$$,
  :'p2c_recognition', :'p2c_cash'), 'P0001', '%collection exceeds outstanding receivable%'),
  'a second collection beyond the remaining receivable must be rejected');

-- ---------------------------------------------------------------------------
-- Item 11: duplicate reversal is rejected; identical replay is idempotent.
-- ---------------------------------------------------------------------------
select id as p2c_pay2_batch from public.journal_batches
where source_type='PAYMENT' and source_id=:'p2c_payment2' \gset
select p2c_owner1_run(format(
  $$select public.p2c_reverse(%L,'إلغاء دفعة لأغراض الفحص','p2c-reverse-pay2-001')$$,
  :'p2c_pay2_batch'));
select id as p2c_reversal1 from public.journal_batches where source_type='REVERSAL' and source_id=:'p2c_pay2_batch' \gset
select p2c_assert(p2c_owner1_raises(format(
  $$select public.p2c_reverse(%L,'محاولة إلغاء ثانية','p2c-reverse-pay2-002')$$,
  :'p2c_pay2_batch'), 'P0001', '%already reversed%'),
  'a second reversal with a different key must be rejected');
select p2c_owner1_run(format(
  $$select public.p2c_reverse(%L,'إلغاء دفعة لأغراض الفحص','p2c-reverse-pay2-001')$$,
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
select p2c_owner1_run(format(
  $$select public.s5_configure_allocation_rules(public.p2c_org(),%L,%L,'FIXED_SHARES',array[%L::uuid,%L::uuid,%L::uuid],array[334,333,333]::bigint[],1000,'P2C-RULE-BASIS-EVIDENCE','p2c-rules-0001')$$,
  :'p2c_project', :'p2c_version', :'p2c_inv1', :'p2c_inv2', :'p2c_inv3'));
select p2c_owner2_run(format(
  $$select public.s5_prepare_allocation(public.p2c_org(),%L,%L,%L,'REALIZED_RESULT','p2c-alloc-prepare-01')$$,
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
select p2c_assert(p2c_owner2_raises(format(
  $$select public.s5_approve_allocation(public.p2c_org(),%L,current_date,'p2c-alloc-selfapprove')$$,
  :'p2c_alloc_run'), '23514'),
  'allocation self-approval by the preparer must violate maker/checker');

-- ---------------------------------------------------------------------------
-- Item 13: S7 opening import with a declared-total mismatch is rejected
-- before posting; a clean import reaches READY_FOR_APPROVAL and is left for
-- the approval race in 29_phase2c_concurrency.sh.
-- ---------------------------------------------------------------------------
select p2c_owner2_run(format(
  $$select public.p2c_stage(%L,'opening-p2c-mismatch.csv',%L,
    array['OPENING_BANK_CASH','OPENING_SUPPLIER_PAYABLE']::text[],
    array[null,%L]::uuid[], array[%L,null]::uuid[],
    array['400000','0']::text[], array['0','400000']::text[],
    array['رصيد بنكي افتتاحي','رصيد مورد افتتاحي']::text[],
    '400001','400000','p2c-opening-mismatch-01')$$,
  :'p2c_project', :'p2c_sum_mismatch', :'p2c_supplier', :'p2c_cash'));
select id as p2c_import_mismatch from public.s7_opening_imports where idempotency_key='p2c-opening-mismatch-01' \gset
select p2c_owner2_run(format($$select public.p2c_validate_import(%L,'p2c-validate-mismatch1')$$, :'p2c_import_mismatch'));
select p2c_assert((select status='REJECTED' and debit_variance_minor_units=-1 and credit_variance_minor_units=0
    and computed_debit_total_minor_units=400000
  from public.s7_opening_imports where id=:'p2c_import_mismatch'),
  'declared-total mismatch must reject the import before posting with an exact variance');
select p2c_assert((select count(*)=0 from public.journal_batches
  where source_type='S7_OPENING_IMPORT' and source_id=:'p2c_import_mismatch'),
  'rejected opening import must never post');

select p2c_owner2_run(format(
  $$select public.p2c_stage(%L,'opening-p2c-clean.csv',%L,
    array['OPENING_BANK_CASH','OPENING_SUPPLIER_PAYABLE','OPENING_CONTRIBUTED_CAPITAL']::text[],
    array[null,%L,%L]::uuid[], array[%L,null,null]::uuid[],
    array['700000','0','0']::text[], array['0','200000','500000']::text[],
    array['رصيد بنكي افتتاحي','رصيد مورد افتتاحي','رأس مال افتتاحي']::text[],
    '700000','700000','p2c-opening-clean-0001')$$,
  :'p2c_project', :'p2c_sum_clean', :'p2c_supplier', :'p2c_inv1', :'p2c_cash'));
select id as p2c_import_clean from public.s7_opening_imports where idempotency_key='p2c-opening-clean-0001' \gset
select p2c_owner2_run(format($$select public.p2c_validate_import(%L,'p2c-validate-clean-01')$$, :'p2c_import_clean'));
select p2c_assert((select status='VALIDATED' and control_totals_match
  from public.s7_opening_imports_read where import_id=:'p2c_import_clean'),
  'clean opening import must validate with zero variance');
select p2c_owner2_run(format(
  $$select public.p2c_review_import(%L,'مراجعة أرصدة افتتاحية مكتملة','p2c-review-clean-001')$$,
  :'p2c_import_clean'));
select p2c_assert((select status='READY_FOR_APPROVAL' from public.s7_opening_imports where id=:'p2c_import_clean'),
  'clean opening import must reach READY_FOR_APPROVAL for the race suite');
select p2c_assert(p2c_owner2_raises(format(
  $$select public.p2c_approve_import(%L,current_date,'p2c-approve-self-001')$$,
  :'p2c_import_clean'), '23514'),
  'opening import self-approval by the stager must violate maker/checker');

-- A second fully valid opening import is staged for the same project. After
-- the first import posts in 29_phase2c_concurrency.sh, approving this second
-- one must be refused (no destructive overwrite of an opening position).
select p2c_owner2_run(format(
  $$select public.p2c_stage(%L,'opening-p2c-second.csv',%L,
    array['OPENING_BANK_CASH','OPENING_CONTRIBUTED_CAPITAL']::text[],
    array[null,%L]::uuid[], array[%L,null]::uuid[],
    array['700000','0']::text[], array['0','700000']::text[],
    array['رصيد بنكي افتتاحي بديل','رأس مال افتتاحي بديل']::text[],
    '700000','700000','p2c-opening-second-01')$$,
  :'p2c_project', :'p2c_sum_second', :'p2c_inv1', :'p2c_cash'));
select id as p2c_import_second from public.s7_opening_imports where idempotency_key='p2c-opening-second-01' \gset
select p2c_owner2_run(format($$select public.p2c_validate_import(%L,'p2c-validate-second-01')$$, :'p2c_import_second'));
select p2c_owner2_run(format(
  $$select public.p2c_review_import(%L,'مراجعة أرصدة افتتاحية ثانية','p2c-review-second-01')$$,
  :'p2c_import_second'));
select p2c_assert((select status='READY_FOR_APPROVAL' from public.s7_opening_imports where id=:'p2c_import_second'),
  'second opening import must reach READY_FOR_APPROVAL before the race suite');

-- ---------------------------------------------------------------------------
-- Concurrency fixtures consumed by 29_phase2c_concurrency.sh:
--  * p2c-obl-race-01: full-amount duplicate payment race.
--  * race project with a prepared close run: posting-versus-close race.
-- ---------------------------------------------------------------------------
select p2c_owner1_run(format(
  $$select public.p2c_create_obl(%L,%L,'التزام سباق الدفع',120000,current_date,'EXPENSE','p2c-obl-race-01')$$,
  :'p2c_project', :'p2c_supplier'));
select id as p2c_race_obligation from public.cost_obligations where idempotency_key='p2c-obl-race-01' \gset
select p2c_owner1_run(format($$select public.p2c_authorize_obl(%L,'p2c-race-obl-auth-01')$$, :'p2c_race_obligation'));

select p2c_owner1_run($$select public.create_investment_project(public.p2c_org(),'مشروع سباق الإغلاق',null,null)$$);
select id as p2c_race_project from public.investment_projects where name='مشروع سباق الإغلاق' \gset
select p2c_owner1_run(format($$select public.create_project_cash_account(public.p2c_org(),%L,'حساب سباق الإغلاق','EGP')$$, :'p2c_race_project'));
select id as p2c_race_cash from public.project_cash_accounts where name='حساب سباق الإغلاق' \gset
select p2c_fund_cash(:'p2c_race_project', :'p2c_race_cash', 90000, current_date, 'p2c-fixture-cash-race-close');
select p2c_owner1_run(format(
  $$select public.p2c_create_obl(%L,%L,'التزام سباق الإغلاق',90000,current_date,'EXPENSE','p2c-obl-raceclose-01')$$,
  :'p2c_race_project', :'p2c_supplier'));
select id as p2c_raceclose_obligation from public.cost_obligations where idempotency_key='p2c-obl-raceclose-01' \gset
select p2c_owner1_run(format($$select public.p2c_authorize_obl(%L,'p2c-raceclose-auth-01')$$, :'p2c_raceclose_obligation'));
select p2c_owner1_run(format($$select public.s6_create_accounting_period(public.p2c_org(),%L,current_date-2,current_date)$$, :'p2c_race_project'));
select id as p2c_race_period from public.accounting_periods where project_id=:'p2c_race_project' and status='OPEN' \gset
select p2c_owner1_run(format($$select public.s6_prepare_close_run(public.p2c_org(),%L,%L,'race close prepare')$$, :'p2c_race_project', :'p2c_race_period'));
select id as p2c_race_close_run from public.close_runs where period_id=:'p2c_race_period' and status='PREPARED' \gset

select 'Phase 2C financial integrity SQL suite fixture and sequential cases PASS' as result;
