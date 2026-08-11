-- GF-006 / S4 — disposition, recognition, carrying-cost derecognition,
-- collection, reconciliation, realized result, authorization, and RLS.
-- Fresh replay is supplied by scripts/db-test.sh. Real two-session races run in
-- 14_s4_concurrency.sh.

create or replace function s4_expect_raise(p_user uuid,p_sql text,p_sqlstate text)
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

create or replace function s4_expect_ok(p_user uuid,p_sql text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
  return true;
exception when others then
  reset role;
  raise notice 's4_expect_ok failed: %',sqlerrm;
  return false;
end $$;

create or replace function s4_run(p_user uuid,p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
end $$;

select id as s4_project from public.investment_projects where name='مشروع النخيل' \gset
select id as s4_project2 from public.investment_projects where name='مشروع ثانٍ' \gset
select id as s4_asset from public.property_assets where idempotency_key='s3-asset-main-0001' \gset
select id as s4_no_cost_asset from public.property_assets where idempotency_key='s3-rt-evidence-asset' \gset
select id as s4_other_asset from public.property_assets where idempotency_key='s3-asset-other-001' \gset
select id as s4_cash from public.project_cash_accounts where name='حساب بنك المشروع' \gset
select id as s4_supplier from public.parties where legal_name='مورد أول' \gset

-- Buyer party is an existing S0 primitive; no CRM/customer subsystem is added.
select s4_run('00000000-0000-4000-8000-000000000003',
  $$select public.create_party('10000000-0000-4000-8000-000000000001','مشتري الأصل العقاري','ORGANIZATION')$$);
select id as s4_buyer from public.parties where legal_name='مشتري الأصل العقاري' \gset
select id as s4_foreign_party from public.parties where legal_name='مورد منظمة باء' \gset

-- Cross-project and cross-tenant property/buyer references are rejected by the
-- command and normalized foreign keys.
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_property_disposition('10000000-0000-4000-8000-000000000001',%L,%L,%L,'BAD-PROJECT','BAD-EVIDENCE',1000000,'EGP',current_date,null,'s4-bad-project-001')$$,
  :'s4_project2',:'s4_asset',:'s4_buyer'),'P0001') then 1 else 0 end as s4_cross_project_property_rejected;
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_property_disposition('10000000-0000-4000-8000-000000000001',%L,%L,%L,'BAD-BUYER','BAD-EVIDENCE',1000000,'EGP',current_date,null,'s4-bad-buyer-0001')$$,
  :'s4_project',:'s4_asset',:'s4_foreign_party'),'P0001') then 1 else 0 end as s4_cross_tenant_buyer_rejected;

-- A draft agreement is not a sale, revenue, receivable, cash, or lifecycle
-- transition. Any member prepares; OWNER approves material action.
select count(*) as s4_journal_before_draft from public.journal_batches \gset
select s4_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_property_disposition('10000000-0000-4000-8000-000000000001',%L,%L,%L,'DISP-2026-001','عقد تصرف موقع DISP-001',1000000,'EGP',current_date-2,current_date,'s4-disposition-main-001')$$,
  :'s4_project',:'s4_asset',:'s4_buyer'));
select id as s4_disposition from public.property_dispositions where idempotency_key='s4-disposition-main-001' \gset
select 1/case when (select count(*) from public.journal_batches)=:'s4_journal_before_draft' then 1 else 0 end as s4_draft_agreement_has_no_posting;
select 1/case when not exists(select 1 from public.property_realized_result_read where disposition_id=:'s4_disposition') then 1 else 0 end as s4_draft_excluded_from_result;
select 1/case when public.s3_current_property_state(:'s4_asset')='HELD' then 1 else 0 end as s4_draft_does_not_change_lifecycle;

-- Payload-bound retry has one effect; a different payload or second disposition
-- for the whole property is rejected by the database.
select 1/case when s4_expect_ok('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_property_disposition('10000000-0000-4000-8000-000000000001',%L,%L,%L,'DISP-2026-001','عقد تصرف موقع DISP-001',1000000,'EGP',current_date-2,current_date,'s4-disposition-main-001')$$,
  :'s4_project',:'s4_asset',:'s4_buyer')) then 1 else 0 end as s4_disposition_retry_ok;
select 1/case when (select count(*) from public.property_dispositions where property_asset_id=:'s4_asset')=1 then 1 else 0 end as s4_disposition_retry_single_effect;
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_property_disposition('10000000-0000-4000-8000-000000000001',%L,%L,%L,'DISP-CHANGED','عقد مختلف',999999,'EGP',current_date-2,current_date,'s4-disposition-main-001')$$,
  :'s4_project',:'s4_asset',:'s4_buyer'),'P0001') then 1 else 0 end as s4_disposition_payload_mismatch_rejected;
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_property_disposition('10000000-0000-4000-8000-000000000001',%L,%L,%L,'DISP-SECOND','محاولة بيع ثانية',1200000,'EGP',current_date,null,'s4-second-disposition')$$,
  :'s4_project',:'s4_asset',:'s4_buyer'),'P0001') then 1 else 0 end as s4_second_disposition_same_property_rejected;

select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.approve_property_disposition('10000000-0000-4000-8000-000000000001',%L,'s4-approve-member-01')$$,
  :'s4_disposition'),'P0001') then 1 else 0 end as s4_disposition_approval_owner_only;
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.approve_property_disposition('10000000-0000-4000-8000-000000000001',%L,'s4-approve-main-001')$$,
  :'s4_disposition'));
select 1/case when (select status='APPROVED' from public.property_dispositions where id=:'s4_disposition') then 1 else 0 end as s4_disposition_approved_without_sale_posting;

-- EXITING is an explicit S3-history extension and creates no journal entry.
select count(*) as s4_journal_before_exiting from public.journal_batches \gset
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'HELD','EXITING','بدء إجراءات التخارج','DISP-2026-001','s4-state-exiting-001')$$,
  :'s4_asset'));
select 1/case when public.s3_current_property_state(:'s4_asset')='EXITING' then 1 else 0 end as s4_property_explicitly_exiting;
select 1/case when (select count(*) from public.journal_batches)=:'s4_journal_before_exiting' then 1 else 0 end as s4_lifecycle_change_has_no_journal;

-- S3 test hardening added a second parcel to this asset after its original
-- parcel-scoped controls. Current property-wide evidence restores whole-asset
-- transfer coverage without treating payment as control.
select s4_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,null,'TITLE','سند شامل عند التخارج','PASSED',current_date,null,'السند يغطي الأصل كاملًا','00000000-0000-4000-8000-000000000003','EXIT-TITLE-001',null,'s4-exit-title-001')$$,
  :'s4_asset'));
select s4_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,null,'POSSESSION','حيازة شاملة عند التخارج','PASSED',current_date,null,'الحيازة تغطي الأصل كاملًا','00000000-0000-4000-8000-000000000003','EXIT-POS-001',null,'s4-exit-pos-0001')$$,
  :'s4_asset'));

select count(*) as s4_journal_before_transfer from public.journal_batches \gset
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.confirm_property_control_transfer('10000000-0000-4000-8000-000000000001',%L,current_date,'محضر إقفال وتسليم CTRL-001','s4-transfer-main-001')$$,
  :'s4_disposition'));
select 1/case when (select status='CONTROL_TRANSFERRED' from public.property_dispositions where id=:'s4_disposition') then 1 else 0 end as s4_control_transfer_confirmed_separately;
select 1/case when (select count(*) from public.journal_batches)=:'s4_journal_before_transfer' then 1 else 0 end as s4_control_transfer_has_no_posting;

-- Recognition is OWNER-only and derives 600000 from the active S2
-- DEVELOPMENT_WIP line classified to this property in S3. Budget, commitments,
-- payments, and management valuation do not participate.
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.recognize_property_sale('10000000-0000-4000-8000-000000000001',%L,current_date,'s4-recognize-member')$$,
  :'s4_disposition'),'P0001') then 1 else 0 end as s4_recognition_owner_only;
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.recognize_property_sale('10000000-0000-4000-8000-000000000001',%L,current_date,'s4-recognize-main-01')$$,
  :'s4_disposition'));
select id as s4_recognition from public.property_sale_recognitions where disposition_id=:'s4_disposition' \gset
select journal_batch_id as s4_sale_batch from public.property_sale_recognitions where id=:'s4_recognition' \gset

select 1/case when (
  select count(*)=4 and sum(debit_minor_units)=sum(credit_minor_units)
    and sum(debit_minor_units)=1600000
  from public.journal_lines where batch_id=:'s4_sale_batch'
) then 1 else 0 end as s4_sale_business_transaction_balanced;
select 1/case when (
  select count(*) from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=:'s4_sale_batch'
    and ((sa.role='CUSTOMER_RECEIVABLE' and jl.debit_minor_units=1000000 and jl.credit_minor_units=0)
      or (sa.role='REAL_ESTATE_SALE_REVENUE' and jl.credit_minor_units=1000000 and jl.debit_minor_units=0))
)=2 then 1 else 0 end as s4_revenue_posts_receivable_and_sale_revenue;
select 1/case when (
  select count(*) from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=:'s4_sale_batch'
    and ((sa.role='REAL_ESTATE_COST_OF_SALE' and jl.debit_minor_units=600000 and jl.credit_minor_units=0)
      or (sa.role='DEVELOPMENT_WIP' and jl.credit_minor_units=600000 and jl.debit_minor_units=0))
)=2 then 1 else 0 end as s4_carrying_cost_posts_cost_of_sale_and_wip;
select 1/case when (
  select carrying_cost_minor_units=600000 and
    (select sum(amount_minor_units) from public.property_sale_carrying_cost_sources s where s.recognition_id=r.id)=600000
  from public.property_sale_recognitions r where r.id=:'s4_recognition'
) then 1 else 0 end as s4_carrying_cost_reconciles_to_s2_s3_sources;

-- Duplicate request is idempotent; different-key repeated recognition is
-- rejected and cannot create a second journal effect.
select 1/case when s4_expect_ok('00000000-0000-4000-8000-000000000001',format(
  $$select public.recognize_property_sale('10000000-0000-4000-8000-000000000001',%L,current_date,'s4-recognize-main-01')$$,
  :'s4_disposition')) then 1 else 0 end as s4_recognition_retry_ok;
select 1/case when (select count(*) from public.property_sale_recognitions where property_asset_id=:'s4_asset')=1
  and (select count(*) from public.journal_batches where source_type='PROPERTY_SALE_RECOGNITION' and source_id=:'s4_recognition')=1
  then 1 else 0 end as s4_recognition_retry_single_effect;
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.recognize_property_sale('10000000-0000-4000-8000-000000000001',%L,current_date,'s4-recognize-second')$$,
  :'s4_disposition'),'P0001') then 1 else 0 end as s4_second_recognition_rejected;

-- Initial result proves valuation != result and revenue != cash. The approved
-- S3 management valuation remains a separately labelled 65000000.
select 1/case when (
  select recognized_revenue_minor_units='1000000'
    and carrying_cost_derecognized_minor_units='600000'
    and selling_costs_minor_units='0'
    and realized_result_minor_units='400000'
    and collected_cash_minor_units='0'
    and outstanding_receivable_minor_units='1000000'
    and latest_management_valuation_minor_units='65000000'
  from public.property_realized_result_read where recognition_id=:'s4_recognition'
) then 1 else 0 end as s4_revenue_cash_valuation_result_are_separate;

-- A draft selling-cost obligation and classification do not affect result.
-- Once the existing S2 authorization posts PROJECT_EXPENSE, it appears as a
-- separate selling cost and never enters carrying cost.
select s4_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,'عمولة بيع الأصل',50000,'EGP',current_date,'EXPENSE','s4-selling-obligation')$$,
  :'s4_project',:'s4_supplier'));
select id as s4_selling_obligation from public.cost_obligations where idempotency_key='s4-selling-obligation' \gset
select s4_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.classify_property_selling_cost('10000000-0000-4000-8000-000000000001',%L,%L,null,null,'عمولة وسيط البيع حسب العقد','s4-selling-classify')$$,
  :'s4_selling_obligation',:'s4_asset'));
select 1/case when (select selling_costs_minor_units='0' and realized_result_minor_units='400000'
  from public.property_realized_result_read where recognition_id=:'s4_recognition') then 1 else 0 end as s4_draft_selling_cost_excluded;
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s4-selling-authorize')$$,
  :'s4_selling_obligation'));
select 1/case when (select selling_costs_minor_units='50000' and realized_result_minor_units='350000'
  and carrying_cost_derecognized_minor_units='600000'
  from public.property_realized_result_read where recognition_id=:'s4_recognition') then 1 else 0 end as s4_posted_selling_cost_reduces_result_separately;

-- Partial/multiple collection: Dr existing BANK_CASH / Cr receivable. The first
-- partial receipt leaves revenue unchanged and an outstanding receivable.
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.collect_property_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,400000,current_date,'إيصال عميل 1','s4-collection-member')$$,
  :'s4_recognition',:'s4_cash'),'P0001') then 1 else 0 end as s4_collection_owner_only;
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.collect_property_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,400000,current_date,'إيصال عميل 1','s4-collection-partial')$$,
  :'s4_recognition',:'s4_cash'));
select id as s4_collection1 from public.property_sale_collections where idempotency_key='s4-collection-partial' \gset
select journal_batch_id as s4_collection_batch1 from public.property_sale_collections where id=:'s4_collection1' \gset
select 1/case when (
  select count(*)=2 and sum(debit_minor_units)=sum(credit_minor_units) and sum(debit_minor_units)=400000
  from public.journal_lines where batch_id=:'s4_collection_batch1'
) then 1 else 0 end as s4_partial_collection_balanced;
select 1/case when (
  select count(*) from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=:'s4_collection_batch1'
    and ((sa.role='BANK_CASH' and jl.debit_minor_units=400000 and jl.cash_account_id=:'s4_cash')
      or (sa.role='CUSTOMER_RECEIVABLE' and jl.credit_minor_units=400000))
)=2 then 1 else 0 end as s4_collection_posts_cash_and_receivable;
select 1/case when (
  select recognized_revenue_minor_units='1000000' and collected_cash_minor_units='400000'
    and outstanding_receivable_minor_units='600000'
  from public.property_realized_result_read where recognition_id=:'s4_recognition'
) then 1 else 0 end as s4_partial_cash_does_not_change_revenue;

select 1/case when s4_expect_ok('00000000-0000-4000-8000-000000000001',format(
  $$select public.collect_property_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,400000,current_date,'إيصال عميل 1','s4-collection-partial')$$,
  :'s4_recognition',:'s4_cash')) then 1 else 0 end as s4_collection_retry_ok;
select 1/case when (select count(*) from public.property_sale_collections where idempotency_key='s4-collection-partial')=1 then 1 else 0 end as s4_collection_retry_single_effect;
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.collect_property_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,700000,current_date,'تجاوز الذمم','s4-collection-over')$$,
  :'s4_recognition',:'s4_cash'),'P0001') then 1 else 0 end as s4_collection_ceiling_rejected;
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.collect_property_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,600000,current_date,'إيصال عميل 2','s4-collection-final')$$,
  :'s4_recognition',:'s4_cash'));
select 1/case when (select collected_cash_minor_units='1000000' and outstanding_receivable_minor_units='0'
  and recognized_revenue_minor_units='1000000' from public.property_realized_result_read where recognition_id=:'s4_recognition') then 1 else 0 end as s4_multiple_collections_fully_settle_receivable;

-- Reuse S2 positive bank-statement facts and a cross-type unique allocation.
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.import_bank_statement_lines('10000000-0000-4000-8000-000000000001',%L,array[current_date],array['400000'],array['EGP'],array['تحصيل مشتري الأصل'],array['SALE-COL-1'],'s4-bank-import-001')$$,
  :'s4_cash'));
select id as s4_statement_line from public.bank_statement_lines where provider_reference='SALE-COL-1' \gset
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.reconcile_property_sale_collection('10000000-0000-4000-8000-000000000001',%L,%L,'s4-collection-reconcile')$$,
  :'s4_collection1',:'s4_statement_line'));
select 1/case when (select is_reconciled and matched_collection_id=:'s4_collection1'
  from public.bank_statement_line_status_read where line_id=:'s4_statement_line') then 1 else 0 end as s4_collection_reuses_bank_reconciliation_truth;

-- Recognition without any posted, property-classified WIP must fail rather
-- than estimating from acquisition contract, budget, commitment, or valuation.
select s4_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_property_disposition('10000000-0000-4000-8000-000000000001',%L,%L,%L,'DISP-NOCOST','اتفاق أصل بلا WIP',2000000,'EGP',current_date,null,'s4-no-cost-disposition')$$,
  :'s4_project',:'s4_no_cost_asset',:'s4_buyer'));
select id as s4_no_cost_disposition from public.property_dispositions where idempotency_key='s4-no-cost-disposition' \gset
select 1/case when not exists(select 1 from public.property_realized_result_read where disposition_id=:'s4_no_cost_disposition') then 1 else 0 end as s4_unposted_disposition_excluded;
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.approve_property_disposition('10000000-0000-4000-8000-000000000001',%L,'s4-no-cost-approve')$$,:'s4_no_cost_disposition'));
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'HELD','EXITING','اختبار فشل التكلفة الدفترية','DISP-NOCOST','s4-no-cost-exiting')$$,:'s4_no_cost_asset'));
-- A classified but unposted draft is not carrying cost. Once control transfers,
-- the shared disposition-row lock also prevents that draft from racing into the
-- recognition snapshot through late WIP authorization.
select s4_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,'WIP غير مرحل قبل التخارج',900,'EGP',current_date,'CAPITALIZABLE_WIP','s4-no-cost-draft-wip')$$,
  :'s4_project',:'s4_supplier'));
select id as s4_no_cost_draft_wip from public.cost_obligations where idempotency_key='s4-no-cost-draft-wip' \gset
select s4_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.classify_property_cost('10000000-0000-4000-8000-000000000001',%L,%L,null,null,'OTHER','تصنيف WIP غير مرحل','s4-no-cost-draft-class')$$,
  :'s4_no_cost_draft_wip',:'s4_no_cost_asset'));
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.confirm_property_control_transfer('10000000-0000-4000-8000-000000000001',%L,current_date,'دليل انتقال بلا تكلفة','s4-no-cost-transfer')$$,:'s4_no_cost_disposition'));
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s4-no-cost-late-wip')$$,
  :'s4_no_cost_draft_wip'),'P0001') then 1 else 0 end as s4_late_wip_after_control_transfer_rejected;
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.recognize_property_sale('10000000-0000-4000-8000-000000000001',%L,current_date,'s4-no-cost-recognize')$$,
  :'s4_no_cost_disposition'),'P0001') then 1 else 0 end as s4_missing_authoritative_carrying_cost_fails;
select 1/case when not exists(select 1 from public.journal_batches jb where jb.idempotency_key like 's4-sale-batch-%' and jb.source_id not in (:'s4_recognition'::uuid)) then 1 else 0 end as s4_failed_recognition_leaves_no_half_posting;

-- DISPOSED is explicit after recognition and does not create another journal.
select count(*) as s4_journal_before_disposed from public.journal_batches \gset
select s4_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'EXITING','DISPOSED','اكتمل التصرف والاعتراف','SALE-BATCH','s4-state-disposed-001')$$,
  :'s4_asset'));
select 1/case when public.s3_current_property_state(:'s4_asset')='DISPOSED' then 1 else 0 end as s4_property_explicitly_disposed;
select 1/case when (select count(*) from public.journal_batches)=:'s4_journal_before_disposed' then 1 else 0 end as s4_disposed_state_has_no_implicit_posting;
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_property_disposition('10000000-0000-4000-8000-000000000001',%L,%L,%L,'SOLD-AGAIN','محاولة بيع أصل متصرف',1,'EGP',current_date,null,'s4-sold-again-001')$$,
  :'s4_project',:'s4_asset',:'s4_buyer'),'P0001') then 1 else 0 end as s4_disposed_property_cannot_sell_twice;

-- Read models drill to source journals/evidence and tenant isolation applies to
-- base tables and views. Browser table DML remains denied.
select 1/case when (select count(*) from public.property_realized_result_drilldown_read
  where disposition_id=:'s4_disposition' and fact_type in ('SALE_RECOGNITION','CARRYING_COST_DERECOGNITION','CARRYING_COST_SOURCE','COLLECTION','SELLING_COST'))>=10 then 1 else 0 end as s4_result_totals_have_drilldown_sources;
create or replace function s4_cross_tenant_hidden(p_user uuid,p_disposition uuid)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  return not exists(select 1 from public.property_dispositions_read where disposition_id=p_disposition)
    and not exists(select 1 from public.property_realized_result_read where disposition_id=p_disposition);
end $$;
select 1/case when s4_cross_tenant_hidden('00000000-0000-4000-8000-000000000002',:'s4_disposition') then 1 else 0 end as s4_two_tenant_rls_hides_sale_and_result;
select 1/case when s4_expect_raise('00000000-0000-4000-8000-000000000002',format(
  $$select public.collect_property_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,1,current_date,'cross tenant','s4-cross-tenant-collection')$$,
  :'s4_recognition',:'s4_cash'),'P0001') then 1 else 0 end as s4_cross_tenant_command_denied;

do $$
begin
  perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
  execute 'set role authenticated';
  begin
    insert into public.property_sale_collections(organization_id,project_id,recognition_id,disposition_id,cash_account_id,amount_minor_units,currency,collection_date,evidence_reference,collected_by,idempotency_key,request_hash)
    values('10000000-0000-4000-8000-000000000001',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),1,'EGP',current_date,'bad','00000000-0000-4000-8000-000000000001','s4-direct-dml',repeat('a',64));
    raise exception 'direct S4 browser DML unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;

select 'S4 Revenue and Realized Result SQL PASS' as result;
