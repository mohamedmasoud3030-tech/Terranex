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
select id as s19_cycle from public.crop_cycles where season_reference='GF018-2026' \gset
select id as s19_field from public.fields where identifier='حقل مبيعات' \gset
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

-- ---------------------------------------------------------------------------
-- 3. Keep an outstanding receivable and physical stock at operational close.
-- ---------------------------------------------------------------------------
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agriculture_sale('10000000-0000-4000-8000-000000000001',%L,%L,
    'GF019-SYNTHETIC-SALE','طلب شراء تكميلي',current_date,'EGP','تسليم من المخزن','دليل اتفاق تكميلي',
    array[%L::uuid],array[%L::uuid],array[10::numeric],array[1000::bigint],'s19-sale')$$,
  :'s19_project',:'s19_buyer',:'s19_lot',:'s19_store')) as s19_sale \gset
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
  and quantity_sold='130.000000' and remaining_physical_inventory='50.000000'
  and recognized_revenue_minor_units='140000' and cash_collected_minor_units='132000'
  and receivable_outstanding_minor_units='8000'
  and attributed_operating_cost_minor_units='60000' and operating_result_to_date_minor_units='80000'
  and remaining_inventory_value_status='UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'
  and cogs_status='NOT_GUESSED'
  from public.crop_cycle_results_read where crop_cycle_id=:'s19_cycle')
then 1 else 0 end as s19_reproducible_result_revenue_cash_inventory_cost;
select 1/case when exists(select 1 from public.crop_cycle_integrity_issues_read where crop_cycle_id=:'s19_cycle' and code='OPEN_INVENTORY' and severity='WARN')
  and exists(select 1 from public.crop_cycle_integrity_issues_read where crop_cycle_id=:'s19_cycle' and code='OPEN_RECEIVABLE' and severity='WARN')
then 1 else 0 end as s19_open_commercial_positions_visible;

select count(*) as s19_distributions_before from public.s5_distributions where project_id=:'s19_project' \gset
select count(*) as s19_audits_before_close from public.audit_events where entity_id=:'s19_cycle' and event_type='CROP_CYCLE_TRANSITIONED' \gset
select s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.close_crop_cycle('10000000-0000-4000-8000-000000000001',%L,%L,
    'اكتملت أعمال الحصاد والتسليم التشغيلي','محضر إغلاق دورة SYNTHETIC','s19-close')$$,
  :'s19_project',:'s19_cycle')) as s19_closeout \gset
select 1/case when public.agriculture_current_cycle_state(:'s19_cycle')='CLOSED'
  and (select count(*) from public.crop_cycle_closeouts where crop_cycle_id=:'s19_cycle')=1
  and (select remaining_physical_inventory='50.000000' and receivable_outstanding_minor_units='8000'
       from public.crop_cycle_closeouts_read where id=:'s19_closeout')
then 1 else 0 end as s19_close_allows_inventory_and_receivable;
select 1/case when s19_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.close_crop_cycle('10000000-0000-4000-8000-000000000001',%L,%L,
    'اكتملت أعمال الحصاد والتسليم التشغيلي','محضر إغلاق دورة SYNTHETIC','s19-close')$$,
  :'s19_project',:'s19_cycle'))=:'s19_closeout'
then 1 else 0 end as s19_close_true_replay;
select 1/case when (select count(*) from public.crop_cycle_state_history where crop_cycle_id=:'s19_cycle' and new_state='CLOSED')=1
  and (select count(*) from public.audit_events where entity_id=:'s19_cycle' and event_type='CROP_CYCLE_TRANSITIONED')=:'s19_audits_before_close'::bigint+1
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

reset role;
select 'GF-019 Agriculture profitability and closeout PASS (synthetic)' as result;
