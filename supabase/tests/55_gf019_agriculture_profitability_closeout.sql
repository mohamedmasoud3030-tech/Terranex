-- GF-019 / Agriculture profitability, posted-cost attribution and closeout.
-- Synthetic Egypt-oriented fixture only; this is technical acceptance, not UAT.

create or replace function s19_run(p_user uuid,p_sql text) returns uuid language plpgsql as $$
declare v uuid; begin
  perform set_config('request.jwt.claim.sub',p_user::text,true); perform set_config('role','authenticated',false);
  execute p_sql into v; reset role; return v;
end $$;
create or replace function s19_catch(p_user uuid,p_sql text) returns text language plpgsql as $$
declare v text; begin
  perform set_config('request.jwt.claim.sub',p_user::text,true); perform set_config('role','authenticated',false);
  begin execute p_sql; exception when others then v:=sqlerrm; reset role; return v; end;
  reset role; return 'NO_EXCEPTION';
end $$;
create or replace function s19_count(p_user uuid,p_sql text) returns bigint language plpgsql as $$
declare v bigint; begin
  perform set_config('request.jwt.claim.sub',p_user::text,true); perform set_config('role','authenticated',false);
  execute p_sql into v; reset role; return v;
end $$;
create or replace function s19_owner_catch(p_sql text) returns text language plpgsql as $$
begin begin execute p_sql; exception when others then return sqlerrm; end; return 'NO_EXCEPTION'; end $$;

select id as s19_project from public.investment_projects where internal_reference='GF013-AG-A' \gset
select id as s19_other_project from public.investment_projects where internal_reference='GF017-AG-OTHER' \gset
select id as s19_cycle from public.crop_cycles where season_reference='GF018-2026' \gset
select id as s19_field from public.fields where identifier='حقل مبيعات' \gset
select farm_id as s19_farm from public.fields where id=:'s19_field' \gset
select id as s19_buyer from public.parties where legal_name='مشتري محاصيل GF018' \gset
select id as s19_supplier from public.parties where organization_id='10000000-0000-4000-8000-000000000001' order by created_at limit 1 \gset
select id as s19_cash from public.project_cash_accounts where name='حساب تحصيل زراعي GF018' \gset
select id as s19_store from public.storage_locations where internal_reference='GF018-STORE' \gset
select id as s19_lot from public.harvest_lots where lot_reference='GF018-LOT-A' \gset

-- ---------------------------------------------------------------------------
-- 1. Authoritative cost source: posted PROJECT_EXPENSE, never Payment.
-- ---------------------------------------------------------------------------
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,
    'عمالة تشغيل وحصاد للدورة الصناعية',100000,'EGP',current_date,'EXPENSE','s19-cost-obligation')$$,
  :'s19_project',:'s19_supplier')) as s19_obligation \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s19-cost-authorize')$$,
  :'s19_obligation')) as s19_cost_batch \gset
select jl.id as s19_cost_line from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
where jl.batch_id=:'s19_cost_batch' and sa.role='PROJECT_EXPENSE' \gset

select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.attribute_crop_cycle_cost('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,
    60000,'LABOR','سياسة تكلفة التشغيل 2026','كشف عمالة وحصاد SYNTHETIC','s19-cost-attribute')$$,
  :'s19_project',:'s19_cycle',:'s19_field',:'s19_cost_line')) as s19_attribution \gset
select 1/case when (select attributed_amount_minor_units=60000 and currency='EGP'
  and source_journal_line_id=:'s19_cost_line'::uuid from public.crop_cycle_cost_attributions where id=:'s19_attribution')
then 1 else 0 end as s19_valid_source_cost_attribution;
select 1/case when s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.attribute_crop_cycle_cost('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,
    60000,'LABOR','سياسة تكلفة التشغيل 2026','كشف عمالة وحصاد SYNTHETIC','s19-cost-attribute')$$,
  :'s19_project',:'s19_cycle',:'s19_field',:'s19_cost_line'))=:'s19_attribution'
then 1 else 0 end as s19_cost_idempotent_replay;
select 1/case when (select count(*) from public.audit_events where event_type='CROP_CYCLE_COST_ATTRIBUTED' and entity_id=:'s19_attribution')=1
then 1 else 0 end as s19_cost_no_duplicate_audit;
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.attribute_crop_cycle_cost('10000000-0000-4000-8000-000000000001',%L,%L,null,%L,60001,
    'LABOR','سياسة تكلفة التشغيل 2026','كشف عمالة وحصاد SYNTHETIC','s19-cost-attribute')$$,
  :'s19_project',:'s19_cycle',:'s19_cost_line'))='idempotency key payload mismatch'
then 1 else 0 end as s19_cost_idempotency_mismatch;
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.attribute_crop_cycle_cost('10000000-0000-4000-8000-000000000001',%L,%L,null,%L,0,
    'LABOR','سياسة تكلفة التشغيل 2026','دليل تكلفة','s19-cost-zero')$$,
  :'s19_project',:'s19_cycle',:'s19_cost_line'))='attributed cost amount must be positive'
then 1 else 0 end as s19_cost_positive;
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.attribute_crop_cycle_cost('10000000-0000-4000-8000-000000000001',%L,%L,null,%L,50000,
    'LABOR','سياسة تكلفة التشغيل 2026','دليل تكلفة','s19-cost-over')$$,
  :'s19_project',:'s19_cycle',:'s19_cost_line'))='crop cycle cost attribution exceeds authoritative source amount'
then 1 else 0 end as s19_cost_aggregate_ceiling;
select 1/case when s19_catch('00000000-0000-4000-8000-000000000002',format(
  $$select public.attribute_crop_cycle_cost('10000000-0000-4000-8000-000000000001',%L,%L,null,%L,1000,
    'OTHER','سياسة تكلفة التشغيل 2026','دليل تكلفة','s19-cost-tenant')$$,
  :'s19_project',:'s19_cycle',:'s19_cost_line'))='forbidden'
then 1 else 0 end as s19_cost_cross_tenant_rejected;
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.attribute_crop_cycle_cost('10000000-0000-4000-8000-000000000001',%L,%L,null,%L,1000,
    'OTHER','سياسة تكلفة التشغيل 2026','دليل تكلفة','s19-cost-project')$$,
  :'s19_other_project',:'s19_cycle',:'s19_cost_line'))='crop cycle not found in project'
then 1 else 0 end as s19_cost_cross_project_rejected;
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$insert into public.crop_cycle_cost_attributions(organization_id,project_id,crop_cycle_id,source_journal_line_id,
    attributed_amount_minor_units,currency,cost_category,policy_reference,evidence_reference,recorded_by,idempotency_key,request_hash)
    values('10000000-0000-4000-8000-000000000001',%L,%L,%L,1,'EGP','OTHER','سياسة','دليل تكلفة',
    '00000000-0000-4000-8000-000000000001','s19-direct','0000000000000000000000000000000000000000000000000000000000000000')$$,
  :'s19_project',:'s19_cycle',:'s19_cost_line')) like '%permission denied%'
then 1 else 0 end as s19_cost_direct_dml_denied;

-- ---------------------------------------------------------------------------
-- 2. Land acquisition consideration is structurally excluded.
-- ---------------------------------------------------------------------------
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,
    'مقابل شراء أرض مستقل عن التشغيل',500000,'EGP',current_date,'EXPENSE','s19-land-obligation')$$,
  :'s19_project',:'s19_supplier')) as s19_land_obligation \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,'أرض فصل التكلفة SYNTHETIC','S19-LAND-SEPARATION',null,
    3,'FEDDAN','المنيا','PURCHASED',current_date,null,%L,'عقد شراء S19','دليل شراء S19',
    500000,'EGP',%L,'s19-land-asset')$$,:'s19_project',:'s19_supplier',:'s19_land_obligation')) as s19_land_asset \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s19-land-authorize')$$,
  :'s19_land_obligation')) as s19_land_batch \gset
select jl.id as s19_land_line from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
where jl.batch_id=:'s19_land_batch' and sa.role='PROJECT_EXPENSE' \gset
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.attribute_crop_cycle_cost('10000000-0000-4000-8000-000000000001',%L,%L,null,%L,1000,
    'OTHER','سياسة تكلفة التشغيل 2026','دليل تكلفة','s19-land-cost-reject')$$,
  :'s19_project',:'s19_cycle',:'s19_land_line'))='land acquisition consideration is not eligible for crop cycle operating cost'
then 1 else 0 end as s19_purchased_land_consideration_excluded;
select 1/case when not exists(select 1 from public.crop_cycle_cost_sources_read where source_journal_line_id=:'s19_land_line')
  and not exists(select 1 from information_schema.columns where table_schema='public' and table_name='agricultural_land_assets'
    and column_name in ('depreciation_minor_units','amortization_minor_units','fair_value_minor_units'))
then 1 else 0 end as s19_no_land_depreciation_amortization_fair_value;
select 1/case when (select land_asset_names='أرض النيل' and land_control_bases='PURCHASED'
  and land_consideration_minor_units='50000000' and attributed_operating_cost_minor_units='0'
  from public.crop_cycle_results_read where crop_cycle_id=(select id from public.crop_cycles where season_reference='موسم 2027-HV'))
  and (select agreed_consideration_minor_units is null from public.agricultural_land_assets where internal_reference='LAND-002')
  and (select agreed_consideration_minor_units is null from public.agricultural_land_assets where internal_reference='LAND-004')
then 1 else 0 end as s19_land_position_separate_and_nonowned_not_costed;

-- ---------------------------------------------------------------------------
-- 3. Dedicated close fixture keeps the GF-018 cycle HARVESTING so its real
-- two-session oversell/collection suite can still run later in this gate.
-- ---------------------------------------------------------------------------
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_field('10000000-0000-4000-8000-000000000001',%L,%L,
    'حقل إغلاق GF019',2,'FEDDAN',null,null,'s19-close-field')$$,
  :'s19_project',:'s19_farm')) as s19_close_field \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,
    'فلفل','هجين','GF019-CLOSE-2026',current_date-30,current_date+30,null,null,'s19-close-cycle')$$,
  :'s19_project')) as s19_close_cycle \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ESTABLISHED','تجهيز دورة الإغلاق','دليل 19-1','s19-close-established')$$,
  :'s19_close_cycle')) as s19_close_t1 \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ESTABLISHED','GROWING','نمو دورة الإغلاق','دليل 19-2','s19-close-growing')$$,
  :'s19_close_cycle')) as s19_close_t2 \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'GROWING','HARVESTING','بدء حصاد الإغلاق','دليل 19-3','s19-close-harvesting')$$,
  :'s19_close_cycle')) as s19_close_t3 \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,
    2,'FEDDAN',current_date-30,current_date+30,'s19-close-assignment')$$,
  :'s19_project',:'s19_close_cycle',:'s19_close_field')) as s19_close_assignment \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,current_date,
    22,20,'كجم','أولى','GF019-CLOSE-LOT',%L,'حصاد إغلاق صناعي','دليل حصاد 19','s19-close-harvest')$$,
  :'s19_close_assignment',:'s19_store')) as s19_close_harvest \gset
select id as s19_close_lot from public.harvest_lots where harvest_event_id=:'s19_close_harvest' \gset

select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,%L,
    'GF019-SYNTHETIC-SALE','طلب شراء تكميلي',current_date,'EGP','تسليم من المخزن','دليل اتفاق تكميلي',
    array[%L::uuid],array[%L::uuid],array[10::numeric],array[1000::bigint],'s19-sale')$$,
  :'s19_project',:'s19_buyer',:'s19_close_lot',:'s19_store')) as s19_sale \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.approve_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,'s19-sale-approve')$$,:'s19_sale')) as s19_approved \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.recognize_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,current_date,
    'إذن تسليم تكميلي','s19-sale-recognize')$$,:'s19_sale')) as s19_recognition \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.collect_agriculture_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,
    2000,current_date,'إيصال تحصيل جزئي','s19-collection')$$,:'s19_recognition',:'s19_cash')) as s19_collection \gset

select 1/case when (select gross_harvest_quantity='189.000000'
  and net_accepted_harvest_quantity='180.000000' and harvest_loss='9.000000'
  and quantity_sold='120.000000' and remaining_physical_inventory='60.000000'
  and recognized_revenue_minor_units='130000' and cash_collected_minor_units='130000'
  and receivable_outstanding_minor_units='0'
  and attributed_operating_cost_minor_units='60000' and operating_result_to_date_minor_units='70000'
  and remaining_inventory_value_status='UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'
  and cogs_status='NOT_GUESSED'
  from public.crop_cycle_results_read where crop_cycle_id=:'s19_cycle')
then 1 else 0 end as s19_reproducible_result_revenue_cash_inventory_cost;
select 1/case when (select spoilage_quantity='5.000000' from public.crop_cycle_results_read
  where crop_cycle_id=(select id from public.crop_cycles where season_reference='موسم 2027-HV'))
then 1 else 0 end as s19_spoilage_derived_from_movements;
select 1/case when (select gross_harvest_quantity='22.000000' and net_accepted_harvest_quantity='20.000000'
  and harvest_loss='2.000000' and quantity_sold='10.000000' and remaining_physical_inventory='10.000000'
  and recognized_revenue_minor_units='10000' and cash_collected_minor_units='2000'
  and receivable_outstanding_minor_units='8000' from public.crop_cycle_results_read where crop_cycle_id=:'s19_close_cycle')
then 1 else 0 end as s19_close_fixture_positions_reproducible;
select 1/case when exists(select 1 from public.crop_cycle_integrity_issues_read where crop_cycle_id=:'s19_close_cycle' and code='OPEN_INVENTORY' and severity='WARN')
  and exists(select 1 from public.crop_cycle_integrity_issues_read where crop_cycle_id=:'s19_close_cycle' and code='OPEN_RECEIVABLE' and severity='WARN')
then 1 else 0 end as s19_open_commercial_positions_visible;

-- Inject and remove corruption as the database owner to prove close recomputes
-- hard integrity rather than trusting command history. Production roles cannot
-- perform these mutations; direct-DML denial is asserted above.
set session_replication_role=replica;
update public.crop_cycle_cost_attributions set attributed_amount_minor_units=100001 where id=:'s19_attribution';
reset session_replication_role;
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.close_crop_cycle('10000000-0000-4000-8000-000000000001',%L,%L,'اختبار سقف التكلفة','دليل اختبار','s19-block-cost')$$,
  :'s19_project',:'s19_cycle'))='crop cycle close blocked: COST_ATTRIBUTION_CEILING_BROKEN'
then 1 else 0 end as s19_broken_cost_attribution_blocks_close;
set session_replication_role=replica;
update public.crop_cycle_cost_attributions set attributed_amount_minor_units=60000 where id=:'s19_attribution';
reset session_replication_role;

select m.id as s19_sale_issue,m.quantity as s19_sale_issue_quantity
from public.harvest_inventory_movements m join public.agriculture_sale_lines sl on sl.id=m.agriculture_sale_line_id
join public.agriculture_sales s on s.id=sl.sale_id where s.sale_reference='SALE-AG-018-001' order by sl.line_no limit 1 \gset
set session_replication_role=replica;
update public.harvest_inventory_movements set quantity=quantity-1 where id=:'s19_sale_issue';
reset session_replication_role;
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.close_crop_cycle('10000000-0000-4000-8000-000000000001',%L,%L,'اختبار تطابق البيع','دليل اختبار','s19-block-sale')$$,
  :'s19_project',:'s19_cycle'))='crop cycle close blocked: BROKEN_SALE_ISSUE'
then 1 else 0 end as s19_broken_sale_inventory_reconciliation_blocks_close;
set session_replication_role=replica;
update public.harvest_inventory_movements set quantity=:'s19_sale_issue_quantity' where id=:'s19_sale_issue';
reset session_replication_role;

set session_replication_role=replica;
insert into public.harvest_inventory_movements(
  id,organization_id,project_id,harvest_lot_id,movement_type,movement_date,quantity,unit,
  from_storage_id,reason,evidence_reference,recorded_by,idempotency_key,request_hash
) values(
  '19000000-0000-4000-8000-000000000019','10000000-0000-4000-8000-000000000001',:'s19_project',:'s19_lot',
  'ADJUSTMENT_OUT',current_date,999,'كجم',:'s19_store','حقن تلف لاختبار الإغلاق','اختبار فقط',
  '00000000-0000-4000-8000-000000000001','s19-corrupt-negative',repeat('9',64));
reset session_replication_role;
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.close_crop_cycle('10000000-0000-4000-8000-000000000001',%L,%L,'اختبار الرصيد السالب','دليل اختبار','s19-block-negative')$$,
  :'s19_project',:'s19_cycle'))='crop cycle close blocked: NEGATIVE_INVENTORY'
then 1 else 0 end as s19_negative_inventory_blocks_close;
set session_replication_role=replica;
delete from public.harvest_inventory_movements where id='19000000-0000-4000-8000-000000000019';
reset session_replication_role;

select count(*) as s19_distributions_before from public.s5_distributions where project_id=:'s19_project' \gset
select count(*) as s19_audits_before_close from public.audit_events where entity_id=:'s19_close_cycle' and event_type='CROP_CYCLE_TRANSITIONED' \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.close_crop_cycle('10000000-0000-4000-8000-000000000001',%L,%L,
    'اكتملت أعمال الحصاد والتسليم التشغيلي','محضر إغلاق دورة SYNTHETIC','s19-close')$$,
  :'s19_project',:'s19_close_cycle')) as s19_closeout \gset
select 1/case when public.agriculture_current_cycle_state(:'s19_close_cycle')='CLOSED'
  and (select count(*) from public.crop_cycle_closeouts where crop_cycle_id=:'s19_close_cycle')=1
  and (select remaining_physical_inventory='10.000000' and receivable_outstanding_minor_units='8000'
       from public.crop_cycle_closeouts_read where id=:'s19_closeout')
then 1 else 0 end as s19_close_allows_inventory_and_receivable;
select 1/case when s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.close_crop_cycle('10000000-0000-4000-8000-000000000001',%L,%L,
    'اكتملت أعمال الحصاد والتسليم التشغيلي','محضر إغلاق دورة SYNTHETIC','s19-close')$$,
  :'s19_project',:'s19_close_cycle'))=:'s19_closeout'
then 1 else 0 end as s19_close_true_replay;
select 1/case when (select count(*) from public.crop_cycle_state_history where crop_cycle_id=:'s19_close_cycle' and new_state='CLOSED')=1
  and (select count(*) from public.audit_events where entity_id=:'s19_close_cycle' and event_type='CROP_CYCLE_TRANSITIONED')=:'s19_audits_before_close'::bigint+1
then 1 else 0 end as s19_no_duplicate_transition_or_audit;
select 1/case when (select count(*) from public.s5_distributions where project_id=:'s19_project')=:'s19_distributions_before'::bigint
then 1 else 0 end as s19_close_does_not_auto_distribute;

-- Invalid lifecycle and no-harvest paths are explicitly blocked.
select id as s19_planned_cycle from public.crop_cycles where season_reference='موسم 2026/2027' \gset
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.close_crop_cycle('10000000-0000-4000-8000-000000000001',%L,%L,'إغلاق خاطئ','دليل خاطئ','s19-close-planned')$$,
  :'s19_project',:'s19_planned_cycle'))='crop cycle must be HARVESTING before close'
then 1 else 0 end as s19_invalid_lifecycle_rejected;
select id as s19_no_harvest_cycle from public.crop_cycles where season_reference='موسم 2027-NH' \gset
-- The GF-016 no-harvest fixture is GROWING; move it to HARVESTING to prove the close gate.
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'GROWING','HARVESTING','بدء حصاد دون تسجيل','دليل اختبار','s19-no-harvest-transition')$$,
  :'s19_no_harvest_cycle')) as s19_no_harvest_transition \gset
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.close_crop_cycle('10000000-0000-4000-8000-000000000001',%L,%L,'إغلاق بلا حصاد','دليل إغلاق','s19-close-no-harvest')$$,
  :'s19_project',:'s19_no_harvest_cycle'))='crop cycle close blocked: NO_HARVEST'
then 1 else 0 end as s19_no_harvest_requires_failed_outcome;

-- ---------------------------------------------------------------------------
-- 4. RLS/grants, shared Finance, period controls and no duplicate ledgers.
-- ---------------------------------------------------------------------------
select 1/case when s19_count('00000000-0000-4000-8000-000000000002',format(
  $$select count(*) from public.crop_cycle_results_read where project_id=%L$$,:'s19_project'))=0
then 1 else 0 end as s19_tenant_b_result_rls;
select 1/case when s19_catch('00000000-0000-4000-8000-000000000002',format(
  $$select public.close_crop_cycle('10000000-0000-4000-8000-000000000001',%L,%L,'اختراق','دليل اختراق','s19-close-tenant')$$,
  :'s19_project',:'s19_no_harvest_cycle'))='forbidden'
then 1 else 0 end as s19_tenant_b_close_rejected;
select 1/case when (select bool_and(relrowsecurity and relforcerowsecurity) from pg_class
  where relnamespace='public'::regnamespace and relname in ('crop_cycle_cost_attributions','crop_cycle_closeouts'))
  and not has_table_privilege('authenticated','public.crop_cycle_cost_attributions','INSERT')
  and not has_table_privilege('anon','public.crop_cycle_closeouts','SELECT')
  and not has_function_privilege('public','public.close_crop_cycle(uuid,uuid,uuid,text,text,text)','EXECUTE')
then 1 else 0 end as s19_rls_force_grants;
select 1/case when not exists(select 1 from information_schema.tables where table_schema='public' and table_name in (
  'agriculture_journals','agriculture_expense_ledger','agriculture_investor_balances','agriculture_distributions','crop_cycle_profit_balances','harvest_inventory_values'))
  and (select bool_and(debit=credit) from (select batch_id,sum(debit_minor_units) debit,sum(credit_minor_units) credit from public.journal_lines group by batch_id) q)
then 1 else 0 end as s19_no_agriculture_ledger_shared_journals_balanced;
select 1/case when exists(select 1 from pg_trigger where tgname='journal_batches_period_lock_guard')
  and exists(select 1 from pg_trigger where tgname='journal_lines_period_lock_guard')
  and not exists(select 1 from information_schema.tables where table_schema='public' and table_name='agriculture_accounting_periods')
then 1 else 0 end as s19_shared_s6_period_controls_reused;

-- Append-only correction must precede shared Finance source reversal.
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',%L,'تصحيح المصدر','s19-source-reverse-blocked')$$,
  :'s19_cost_batch'))='reverse active crop cycle cost attributions before reversing the Finance source'
then 1 else 0 end as s19_source_reversal_requires_attribution_offset;
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.reverse_crop_cycle_cost_attribution('10000000-0000-4000-8000-000000000001',%L,
    'تصحيح تحميل الدورة','مذكرة تصحيح تكلفة','s19-attribution-reverse')$$,:'s19_attribution')) as s19_attribution_reversal \gset
select 1/case when (select attributed_operating_cost_minor_units='0' from public.crop_cycle_results_read where crop_cycle_id=:'s19_cycle')
  and (select count(*) from public.crop_cycle_cost_attributions where reversal_of_attribution_id=:'s19_attribution')=1
then 1 else 0 end as s19_append_only_cost_correction;

-- ---------------------------------------------------------------------------
-- 5. Agriculture monetary events obey the shared S6 OPEN/CLOSED period.
-- ---------------------------------------------------------------------------
select s19_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',
    'مشروع اختبار فترة زراعية GF019','GF019-PERIOD-AG',null,'AGRICULTURE')$$) as s19_period_project \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s6_create_accounting_period('10000000-0000-4000-8000-000000000001',%L,current_date-1,current_date+1)$$,
  :'s19_period_project')) as s19_period \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_farm('10000000-0000-4000-8000-000000000001',%L,'مزرعة اختبار الفترة','S19-PERIOD-FARM',null,null,'Africa/Cairo',null,'s19-period-farm')$$,
  :'s19_period_project')) as s19_period_farm \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_field('10000000-0000-4000-8000-000000000001',%L,%L,'حقل اختبار الفترة',1,'FEDDAN',null,null,'s19-period-field')$$,
  :'s19_period_project',:'s19_period_farm')) as s19_period_field \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'باذنجان',null,'S19-PERIOD-CYCLE',current_date-5,current_date+1,null,null,'s19-period-cycle')$$,
  :'s19_period_project')) as s19_period_cycle \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ESTABLISHED','تجهيز اختبار الفترة','دليل فترة 1','s19-period-t1')$$,:'s19_period_cycle')) as s19_period_t1 \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ESTABLISHED','GROWING','نمو اختبار الفترة','دليل فترة 2','s19-period-t2')$$,:'s19_period_cycle')) as s19_period_t2 \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'GROWING','HARVESTING','حصاد اختبار الفترة','دليل فترة 3','s19-period-t3')$$,:'s19_period_cycle')) as s19_period_t3 \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,1,'FEDDAN',current_date-5,current_date+1,'s19-period-assignment')$$,
  :'s19_period_project',:'s19_period_cycle',:'s19_period_field')) as s19_period_assignment \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_storage_location('10000000-0000-4000-8000-000000000001',%L,'مخزن اختبار الفترة','S19-PERIOD-STORE',null,'s19-period-store')$$,
  :'s19_period_project')) as s19_period_store \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,current_date,10,10,'كجم',null,'S19-PERIOD-LOT',%L,null,'دليل حصاد الفترة','s19-period-harvest')$$,
  :'s19_period_assignment',:'s19_period_store')) as s19_period_harvest \gset
select id as s19_period_lot from public.harvest_lots where harvest_event_id=:'s19_period_harvest' \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_project_cash_account('10000000-0000-4000-8000-000000000001',%L,'نقدية اختبار الفترة','EGP')$$,
  :'s19_period_project')) as s19_period_cash \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,%L,'S19-PERIOD-SALE',null,current_date,'EGP',null,'دليل بيع الفترة',
    array[%L::uuid],array[%L::uuid],array[5::numeric],array[1000::bigint],'s19-period-sale')$$,
  :'s19_period_project',:'s19_buyer',:'s19_period_lot',:'s19_period_store')) as s19_period_sale \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.approve_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,'s19-period-sale-approve')$$,:'s19_period_sale')) as s19_period_approved \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.recognize_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,current_date,'إذن تسليم الفترة','s19-period-recognize')$$,
  :'s19_period_sale')) as s19_period_recognition \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.close_crop_cycle('10000000-0000-4000-8000-000000000001',%L,%L,'اكتمال دورة اختبار الفترة','دليل إغلاق الفترة','s19-period-cycle-close')$$,
  :'s19_period_project',:'s19_period_cycle')) as s19_period_cycle_close \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s6_prepare_close_run('10000000-0000-4000-8000-000000000001',%L,%L,'إغلاق فترة زراعية GF019')$$,
  :'s19_period_project',:'s19_period')) as s19_period_close_run \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s6_approve_close_run('10000000-0000-4000-8000-000000000001',%L,'s19-period-close-approve')$$,
  :'s19_period_close_run')) as s19_period_approved_close \gset
select 1/case when (select status='CLOSED' from public.accounting_periods where id=:'s19_period')
then 1 else 0 end as s19_shared_s6_period_closed;

select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.collect_agriculture_sale_receivable('10000000-0000-4000-8000-000000000001',%L,%L,1000,current_date,'تحصيل بعد الإغلاق','s19-period-collection-blocked')$$,
  :'s19_period_recognition',:'s19_period_cash')) like 'no open accounting period covers%'
then 1 else 0 end as s19_collection_obeys_closed_period;
select 1/case when not exists(select 1 from public.agriculture_sale_collections where recognition_id=:'s19_period_recognition')
then 1 else 0 end as s19_closed_period_collection_atomic_rollback;

select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,%L,'S19-PERIOD-LATE-SALE',null,current_date,'EGP',null,'دليل بيع متأخر',
    array[%L::uuid],array[%L::uuid],array[2::numeric],array[1000::bigint],'s19-period-late-sale')$$,
  :'s19_period_project',:'s19_buyer',:'s19_period_lot',:'s19_period_store')) as s19_period_late_sale \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.approve_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,'s19-period-late-approve')$$,:'s19_period_late_sale')) as s19_period_late_approved \gset
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.recognize_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,current_date,'تسليم متأخر','s19-period-late-recognize')$$,
  :'s19_period_late_sale')) like 'no open accounting period covers%'
then 1 else 0 end as s19_revenue_obeys_closed_period;
select 1/case when not exists(select 1 from public.agriculture_sale_recognitions where sale_id=:'s19_period_late_sale')
  and not exists(select 1 from public.harvest_inventory_movements where agriculture_sale_line_id in
    (select id from public.agriculture_sale_lines where sale_id=:'s19_period_late_sale'))
then 1 else 0 end as s19_closed_period_revenue_atomic_rollback;

select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,'تكلفة بعد إغلاق الفترة',1000,'EGP',current_date,'EXPENSE','s19-period-cost')$$,
  :'s19_period_project',:'s19_supplier')) as s19_period_cost \gset
select 1/case when s19_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s19-period-cost-authorize')$$,
  :'s19_period_cost')) like 'no open accounting period covers%'
then 1 else 0 end as s19_authoritative_cost_source_obeys_closed_period;

reset role;
select 'GF-019 Agriculture profitability and closeout PASS (synthetic)' as result;
