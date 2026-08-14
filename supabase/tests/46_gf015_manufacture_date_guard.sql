-- GF-015 regression: an InputApplication cannot predate its InputLot manufacture date.
-- Runs after 44_gf015_input_application.sql in the canonical SQL-test sequence and
-- deliberately reuses that suite's authenticated helper functions and fixture rows.

select id as s15_mfg_item
from public.input_items
where internal_reference = 'FERT-UREA'
order by created_at
limit 1
\gset

select fa.project_id as s15_mfg_project,
       fa.crop_cycle_id as s15_mfg_cycle,
       fa.field_id as s15_mfg_field,
       fa.assignment_id as s15_mfg_assignment
from public.field_activities fa
join public.input_applications ia on ia.field_activity_id = fa.id
where ia.input_item_id = :'s15_mfg_item'::uuid
  and fa.activity_type = 'FERTILIZE'
order by fa.created_at
limit 1
\gset

-- Manufacture date is after the attempted application date, while expiry remains valid.
select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_lot('10000000-0000-4000-8000-000000000001',%L,'LOT-U-FUTURE-MFG',null,date '2027-06-15',date '2028-01-01',null,'s15-lot-future-mfg')$$,
  :'s15_mfg_item')) as s15_mfg_lot
\gset

select count(*) as s15_mfg_audit_before
from public.audit_events
where event_type = 'INPUT_APPLICATION_RECORDED'
\gset

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','كجم','1','FEDDAN',null,null,null,'s15-app-before-mfg')$$,
  (select id from public.field_activities
    where project_id = :'s15_mfg_project'::uuid
      and crop_cycle_id = :'s15_mfg_cycle'::uuid
      and field_id = :'s15_mfg_field'::uuid
      and assignment_id = :'s15_mfg_assignment'::uuid
      and activity_type = 'FERTILIZE'
    order by created_at limit 1),
  :'s15_mfg_item', :'s15_mfg_lot'))
  like '%manufactured on%cannot be applied on earlier date%'
  then 1 else 0 end as s15_application_before_manufacture_rejected;

select 1/case when (
  select count(*) from public.input_applications
  where idempotency_key = 's15-app-before-mfg'
) = 0 then 1 else 0 end as s15_before_manufacture_writes_no_application;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'INPUT_APPLICATION_RECORDED'
) = :'s15_mfg_audit_before'::bigint then 1 else 0 end
as s15_before_manufacture_writes_no_audit;

-- The boundary is inclusive: application on the manufacture date is valid.
select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2027-06-15','FERTILIZE',null,null,'تسميد يوم تصنيع التشغيلة',null,'s15-act-on-mfg')$$,
  :'s15_mfg_project', :'s15_mfg_cycle', :'s15_mfg_field', :'s15_mfg_assignment')) as s15_mfg_activity
\gset

select 1/case when s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-15','10','كجم','1','FEDDAN',null,null,null,'s15-app-on-mfg')$$,
  :'s15_mfg_activity', :'s15_mfg_item', :'s15_mfg_lot')) is not null
  then 1 else 0 end as s15_application_on_manufacture_date_ok;

select 1/case when (
  select count(*) from public.input_applications
  where idempotency_key = 's15-app-on-mfg'
) = 1 then 1 else 0 end as s15_on_manufacture_date_written_once;
