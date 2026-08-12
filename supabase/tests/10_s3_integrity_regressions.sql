-- Independent GF-005 red-team regressions.
-- Relies on the canonical S3 fixture created by 07_s3_real_estate_operations.sql.

select id as rt_project from public.investment_projects where name='مشروع النخيل' \gset
select id as rt_supplier from public.parties where legal_name='مورد أول' \gset
select id as rt_main_asset from public.property_assets where idempotency_key='s3-asset-main-0001' \gset
select id as rt_main_parcel from public.parcels where idempotency_key='s3-parcel-main-001' \gset
select id as rt_main_phase from public.development_phases where idempotency_key='s3-phase-main-001' \gset

-- ---------------------------------------------------------------------------
-- A. A parcel-scoped phase cannot be paired with another parcel from the same
-- property. The original composite FKs proved common ancestry but not sibling
-- alignment.
-- ---------------------------------------------------------------------------
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_parcel('10000000-0000-4000-8000-000000000001',%L,'قطعة-ب','CAD-78','قطعة ثانية لنفس الأصل',3.250000,'FEDDAN','s3-rt-parcel-b-001')$$,
  :'rt_main_asset'));
select id as rt_other_parcel from public.parcels where idempotency_key='s3-rt-parcel-b-001' \gset

select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.confirm_real_estate_event('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,null,'DEVELOPMENT_PROGRESS',now(),10,'PERCENT','00000000-0000-4000-8000-000000000003',null,'اختبار تعارض القطعة والمرحلة',null,'s3-rt-wrong-parcel-event')$$,
  :'rt_project',:'rt_main_asset',:'rt_other_parcel',:'rt_main_phase'),'P0001') then 1 else 0 end
  as s3_rt_event_rejects_same_asset_wrong_parcel;

select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.propose_property_budget('10000000-0000-4000-8000-000000000001',%L,'EGP','اختبار تعارض أبعاد الميزانية',array[%L::uuid],array[%L::uuid],array['CONSTRUCTION'],array[12345::bigint],'s3-rt-wrong-budget-dim')$$,
  :'rt_main_asset',:'rt_other_parcel',:'rt_main_phase'),'P0001') then 1 else 0 end
  as s3_rt_budget_rejects_same_asset_wrong_parcel;

-- ---------------------------------------------------------------------------
-- B. Budget dimensions use NULL as a real dimension value. Duplicate NULL
-- dimensions must be rejected, and NULL array positions must participate in
-- the idempotency request hash.
-- ---------------------------------------------------------------------------
select 1/case when s3_expect_ok('00000000-0000-4000-8000-000000000003',format(
  $$select public.propose_property_budget('10000000-0000-4000-8000-000000000001',%L,'EGP','اختبار بصمة مواضع القيم الفارغة',array[null::uuid,%L::uuid],array[null::uuid,null::uuid],array['OTHER','HOLDING'],array[111::bigint,222::bigint],'s3-rt-budget-nullhash')$$,
  :'rt_main_asset',:'rt_main_parcel')) then 1 else 0 end
  as s3_rt_budget_null_position_fixture_created;

select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.propose_property_budget('10000000-0000-4000-8000-000000000001',%L,'EGP','اختبار بصمة مواضع القيم الفارغة',array[%L::uuid,null::uuid],array[null::uuid,null::uuid],array['OTHER','HOLDING'],array[111::bigint,222::bigint],'s3-rt-budget-nullhash')$$,
  :'rt_main_asset',:'rt_main_parcel'),'P0001') then 1 else 0 end
  as s3_rt_budget_idempotency_preserves_null_positions;

select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000003',format(
  $$select public.propose_property_budget('10000000-0000-4000-8000-000000000001',%L,'EGP','اختبار منع تكرار نفس بُعد الميزانية',array[null::uuid,null::uuid],array[null::uuid,null::uuid],array['OTHER','OTHER'],array[100::bigint,200::bigint],'s3-rt-budget-dup-null')$$,
  :'rt_main_asset'),'23505') then 1 else 0 end
  as s3_rt_budget_duplicate_null_dimension_rejected;

-- ---------------------------------------------------------------------------
-- C. Property-state evidence must reflect the CURRENT effective control, not
-- any historic PASSED row. Parcel-specific evidence must cover all parcels or
-- an explicit property-level control must cover the asset.
-- ---------------------------------------------------------------------------
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_property_asset('10000000-0000-4000-8000-000000000001',%L,'أصل مراجعة الأدلة','PROP-RT-EVID','s3-rt-evidence-asset')$$,
  :'rt_project'));
select id as rt_evidence_asset from public.property_assets where idempotency_key='s3-rt-evidence-asset' \gset

select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_parcel('10000000-0000-4000-8000-000000000001',%L,'E-A',null,null,1.000000,'FEDDAN','s3-rt-evidence-pa')$$,
  :'rt_evidence_asset'));
select id as rt_evidence_parcel_a from public.parcels where idempotency_key='s3-rt-evidence-pa' \gset

select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_parcel('10000000-0000-4000-8000-000000000001',%L,'E-B',null,null,1.500000,'FEDDAN','s3-rt-evidence-pb')$$,
  :'rt_evidence_asset'));
select id as rt_evidence_parcel_b from public.parcels where idempotency_key='s3-rt-evidence-pb' \gset

select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'CANDIDATE','DUE_DILIGENCE','بدء مراجعة أدلة الاختبار',null,'s3-rt-evidence-dd')$$,
  :'rt_evidence_asset'));

select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.record_property_acquisition('10000000-0000-4000-8000-000000000001',%L,%L,'SALE-RT-EVID',1000000,0,'EGP',current_date-5,null,'عقد اختبار الأدلة','s3-rt-evidence-acq')$$,
  :'rt_evidence_asset',:'rt_supplier'));

-- Only parcel A has a passed DD check: insufficient coverage for a two-parcel asset.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,%L,'ACQUISITION_CHECK','فحص القطعة أ','PASSED',current_date-3,null,'ناجح','00000000-0000-4000-8000-000000000003','DD-E-A',null,'s3-rt-dd-parcel-a')$$,
  :'rt_evidence_asset',:'rt_evidence_parcel_a'));

select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'DUE_DILIGENCE','ACQUIRING','محاولة بتغطية جزئية',null,'s3-rt-acq-partial')$$,
  :'rt_evidence_asset'),'P0001') then 1 else 0 end
  as s3_rt_partial_dd_cannot_cover_whole_property;

-- Property-level PASS followed by property-level FAIL: the later fact supersedes
-- the older PASS for current-state gating.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,null,'ACQUISITION_CHECK','فحص شامل للأصل','PASSED',current_date-2,null,'ناجح','00000000-0000-4000-8000-000000000003','DD-E-ALL-PASS',null,'s3-rt-dd-global-pass')$$,
  :'rt_evidence_asset'));
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,null,'ACQUISITION_CHECK','إعادة فحص شامل','FAILED',current_date-1,null,'ظهرت ملاحظة مانعة','00000000-0000-4000-8000-000000000003','DD-E-ALL-FAIL',null,'s3-rt-dd-global-fail')$$,
  :'rt_evidence_asset'));

select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'DUE_DILIGENCE','ACQUIRING','محاولة بعد فشل أحدث',null,'s3-rt-acq-stale-pass')$$,
  :'rt_evidence_asset'),'P0001') then 1 else 0 end
  as s3_rt_stale_pass_cannot_override_newer_failure;

select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,null,'ACQUISITION_CHECK','إغلاق الملاحظة وإعادة الفحص','PASSED',current_date,null,'أغلق السبب المانع','00000000-0000-4000-8000-000000000003','DD-E-ALL-CLEAR',null,'s3-rt-dd-global-clear')$$,
  :'rt_evidence_asset'));
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'DUE_DILIGENCE','ACQUIRING','الفحص الحالي ناجح','DD-E-ALL-CLEAR','s3-rt-acquiring-ok')$$,
  :'rt_evidence_asset'));

-- Title/possession on only one of two parcels cannot establish whole-asset HELD.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,%L,'TITLE','سند القطعة أ','PASSED',current_date,null,'ساري','00000000-0000-4000-8000-000000000003','TITLE-E-A',null,'s3-rt-title-a')$$,
  :'rt_evidence_asset',:'rt_evidence_parcel_a'));
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,%L,'POSSESSION','استلام القطعة أ','PASSED',current_date,null,'مستلمة','00000000-0000-4000-8000-000000000003','POS-E-A',null,'s3-rt-pos-a')$$,
  :'rt_evidence_asset',:'rt_evidence_parcel_a'));

select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'ACQUIRING','HELD','محاولة ملكية بتغطية قطعة واحدة',null,'s3-rt-held-partial')$$,
  :'rt_evidence_asset'),'P0001') then 1 else 0 end
  as s3_rt_partial_title_possession_cannot_cover_whole_property;

-- Explicit property-level controls cover the complete asset.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,null,'TITLE','سند شامل للأصل','PASSED',current_date,null,'ساري لكل الأصل','00000000-0000-4000-8000-000000000003','TITLE-E-ALL',null,'s3-rt-title-global')$$,
  :'rt_evidence_asset'));
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,null,'POSSESSION','استلام شامل للأصل','PASSED',current_date,null,'تم الاستلام الكامل','00000000-0000-4000-8000-000000000003','POS-E-ALL',null,'s3-rt-pos-global')$$,
  :'rt_evidence_asset'));
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'ACQUIRING','HELD','اكتملت أدلة الأصل الحالية','TITLE-E-ALL + POS-E-ALL','s3-rt-held-ok')$$,
  :'rt_evidence_asset'));

select 1/case when public.s3_current_property_state(:'rt_evidence_asset')='HELD' then 1 else 0 end
  as s3_rt_current_evidence_allows_held;

select 'S3 red-team integrity regressions PASS' as result;
