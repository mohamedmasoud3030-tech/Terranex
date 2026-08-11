-- GF-005 / S3 current-control precedence regressions.
-- Extends the evidence fixture from 10_s3_integrity_regressions.sql.

select id as cp_asset from public.property_assets where idempotency_key='s3-rt-evidence-asset' \gset
select id as cp_parcel_a from public.parcels where idempotency_key='s3-rt-evidence-pa' \gset
select id as cp_parcel_b from public.parcels where idempotency_key='s3-rt-evidence-pb' \gset

-- A newer parcel-specific failure must supersede an older property-wide PASS
-- for that parcel, so whole-asset title coverage is no longer current.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,%L,'TITLE','نزاع سند أحدث للقطعة ب','FAILED',current_date,null,'السند محل نزاع','00000000-0000-4000-8000-000000000003','TITLE-E-B-FAIL',null,'s3-cp-title-b-fail')$$,
  :'cp_asset',:'cp_parcel_b'));
select 1/case when not public.s3_has_current_effective_control(:'cp_asset','TITLE') then 1 else 0 end
  as s3_cp_newer_parcel_failure_supersedes_global_pass;

-- Even with an active development phase, the property cannot enter DEVELOPING
-- while current title/possession coverage is broken.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.create_development_phase('10000000-0000-4000-8000-000000000001',%L,null,'مرحلة اختبار استمرار السيطرة',1,current_date,current_date+7,'s3-cp-phase-001')$$,
  :'cp_asset'));
select id as cp_phase from public.development_phases where idempotency_key='s3-cp-phase-001' \gset
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.transition_development_phase('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ACTIVE','بدء مرحلة اختبار السيطرة','s3-cp-phase-active')$$,
  :'cp_phase'));
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'HELD','DEVELOPING','محاولة تطوير مع سند غير حالي',null,'s3-cp-develop-block')$$,
  :'cp_asset'),'P0001') then 1 else 0 end
  as s3_cp_development_blocked_when_current_control_lost;

-- A later property-wide PASS becomes the newest applicable fact and restores
-- whole-asset title coverage.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,null,'TITLE','تسوية السند الشاملة','PASSED',current_date,null,'تمت التسوية لكل الأصل','00000000-0000-4000-8000-000000000003','TITLE-E-ALL-RESTORED',null,'s3-cp-title-restored')$$,
  :'cp_asset'));
select 1/case when public.s3_has_current_effective_control(:'cp_asset','TITLE') then 1 else 0 end
  as s3_cp_newer_global_pass_restores_coverage;
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'HELD','DEVELOPING','السيطرة الحالية صالحة وبدأ التطوير','TITLE-RESTORED','s3-cp-develop-ok')$$,
  :'cp_asset'));

-- Complete the phase, then invalidate possession on one parcel. Re-entering
-- HELD must still require current whole-asset control, not historic evidence.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.transition_development_phase('10000000-0000-4000-8000-000000000001',%L,'ACTIVE','COMPLETED','اكتمال مرحلة اختبار السيطرة','s3-cp-phase-done')$$,
  :'cp_phase'));
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,%L,'POSSESSION','تعذر حيازة القطعة أ','FAILED',current_date,null,'تعذر الاستلام الحالي','00000000-0000-4000-8000-000000000003','POS-E-A-FAIL',null,'s3-cp-pos-a-fail')$$,
  :'cp_asset',:'cp_parcel_a'));
select 1/case when not public.s3_has_current_effective_control(:'cp_asset','POSSESSION') then 1 else 0 end
  as s3_cp_newer_parcel_possession_failure_breaks_coverage;
select 1/case when s3_expect_raise('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'DEVELOPING','HELD','محاولة العودة مع حيازة غير حالية',null,'s3-cp-held-block')$$,
  :'cp_asset'),'P0001') then 1 else 0 end
  as s3_cp_return_held_blocked_when_current_control_lost;

select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,null,'POSSESSION','استعادة الحيازة الشاملة','PASSED',current_date,null,'الحيازة الحالية تغطي الأصل','00000000-0000-4000-8000-000000000003','POS-E-ALL-RESTORED',null,'s3-cp-pos-restored')$$,
  :'cp_asset'));
select s3_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.transition_property_asset('10000000-0000-4000-8000-000000000001',%L,'DEVELOPING','HELD','اكتملت المرحلة والسيطرة الحالية صالحة','POS-RESTORED','s3-cp-held-ok')$$,
  :'cp_asset'));
select 1/case when public.s3_current_property_state(:'cp_asset')='HELD' then 1 else 0 end
  as s3_cp_current_control_chain_finishes_held;

select 'S3 current-control precedence regressions PASS' as result;
