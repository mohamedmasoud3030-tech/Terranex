-- GF-005 / S3 — Real Estate operational truth and S2 cost integration.
-- Fresh replay is supplied by scripts/db-test.sh; this suite proves hierarchy,
-- lifecycle/evidence, exact cost derivation, valuation separation, RLS, and DML denial.

create or replace function s3_expect_raise(p_user uuid, p_sql text, p_sqlstate text)
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

create or replace function s3_expect_ok(p_user uuid,p_sql text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
  return true;
exception when others then
  reset role;
  raise notice 's3_expect_ok failed: %',sqlerrm;
  return false;
end $$;

create or replace function s3_run(p_user uuid,p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
end $$;

select id as s3_project from public.investment_projects where name='مشروع النخيل' \gset
select id as s3_project2 from public.investment_projects where name='مشروع ثانٍ' \gset
select id as s3_supplier from public.parties where legal_name='مورد أول' \gset
select id as s3_wip_obligation from public.cost_obligations where idempotency_key='s2-obl-wip-0001' \gset

-- Profile and multiple property roots remain separate from InvestmentProject.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_real_estate_profile('10000000-0000-4000-8000-000000000001',%L,'DEVELOP_SELL','القاهرة، مصر','s3-profile-main-001')$$,:'s3_project'));
select id as s3_profile from public.real_estate_project_profiles where idempotency_key='s3-profile-main-001' \gset
select 1/case when s3_expect_ok('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_real_estate_profile('10000000-0000-4000-8000-000000000001',%L,'DEVELOP_SELL','القاهرة، مصر','s3-profile-main-001')$$,:'s3_project')) then 1 else 0 end as s3_profile_retry_ok;
select 1/case when (select count(*) from public.real_estate_project_profiles where project_id=:'s3_project')=1 then 1 else 0 end as s3_profile_retry_single_effect;

select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_property_asset('10000000-0000-4000-8000-000000000001',%L,'أرض مشروع النخيل','PROP-001','s3-asset-main-0001')$$,:'s3_project'));
select id as s3_asset from public.property_assets where idempotency_key='s3-asset-main-0001' \gset
select 1/case when public.s3_current_property_state(:'s3_asset')='CANDIDATE' then 1 else 0 end as s3_asset_starts_candidate;

-- Same-tenant second project fixture for contamination tests.
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_real_estate_profile('10000000-0000-4000-8000-000000000001',%L,'ACQUIRE_HOLD','الجيزة، مصر','s3-profile-other-01')$$,:'s3_project2'));
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_property_asset('10000000-0000-4000-8000-000000000001',%L,'أصل مشروع ثانٍ','PROP-002','s3-asset-other-001')$$,:'s3_project2'));
select id as s3_other_asset from public.property_assets where idempotency_key='s3-asset-other-001' \gset

-- Explicit area quantity + unit, with no GIS subsystem.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_parcel('10000000-0000-4000-8000-000000000001',%L,'قطعة-أ','CAD-77','قطعة أرض فضاء بحدود العقد',12.500000,'FEDDAN','s3-parcel-main-001')$$,:'s3_asset'));
select id as s3_parcel from public.parcels where idempotency_key='s3-parcel-main-001' \gset
select 1/case when (select area_quantity='12.500000' and area_unit='FEDDAN' from public.parcels_read where id=:'s3_parcel') then 1 else 0 end as s3_parcel_quantity_has_explicit_unit;

-- Lifecycle cannot skip states or impersonate evidence.
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'CANDIDATE','HELD','محاولة تجاوز الفحص',null,'s3-invalid-skip-001')$$,:'s3_asset'),'P0001') then 1 else 0 end as s3_invalid_transition_rejected;
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'CANDIDATE','DUE_DILIGENCE','بدء الفحص',null,'s3-member-transition')$$,:'s3_asset'),'P0001') then 1 else 0 end as s3_member_cannot_confirm_property_state;
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'CANDIDATE','DUE_DILIGENCE','بدء فحص الاستحواذ','مذكرة قرار DD-1','s3-state-dd-00001')$$,:'s3_asset'));
select 1/case when s3_expect_ok('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'CANDIDATE','DUE_DILIGENCE','بدء فحص الاستحواذ','مذكرة قرار DD-1','s3-state-dd-00001')$$,:'s3_asset')) then 1 else 0 end as s3_transition_retry_ok;
select 1/case when (select count(*) from public.property_asset_state_history where property_asset_id=:'s3_asset' and new_state='DUE_DILIGENCE')=1 then 1 else 0 end as s3_transition_retry_single_effect;

-- Acquisition is an immutable legal fact. It does not create payment or journal.
select count(*) as s3_journal_before_acq from public.journal_batches \gset
select count(*) as s3_payments_before_acq from public.project_payments \gset
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.record_property_acquisition('10000000-0000-4000-8000-000000000001',%L,%L,'SALE-2026-44',50000000,750000,'EGP',current_date-10,null,'عقد بيع نسخة موقعة ACQ-44','s3-acquisition-001')$$,:'s3_asset',:'s3_supplier'));
select id as s3_acquisition from public.property_acquisitions where idempotency_key='s3-acquisition-001' \gset
select 1/case when (select count(*) from public.journal_batches)=:'s3_journal_before_acq' then 1 else 0 end as s3_acquisition_creates_no_journal;
select 1/case when (select count(*) from public.project_payments)=:'s3_payments_before_acq' then 1 else 0 end as s3_acquisition_is_not_payment;

-- Acquiring requires both contract and a passed due-diligence check.
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'DUE_DILIGENCE','ACQUIRING','بدء الاستحواذ',null,'s3-acq-before-dd')$$,:'s3_asset'),'P0001') then 1 else 0 end as s3_acquiring_without_check_rejected;
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,%L,'ACQUISITION_CHECK','فحص قانوني للعقد','PASSED',current_date-9,null,'لا توجد موانع مسجلة','00000000-0000-4000-8000-000000000003','تقرير قانوني DD-44','تمت مراجعة سلسلة العقود','s3-control-dd-0001')$$,:'s3_asset',:'s3_parcel'));
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'DUE_DILIGENCE','ACQUIRING','اجتياز الفحص وتسجيل العقد','تقرير قانوني DD-44','s3-state-acq-0001')$$,:'s3_asset'));

-- HELD requires independent effective TITLE and POSSESSION evidence. Payment is
-- not part of this control rule and cannot imply ownership/control.
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'ACQUIRING','HELD','إثبات السيطرة',null,'s3-held-no-proof')$$,:'s3_asset'),'P0001') then 1 else 0 end as s3_held_without_control_evidence_rejected;
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,%L,'TITLE','نقل سند الملكية','PASSED',current_date-5,null,'تم قيد السند','00000000-0000-4000-8000-000000000003','سند مسجل TITLE-44',null,'s3-control-title-1')$$,:'s3_asset',:'s3_parcel'));
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'ACQUIRING','HELD','إثبات السيطرة','سند مسجل TITLE-44','s3-held-title-only')$$,:'s3_asset'),'P0001') then 1 else 0 end as s3_title_alone_does_not_imply_possession;
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,%L,'POSSESSION','محضر استلام الموقع','PASSED',current_date-4,null,'تسليم فعلي للموقع','00000000-0000-4000-8000-000000000003','محضر استلام POS-44',null,'s3-control-pos-001')$$,:'s3_asset',:'s3_parcel'));
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'ACQUIRING','HELD','اكتمل السند والاستلام','TITLE-44 + POS-44','s3-state-held-001')$$,:'s3_asset'));
select 1/case when (select operational_state='HELD' and title_status='PASSED' and possession_status='PASSED' and acquisition_payment_status='NOT_LINKED' from public.property_asset_workspace_read where property_asset_id=:'s3_asset') then 1 else 0 end as s3_title_possession_payment_are_independent;

-- Phase and milestone history prove HELD -> DEVELOPING -> HELD without a PM suite.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_development_phase('10000000-0000-4000-8000-000000000001',%L,%L,'تجهيز الموقع',1,current_date,current_date+30,'s3-phase-main-001')$$,:'s3_asset',:'s3_parcel'));
select id as s3_phase from public.development_phases where idempotency_key='s3-phase-main-001' \gset
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_development_milestone('10000000-0000-4000-8000-000000000001',%L,'تسوية الأرض',1,current_date+10,'s3-milestone-main')$$,:'s3_phase'));
select id as s3_milestone from public.development_milestones where idempotency_key='s3-milestone-main' \gset
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'HELD','DEVELOPING','بدء التطوير',null,'s3-develop-no-phase')$$,:'s3_asset'),'P0001') then 1 else 0 end as s3_developing_requires_active_phase;
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.transition_development_phase('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ACTIVE','بدء أعمال تجهيز الموقع','s3-phase-active-01')$$,:'s3_phase'));
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'HELD','DEVELOPING','بدأت مرحلة تجهيز الموقع','PHASE-1','s3-state-develop-1')$$,:'s3_asset'));
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.transition_development_milestone('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ACTIVE','بدء تسوية الأرض','s3-mile-active-001')$$,:'s3_milestone'));
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.transition_development_milestone('10000000-0000-4000-8000-000000000001',%L,'ACTIVE','COMPLETED','اكتملت التسوية حسب المعاينة','s3-mile-done-0001')$$,:'s3_milestone'));
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'DEVELOPING','HELD','اكتمال التطوير',null,'s3-held-phase-active')$$,:'s3_asset'),'P0001') then 1 else 0 end as s3_return_held_requires_completed_phase;
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.transition_development_phase('10000000-0000-4000-8000-000000000001',%L,'ACTIVE','COMPLETED','اكتمال مرحلة تجهيز الموقع','s3-phase-done-0001')$$,:'s3_phase'));
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'DEVELOPING','HELD','انتهاء مرحلة التطوير الحالية','PHASE-1-DONE','s3-state-reheld-1')$$,:'s3_asset'));
select 1/case when public.s3_current_property_state(:'s3_asset')='HELD' and (select count(*) from public.property_asset_state_history where property_asset_id=:'s3_asset')=6 then 1 else 0 end as s3_complete_lifecycle_and_history;
select 1/case when (select operational_state='COMPLETED' and actual_start_at is not null and actual_end_at is not null from public.development_phases_read where phase_id=:'s3_phase') then 1 else 0 end as s3_phase_actual_dates_derived_from_history;
select 1/case when (select operational_state='COMPLETED' and completed_at is not null from public.development_milestones_read where milestone_id=:'s3_milestone') then 1 else 0 end as s3_milestone_transition_audited;

-- Wrong hierarchy and same-tenant cross-project contamination fail at DB boundary.
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_development_phase('10000000-0000-4000-8000-000000000001',%L,null,'مرحلة مشروع آخر',1,current_date,current_date+1,'s3-phase-other-001')$$,:'s3_other_asset'));
select id as s3_other_phase from public.development_phases where idempotency_key='s3-phase-other-001' \gset
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.classify_property_cost('10000000-0000-4000-8000-000000000001',%L,%L,null,null,'CONSTRUCTION','قرار رسملة WIP','s3-cross-project-cost')$$,:'s3_wip_obligation',:'s3_other_asset'),'P0001') then 1 else 0 end as s3_same_tenant_cross_project_cost_rejected;
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.classify_property_cost('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,'CONSTRUCTION','قرار رسملة WIP','s3-wrong-phase-cost')$$,:'s3_wip_obligation',:'s3_asset',:'s3_parcel',:'s3_other_phase'),'23503') then 1 else 0 end as s3_phase_from_wrong_property_rejected;

-- Classify an existing S2 obligation without copying its amount or posting.
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.classify_property_cost('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,'CONSTRUCTION','قرار المعالجة CAPITALIZABLE_WIP في S2','s3-cost-class-main')$$,:'s3_wip_obligation',:'s3_asset',:'s3_parcel',:'s3_phase'));
select id as s3_cost_item from public.property_cost_items where idempotency_key='s3-cost-class-main' \gset
select 1/case when not exists(select 1 from information_schema.columns where table_schema='public' and table_name='property_cost_items' and column_name in ('amount_minor_units','actual_minor_units','committed_minor_units','paid_minor_units')) then 1 else 0 end as s3_no_duplicate_editable_cost_balance;

-- Budget versions preserve history; latest approved version drives the view.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.propose_property_budget('10000000-0000-4000-8000-000000000001',%L,'EGP','خطة تجهيز معتمدة أولية',array[%L::uuid],array[%L::uuid],array['CONSTRUCTION'],array[700000::bigint],'s3-budget-v1-0001')$$,:'s3_asset',:'s3_parcel',:'s3_phase'));
select id as s3_budget1 from public.property_budget_versions where idempotency_key='s3-budget-v1-0001' \gset
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.approve_property_budget('10000000-0000-4000-8000-000000000001',%L,'s3-budget-member')$$,:'s3_budget1'),'P0001') then 1 else 0 end as s3_budget_approval_owner_only;
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.approve_property_budget('10000000-0000-4000-8000-000000000001',%L,'s3-budget-v1-appr')$$,:'s3_budget1'));
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.propose_property_budget('10000000-0000-4000-8000-000000000001',%L,'EGP','تحديث تقدير تجهيز الموقع',array[%L::uuid],array[%L::uuid],array['CONSTRUCTION'],array[800000::bigint],'s3-budget-v2-0001')$$,:'s3_asset',:'s3_parcel',:'s3_phase'));
select id as s3_budget2 from public.property_budget_versions where idempotency_key='s3-budget-v2-0001' \gset
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.approve_property_budget('10000000-0000-4000-8000-000000000001',%L,'s3-budget-v2-appr')$$,:'s3_budget2'));
select 1/case when (select count(*) from public.property_budget_versions where property_asset_id=:'s3_asset' and status='APPROVED')=2 and (select sum(total_minor_units::bigint) from public.property_budget_versions_read where property_asset_id=:'s3_asset')=1500000 then 1 else 0 end as s3_budget_versions_preserved_exactly;

-- Committed is active approved/open S2 obligation outstanding (600000 here).
-- Actual is the authoritative S2 posted WIP debit (600000); variance is budget-actual.
select 1/case when (select budget_minor_units='800000' and committed_minor_units='600000' and actual_minor_units='600000' and variance_minor_units='200000' from public.property_cost_control_read where property_asset_id=:'s3_asset' and parcel_id=:'s3_parcel' and phase_id=:'s3_phase' and cost_category='CONSTRUCTION') then 1 else 0 end as s3_budget_committed_actual_exact;
select 1/case when (select originating_batch_id is not null and obligation_id=:'s3_wip_obligation' and actual_minor_units='600000' from public.property_cost_drilldown_read where property_cost_item_id=:'s3_cost_item') then 1 else 0 end as s3_cost_drilldown_reaches_s2_origin;
select 1/case when (select d.actual_minor_units::bigint=(select sum(jl.debit_minor_units-jl.credit_minor_units) from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id where jl.obligation_id=:'s3_wip_obligation' and sa.role in ('PROJECT_EXPENSE','DEVELOPMENT_WIP')) from public.property_cost_drilldown_read d where d.property_cost_item_id=:'s3_cost_item') then 1 else 0 end as s3_actual_reproducible_from_posted_facts;
select 1/case when (select d.committed_minor_units='600000' from public.property_cost_drilldown_read d where d.property_cost_item_id=:'s3_cost_item') then 1 else 0 end as s3_committed_reproducible_from_open_obligation;
select 1/case when pg_typeof((select actual_minor_units from public.property_cost_control_read where property_asset_id=:'s3_asset' limit 1))='text'::regtype then 1 else 0 end as s3_money_transport_is_text;

-- Sector events permit quantity-free facts and enforce value+unit together.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.confirm_real_estate_event('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,%L,'MILESTONE_NOTE',now(),null,null,'00000000-0000-4000-8000-000000000003','الموقع','معاينة اكتمال التسوية','صورة معاينة EVT-1','s3-event-note-001')$$,:'s3_project',:'s3_asset',:'s3_parcel',:'s3_phase',:'s3_milestone'));
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.confirm_real_estate_event('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,null,'DEVELOPMENT_PROGRESS',now(),12.5,'PERCENT','00000000-0000-4000-8000-000000000003','الموقع','قياس تقدم موضعي',null,'s3-event-qty-0001')$$,:'s3_project',:'s3_asset',:'s3_parcel',:'s3_phase'));
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.confirm_real_estate_event('10000000-0000-4000-8000-000000000001',%L,%L,null,null,null,'SITE_VISIT',now(),10,null,'00000000-0000-4000-8000-000000000003',null,'كمية بلا وحدة',null,'s3-event-no-unit')$$,:'s3_project',:'s3_asset'),'P0001') then 1 else 0 end as s3_event_quantity_requires_unit;
select 1/case when (select count(*) from public.real_estate_events where property_asset_id=:'s3_asset')=2 then 1 else 0 end as s3_confirmed_events_are_facts;

-- Management valuation approval is explicit and has no journal/cash/revenue effect.
select count(*) as s3_journal_before_val from public.journal_batches \gset
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.propose_property_valuation('10000000-0000-4000-8000-000000000001',%L,current_date,'مقيّم مستقل','مقارنة سوقية',65000000,'EGP','مقارنات أراضٍ مماثلة؛ تقييم إداري فقط','MEDIUM','تقرير تقييم VAL-44','s3-valuation-0001')$$,:'s3_asset'));
select id as s3_valuation from public.property_valuations where idempotency_key='s3-valuation-0001' \gset
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.approve_property_valuation('10000000-0000-4000-8000-000000000001',%L,'s3-val-member-001')$$,:'s3_valuation'),'P0001') then 1 else 0 end as s3_valuation_approval_owner_only;
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.approve_property_valuation('10000000-0000-4000-8000-000000000001',%L,'s3-val-approve-001')$$,:'s3_valuation'));
select 1/case when (select status='APPROVED' and amount_minor_units='65000000' from public.property_valuations_read where valuation_id=:'s3_valuation') then 1 else 0 end as s3_management_valuation_approved_exact;
select 1/case when (select count(*) from public.journal_batches)=:'s3_journal_before_val' then 1 else 0 end as s3_valuation_creates_no_posting;
select 1/case when not exists(select 1 from public.journal_batches where source_id=:'s3_valuation') then 1 else 0 end as s3_valuation_not_cash_revenue_or_result;

-- Material facts/history are immutable, and browser table DML is denied.
select 1/case when s2_owner_expect_raise(format($$update public.property_acquisitions set contract_reference='EDIT' where id=%L::uuid$$,:'s3_acquisition'),'P0001') then 1 else 0 end as s3_acquisition_immutable;
select 1/case when s2_owner_expect_raise(format($$delete from public.property_asset_state_history where property_asset_id=%L::uuid$$,:'s3_asset'),'P0001') then 1 else 0 end as s3_history_immutable;
do $$
begin
  perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
  execute 'set role authenticated';
  begin
    insert into public.property_valuations(organization_id,project_id,property_asset_id,effective_date,valuer_source,method,amount_minor_units,currency,assumptions_notes,evidence_reference,prepared_by,idempotency_key,request_hash)
    values('10000000-0000-4000-8000-000000000001',gen_random_uuid(),gen_random_uuid(),current_date,'x','x',1,'EGP','bad','bad','00000000-0000-4000-8000-000000000001','s3-direct-dml-001',repeat('a',64));
    raise exception 'direct browser DML unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;

-- Two-organization RLS and command isolation.
create or replace function s3_cross_tenant_hidden(p_user uuid,p_asset uuid)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  return not exists(select 1 from public.property_asset_workspace_read where property_asset_id=p_asset);
end $$;
select 1/case when s3_cross_tenant_hidden('00000000-0000-4000-8000-000000000002',:'s3_asset') then 1 else 0 end as s3_cross_tenant_read_hidden;
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000002',format(
  $$select public.create_parcel('10000000-0000-4000-8000-000000000001',%L,'تسريب',null,null,1,'M2','s3-cross-tenant-cmd')$$,:'s3_asset'),'P0001') then 1 else 0 end as s3_cross_tenant_command_denied;

-- Timeline is a derived history, not an editable status projection.
select 1/case when (select count(*) from public.real_estate_timeline_read where property_asset_id=:'s3_asset' and event_type in ('PROPERTY_STATE_CHANGED','PHASE_STATE_CHANGED','MILESTONE_STATE_CHANGED','CONTROL_RECORDED','SECTOR_EVENT_CONFIRMED','VALUATION_APPROVED'))>=15 then 1 else 0 end as s3_operational_timeline_complete;

select 'S3 Real Estate operations SQL PASS' as result;
