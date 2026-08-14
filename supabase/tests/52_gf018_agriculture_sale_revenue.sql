-- GF-018 / Agriculture Sale, Dispatch & Revenue.
-- Functional, tenant, finance-isolation and traceability proof. Two-session
-- oversell/collection races run in 53_gf018_sale_concurrency.sh.

create or replace function s18_run(p_user uuid,p_sql text) returns uuid language plpgsql as $$
declare v uuid; begin
  perform set_config('request.jwt.claim.sub',p_user::text,true); perform set_config('role','authenticated',false);
  execute p_sql into v; reset role; return v;
end $$;
create or replace function s18_catch(p_user uuid,p_sql text) returns text language plpgsql as $$
declare v text; begin
  perform set_config('request.jwt.claim.sub',p_user::text,true); perform set_config('role','authenticated',false);
  begin execute p_sql; exception when others then v:=sqlerrm; reset role; return v; end;
  reset role; return 'NO_EXCEPTION';
end $$;
create or replace function s18_count(p_user uuid,p_sql text) returns bigint language plpgsql as $$
declare v bigint; begin
  perform set_config('request.jwt.claim.sub',p_user::text,true); perform set_config('role','authenticated',false);
  execute p_sql into v; reset role; return v;
end $$;
create or replace function s18_owner_catch(p_sql text) returns text language plpgsql as $$
begin begin execute p_sql; exception when others then return sqlerrm; end; return 'NO_EXCEPTION'; end $$;

select id as s18_project from public.investment_projects where internal_reference='GF013-AG-A' \gset
select id as s18_re_project from public.investment_projects where internal_reference='GF013-RE-A' \gset

-- Dedicated current-date operational fixture avoids interference with GF-016
-- adjustment/transfer proofs and remains compatible with shared period rules.
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_farm('10000000-0000-4000-8000-000000000001',%L,
  'مزرعة مبيعات GF018','GF018-FARM',null,null,'Africa/Cairo',null,'s18-farm-create')$$,:'s18_project')) as s18_farm \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_field('10000000-0000-4000-8000-000000000001',%L,%L,
  'حقل مبيعات',10,'FEDDAN',null,null,'s18-field-create')$$,:'s18_project',:'s18_farm')) as s18_field \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,
  'طماطم','هجين','GF018-2026',current_date-30,current_date+30,null,null,'s18-cycle-create')$$,:'s18_project')) as s18_cycle \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ESTABLISHED','بدء التجهيز','EV-18-1','s18-cycle-established')$$,:'s18_cycle')) as s18_t1 \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ESTABLISHED','GROWING','بدء النمو','EV-18-2','s18-cycle-growing')$$,:'s18_cycle')) as s18_t2 \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'GROWING','HARVESTING','جاهز للحصاد','EV-18-3','s18-cycle-harvesting')$$,:'s18_cycle')) as s18_t3 \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,
  10,'FEDDAN',current_date-30,current_date+30,'s18-assignment')$$,:'s18_project',:'s18_cycle',:'s18_field')) as s18_assignment \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_storage_location('10000000-0000-4000-8000-000000000001',%L,
  'مخزن مبيعات GF018','GF018-STORE',null,'s18-storage-create')$$,:'s18_project')) as s18_storage \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,current_date,
  105,100,'كجم','أولى','GF018-LOT-A',%L,'حصاد مبيعات أ','EV-H-A','s18-harvest-a')$$,:'s18_assignment',:'s18_storage')) as s18_harvest_a \gset
select id as s18_lot_a from public.harvest_lots where harvest_event_id=:'s18_harvest_a' \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,current_date,
  84,80,'كجم','أولى','GF018-LOT-B',%L,'حصاد مبيعات ب','EV-H-B','s18-harvest-b')$$,:'s18_assignment',:'s18_storage')) as s18_harvest_b \gset
select id as s18_lot_b from public.harvest_lots where harvest_event_id=:'s18_harvest_b' \gset

select s18_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_party('10000000-0000-4000-8000-000000000001','مشتري محاصيل GF018','ORGANIZATION')$$) as s18_buyer \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_project_cash_account('10000000-0000-4000-8000-000000000001',%L,'حساب تحصيل زراعي GF018','EGP')$$,:'s18_project')) as s18_cash \gset

select count(*) as s18_journal_before_draft from public.journal_batches \gset
select count(*) as s18_movement_before_draft from public.harvest_inventory_movements \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agriculture_sale(
  '10000000-0000-4000-8000-000000000001',%L,%L,'SALE-AG-018-001','طلب شراء 018',current_date,
  'EGP','تسليم من المخزن','عقد بيع موثق',array[%L::uuid,%L::uuid],array[%L::uuid,%L::uuid],
  array[70::numeric,50::numeric],array[1000::bigint,1200::bigint],'s18-sale-main-create')$$,
  :'s18_project',:'s18_buyer',:'s18_lot_a',:'s18_lot_b',:'s18_storage',:'s18_storage')) as s18_sale \gset

select 1/case when (select status='DRAFT' from public.agriculture_sales where id=:'s18_sale')
  and (select count(*) from public.agriculture_sale_lines where sale_id=:'s18_sale')=2
  and (select sum(line_amount_minor_units) from public.agriculture_sale_lines where sale_id=:'s18_sale')=130000
then 1 else 0 end as s18_multi_line_draft_created;
select 1/case when (select count(*) from public.journal_batches)=:'s18_journal_before_draft'::bigint
  and (select count(*) from public.harvest_inventory_movements)=:'s18_movement_before_draft'::bigint
then 1 else 0 end as s18_draft_has_no_revenue_or_issue;
select 1/case when s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agriculture_sale(
  '10000000-0000-4000-8000-000000000001',%L,%L,'SALE-AG-018-001','طلب شراء 018',current_date,
  'EGP','تسليم من المخزن','عقد بيع موثق',array[%L::uuid,%L::uuid],array[%L::uuid,%L::uuid],
  array[70::numeric,50::numeric],array[1000::bigint,1200::bigint],'s18-sale-main-create')$$,
  :'s18_project',:'s18_buyer',:'s18_lot_a',:'s18_lot_b',:'s18_storage',:'s18_storage'))=:'s18_sale'
then 1 else 0 end as s18_draft_idempotent;

select 1/case when s18_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agriculture_sale(
  '10000000-0000-4000-8000-000000000001',%L,%L,'SALE-BAD-QTY',null,current_date,'EGP',null,null,
  array[%L::uuid],array[%L::uuid],array[0::numeric],array[1000::bigint],'s18-sale-bad-qty')$$,
  :'s18_project',:'s18_buyer',:'s18_lot_a',:'s18_storage'))='sale quantity must be positive'
then 1 else 0 end as s18_quantity_positive;
select 1/case when s18_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agriculture_sale(
  '10000000-0000-4000-8000-000000000001',%L,%L,'SALE-RE-PROJECT',null,current_date,'EGP',null,null,
  array[%L::uuid],array[%L::uuid],array[1::numeric],array[1000::bigint],'s18-sale-re-project')$$,
  :'s18_re_project',:'s18_buyer',:'s18_lot_a',:'s18_storage'))='agriculture project not found'
then 1 else 0 end as s18_real_estate_project_rejected;
select 1/case when s18_catch('00000000-0000-4000-8000-000000000002',format(
  $$select public.create_agriculture_sale(
  '10000000-0000-4000-8000-000000000001',%L,%L,'SALE-TENANT',null,current_date,'EGP',null,null,
  array[%L::uuid],array[%L::uuid],array[1::numeric],array[1000::bigint],'s18-sale-tenant')$$,
  :'s18_project',:'s18_buyer',:'s18_lot_a',:'s18_storage'))='forbidden'
then 1 else 0 end as s18_cross_tenant_rejected;

select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.approve_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,'s18-sale-main-approve')$$,:'s18_sale')) as s18_approved \gset
select 1/case when (select status='APPROVED' from public.agriculture_sales where id=:'s18_sale')
  and not exists(select 1 from public.agriculture_sale_recognitions where sale_id=:'s18_sale')
then 1 else 0 end as s18_approval_has_no_revenue;

select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.recognize_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,current_date,
  'إذن تسليم GF018','s18-sale-main-recognize')$$,:'s18_sale')) as s18_recognition \gset
select journal_batch_id as s18_revenue_batch from public.agriculture_sale_recognitions where id=:'s18_recognition' \gset

select 1/case when (select status='CONTROL_TRANSFERRED' from public.agriculture_sales where id=:'s18_sale')
  and (select count(*) from public.harvest_inventory_movements where movement_type='SALE_ISSUE'
    and agriculture_sale_line_id in (select id from public.agriculture_sale_lines where sale_id=:'s18_sale'))=2
  and public.harvest_lot_storage_balance(:'s18_lot_a',:'s18_storage')=30
  and public.harvest_lot_storage_balance(:'s18_lot_b',:'s18_storage')=30
  and public.harvest_lot_total_balance(:'s18_lot_a')=30
then 1 else 0 end as s18_atomic_sale_issue_and_inventory_decrease;
select 1/case when (select count(*)=2 and sum(debit_minor_units)=sum(credit_minor_units)
  and sum(debit_minor_units)=130000 from public.journal_lines where batch_id=:'s18_revenue_batch')
  and (select count(*) from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
    where jl.batch_id=:'s18_revenue_batch' and sa.role='CUSTOMER_RECEIVABLE' and jl.debit_minor_units=130000)=1
  and (select count(*) from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
    where jl.batch_id=:'s18_revenue_batch' and sa.role='AGRICULTURE_SALE_REVENUE' and jl.credit_minor_units=130000)=1
then 1 else 0 end as s18_revenue_and_receivable_once;
select 1/case when not exists(select 1 from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=:'s18_revenue_batch' and sa.role in ('REAL_ESTATE_COST_OF_SALE','DEVELOPMENT_WIP'))
then 1 else 0 end as s18_no_invented_cogs_valuation;
select 1/case when (select count(*) from public.harvest_lot_sale_traceability_read
  where sale_id=:'s18_sale' and sale_issue_movement_id is not null and revenue_journal_batch_id=:'s18_revenue_batch')=2
then 1 else 0 end as s18_one_step_forward_traceability;

-- Recognition replay remains stable after stock and collection state mutate.
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.collect_agriculture_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,
  30000,current_date,'تحصيل جزئي أول','s18-collection-one')$$,:'s18_recognition',:'s18_cash')) as s18_collection_one \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.collect_agriculture_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,
  20000,current_date,'تحصيل جزئي ثان','s18-collection-two')$$,:'s18_recognition',:'s18_cash')) as s18_collection_two \gset
select 1/case when (select collected_minor_units='50000' and outstanding_receivable_minor_units='80000'
  from public.agriculture_sales_read where sale_id=:'s18_sale') then 1 else 0 end as s18_partial_multiple_collection;
select 1/case when s18_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.collect_agriculture_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,
  90000,current_date,'تحصيل زائد مرفوض','s18-collection-over')$$,:'s18_recognition',:'s18_cash'))
  ='collection exceeds outstanding agriculture receivable'
then 1 else 0 end as s18_over_collection_rejected;
select 1/case when s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.collect_agriculture_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,
  30000,current_date,'تحصيل جزئي أول','s18-collection-one')$$,:'s18_recognition',:'s18_cash'))=:'s18_collection_one'
then 1 else 0 end as s18_collection_idempotent;
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.collect_agriculture_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,
  80000,current_date,'تحصيل الرصيد النهائي','s18-collection-final')$$,:'s18_recognition',:'s18_cash')) as s18_collection_final \gset
select 1/case when (select state='SETTLED' and collected_minor_units='130000'
  and outstanding_receivable_minor_units='0' from public.agriculture_sales_read where sale_id=:'s18_sale')
then 1 else 0 end as s18_settlement_is_derived_from_collections;
select 1/case when s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.recognize_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,current_date,
  'إذن تسليم GF018','s18-sale-main-recognize')$$,:'s18_sale'))=:'s18_recognition'
then 1 else 0 end as s18_recognition_replay_after_collection_and_stock_change;
select 1/case when (select count(*) from public.journal_batches where source_type='AGRICULTURE_SALE_RECOGNITION' and source_id=:'s18_recognition')=1
  and (select count(*) from public.audit_events where event_type='AGRICULTURE_SALE_RECOGNIZED' and entity_id=:'s18_recognition')=1
then 1 else 0 end as s18_revenue_and_audit_not_duplicated;

-- Insufficient stock rolls back physical, commercial and financial facts.
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agriculture_sale(
  '10000000-0000-4000-8000-000000000001',%L,%L,'SALE-AG-018-OVER',null,current_date,'EGP',null,null,
  array[%L::uuid],array[%L::uuid],array[60::numeric],array[1000::bigint],'s18-sale-over-create')$$,
  :'s18_project',:'s18_buyer',:'s18_lot_a',:'s18_storage')) as s18_over_sale \gset
select s18_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.approve_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,'s18-sale-over-approve')$$,:'s18_over_sale')) as s18_over_approved \gset
select 1/case when s18_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.recognize_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,current_date,
  'تسليم غير كاف','s18-sale-over-recognize')$$,:'s18_over_sale')) like 'insufficient inventory%'
  and not exists(select 1 from public.agriculture_sale_recognitions where sale_id=:'s18_over_sale')
  and not exists(select 1 from public.harvest_inventory_movements where agriculture_sale_line_id in
    (select id from public.agriculture_sale_lines where sale_id=:'s18_over_sale'))
then 1 else 0 end as s18_insufficient_inventory_atomic_rollback;

-- Security and append-only material facts.
select 1/case when s18_count('00000000-0000-4000-8000-000000000002',format(
  $$select count(*) from public.agriculture_sales_read where project_id=%L$$,:'s18_project'))=0
then 1 else 0 end as s18_tenant_b_rls;
select 1/case when s18_catch('00000000-0000-4000-8000-000000000001',format(
  $$delete from public.agriculture_sale_lines where sale_id=%L$$,:'s18_sale')) like '%permission denied%'
then 1 else 0 end as s18_direct_dml_denied;
select 1/case when s18_owner_catch(format(
  $$update public.agriculture_sale_collections set amount_minor_units=1 where id=%L$$,:'s18_collection_one'))
  ='agriculture sale recognition, line and collection facts are immutable'
then 1 else 0 end as s18_collection_append_only;
select 1/case when not exists(select 1 from information_schema.tables where table_schema='public'
  and table_name in ('agriculture_journals','agriculture_receivable_ledger','agriculture_cash_ledger','agriculture_inventory_valuations'))
then 1 else 0 end as s18_no_duplicate_agriculture_ledger;
select 1/case when exists(select 1 from pg_constraint where conname='agriculture_sale_lines_amount_matches')
  and (select count(*) from pg_trigger where not tgisinternal and tgname in (
    'agriculture_sale_lines_insert_guard','agriculture_sale_recognitions_insert_guard',
    'agriculture_sale_collections_insert_guard','journal_batches_gf018_sale_reversal_guard'
  ))=4
then 1 else 0 end as s18_cross_fact_integrity_guards_installed;

reset role;
select 'GF-018 Agriculture sale/revenue PASS' as result;
