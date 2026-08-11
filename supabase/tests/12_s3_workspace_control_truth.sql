-- GF-005 / S3 workspace truth regression.
-- Extends the current-control fixture from test 11.

select id as wt_asset from public.property_assets where idempotency_key='s3-rt-evidence-asset' \gset
select id as wt_parcel_a from public.parcels where idempotency_key='s3-rt-evidence-pa' \gset

select 1/case when (
  select title_status='PASSED' and possession_status='PASSED'
  from public.property_asset_workspace_read
  where property_asset_id=:'wt_asset'
) then 1 else 0 end as s3_workspace_shows_passed_only_with_full_current_coverage;

-- A later parcel-specific failure must immediately stop the summary card from
-- showing whole-asset title as PASSED, even though an older global PASS exists.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,%L,'TITLE','مراجعة عرض حالة السند','FAILED',current_date,null,'فشل أحدث خاص بالقطعة','00000000-0000-4000-8000-000000000003','TITLE-WT-A-FAIL',null,'s3-wt-title-a-fail')$$,
  :'wt_asset',:'wt_parcel_a'));

select 1/case when (
  select title_status='INCOMPLETE' and title_effective_date is null and title_evidence_reference is null
  from public.property_asset_workspace_read
  where property_asset_id=:'wt_asset'
) then 1 else 0 end as s3_workspace_never_misstates_partial_failed_title_as_passed;

-- A newer global PASS restores the complete-asset projection.
select s3_run('00000000-0000-4000-8000-000000000003',format(
  $$select public.record_property_control('10000000-0000-4000-8000-000000000001',%L,null,'TITLE','إعادة اعتماد السند الشامل للعرض','PASSED',current_date,null,'السند الحالي يغطي الأصل','00000000-0000-4000-8000-000000000003','TITLE-WT-ALL-PASS',null,'s3-wt-title-restored')$$,
  :'wt_asset'));

select 1/case when (
  select title_status='PASSED'
  from public.property_asset_workspace_read
  where property_asset_id=:'wt_asset'
) then 1 else 0 end as s3_workspace_restores_passed_after_newer_full_coverage;

select 'S3 workspace whole-asset control truth PASS' as result;
