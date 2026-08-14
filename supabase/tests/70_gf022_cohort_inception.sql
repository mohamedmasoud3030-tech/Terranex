-- GF-022 inception/provenance regression suite.
-- Normal Cohorts use origin_date at UTC midnight as a date-only lower boundary.
-- Derived Cohorts use the exact producing operation effective_at.

select id gf70_project from investment_projects where internal_reference = 'GF020-LS-A' \gset
select id gf70_site_a from livestock_sites
 where internal_reference = 'SITE-A' and project_id = :'gf70_project' \gset
select id gf70_site_b from livestock_sites
 where internal_reference = 'SITE-B' and project_id = :'gf70_project' \gset
select id gf70_herd_a from livestock_herds
 where internal_reference = 'HERD-A' and project_id = :'gf70_project' \gset
select id gf70_existing from livestock_cohorts
 where cohort_reference = 'دفعة أغسطس 2026' and project_id = :'gf70_project' \gset
select current_date + 1 gf70_origin_date \gset

-- ---------------------------------------------------------------------------
-- Normal Cohort: date-only inception boundary.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة قبل تاريخ المصدر', 'PURCHASED', date %L, 10, 'MIXED', null,
    null, null, null, null, null, 'gf70-normal-future'
  )$q$, :'gf70_project', :'gf70_herd_a', :'gf70_site_a', :'gf70_origin_date')) gf70_normal \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل مؤجل زمنيًا', null, 'gf70-normal-active'
  )$q$, :'gf70_project', :'gf70_normal')) gf70_normal_active \gset

select 1/case when (
  select current_quantity = 0 from livestock_cohort_quantity_rollforward
  where cohort_id = :'gf70_normal'
) and (
  select public.livestock_cohort_quantity_as_of(:'gf70_normal', current_timestamp) = 0
) and (
  select opening_headcount = 10
    and operational_inception_at = (:'gf70_origin_date'::date::timestamp at time zone 'UTC')
  from livestock_cohorts_read where id = :'gf70_normal'
) then 1 else 0 end as normal_quantity_is_zero_before_origin;

select 1/case when (
  select public.livestock_cohort_quantity_as_of(
    :'gf70_normal', (:'gf70_origin_date'::date::timestamp at time zone 'UTC')
  ) = 10
) then 1 else 0 end as normal_quantity_starts_at_date_boundary;

-- No operational quantity event may be recorded before normal inception.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1,
    current_timestamp, null, null, 'gf70-normal-birth-before-origin'
  )$q$, :'gf70_project', :'gf70_normal')) like '%precedes Cohort inception%'
then 1 else 0 end as normal_birth_before_origin_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1,
    current_timestamp, 'UNKNOWN', null, null, 'PENDING', null,
    'gf70-normal-mortality-before-origin'
  )$q$, :'gf70_project', :'gf70_normal')) like '%exceeds the current derived quantity%'
then 1 else 0 end as normal_mortality_before_origin_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, current_timestamp,
    'COHORT_TOTAL', 200, 'KG', null, null, null, 'UNASSESSED', null,
    'gf70-normal-weight-before-origin'
  )$q$, :'gf70_project', :'gf70_normal')) like '%precedes Cohort inception%'
then 1 else 0 end as normal_weight_before_origin_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    current_timestamp, 'حركة قبل بداية الدفعة', null, null, 'gf70-normal-movement-before-origin'
  )$q$, :'gf70_project', :'gf70_normal', :'gf70_site_a', :'gf70_herd_a',
       :'gf70_site_b', :'gf70_herd_a')) like '%precedes Cohort inception%'
then 1 else 0 end as normal_movement_before_origin_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1, current_timestamp,
    'ناتج تقسيم قبل الأصل', %L, %L, null, null, 'مرفوض', null, null,
    'gf70-normal-split-before-origin'
  )$q$, :'gf70_project', :'gf70_normal', :'gf70_herd_a', :'gf70_site_b')) like '%exceeds the current derived quantity%'
then 1 else 0 end as normal_split_before_origin_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.merge_livestock_cohorts(
    '10000000-0000-4000-8000-000000000001', %L,
    array[%L,%L]::uuid[], array[1,1]::integer[], current_timestamp,
    'دمج قبل أصل المصدر', %L, %L, null, null, 'مرفوض', null, null,
    'gf70-normal-merge-before-origin'
  )$q$, :'gf70_project', :'gf70_normal', :'gf70_existing',
       :'gf70_herd_a', :'gf70_site_b')) like '%exceeds the current derived quantity%'
then 1 else 0 end as normal_merge_invalid_sources_rejected;

-- A direct/import-style quantity write is guarded by the same inception rule.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    recorded_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, 'BIRTH', 1, now(),
    '00000000-0000-4000-8000-000000000001', 'gf70-normal-direct-before-origin', repeat('a',64)
  )
$q$, :'gf70_project', :'gf70_normal')) like '%precedes Cohort inception%'
then 1 else 0 end as normal_privileged_event_before_origin_rejected;

-- ---------------------------------------------------------------------------
-- Future SPLIT destination: row may be scheduled, but has no economics yet.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة مصدر انقسام مؤجل', 'PURCHASED', current_date, 30, 'MIXED', null,
    null, null, null, null, null, 'gf70-split-source'
  )$q$, :'gf70_project', :'gf70_herd_a', :'gf70_site_a')) gf70_split_source \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل مصدر الانقسام المؤجل', null, 'gf70-split-source-active'
  )$q$, :'gf70_project', :'gf70_split_source')) gf70_split_source_active \gset
select current_timestamp + interval '2 hours' gf70_split_at \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 5, %L,
    'دفعة ناتجة مستقبلية', %L, %L, null, null, 'انقسام مستقبلي', null, null,
    'gf70-future-split'
  )$q$, :'gf70_project', :'gf70_split_source', :'gf70_split_at',
       :'gf70_herd_a', :'gf70_site_b')) gf70_split_operation \gset
select destination_cohort_id gf70_split_destination
  from livestock_cohort_lineage where operation_id = :'gf70_split_operation' \gset

select 1/case when (
  select current_quantity = 0 from livestock_cohort_quantity_rollforward
  where cohort_id = :'gf70_split_destination'
) and (
  select operational_inception_at = :'gf70_split_at'::timestamptz
  from livestock_cohorts_read where id = :'gf70_split_destination'
) then 1 else 0 end as future_split_destination_has_no_current_quantity;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1,
    %L::timestamptz - interval '1 hour', null, null, 'gf70-future-split-birth-early'
  )$q$, :'gf70_project', :'gf70_split_destination', :'gf70_split_at')) like '%precedes Cohort inception%'
then 1 else 0 end as future_split_birth_before_inception_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    %L::timestamptz - interval '1 hour', 'COHORT_TOTAL', 200, 'KG',
    null, null, null, 'UNASSESSED', null, 'gf70-future-split-weight-early'
  )$q$, :'gf70_project', :'gf70_split_destination', :'gf70_split_at')) like '%precedes Cohort inception%'
then 1 else 0 end as future_split_weight_before_inception_rejected;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1,
    %L::timestamptz + interval '1 hour', null, null, 'gf70-future-split-birth-after'
  )$q$, :'gf70_project', :'gf70_split_destination', :'gf70_split_at')) is not null
then 1 else 0 end as future_split_birth_after_inception_allowed;

-- ---------------------------------------------------------------------------
-- Future MERGE destination gets the same exact producing timestamp boundary.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة مصدر دمج مؤجل', 'PURCHASED', current_date, 20, 'MIXED', null,
    null, null, null, null, null, 'gf70-merge-source'
  )$q$, :'gf70_project', :'gf70_herd_a', :'gf70_site_a')) gf70_merge_source \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل مصدر الدمج المؤجل', null, 'gf70-merge-source-active'
  )$q$, :'gf70_project', :'gf70_merge_source')) gf70_merge_source_active \gset
select current_timestamp + interval '4 hours' gf70_merge_at \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.merge_livestock_cohorts(
    '10000000-0000-4000-8000-000000000001', %L,
    array[%L,%L]::uuid[], array[5,5]::integer[], %L,
    'دفعة دمج مستقبلية', %L, %L, null, null, 'دمج مستقبلي', null, null,
    'gf70-future-merge'
  )$q$, :'gf70_project', :'gf70_split_source', :'gf70_merge_source', :'gf70_merge_at',
       :'gf70_herd_a', :'gf70_site_a')) gf70_merge_operation \gset
select distinct destination_cohort_id gf70_merge_destination
  from livestock_cohort_lineage where operation_id = :'gf70_merge_operation' \gset

select 1/case when (
  select current_quantity = 0 from livestock_cohort_quantity_rollforward
  where cohort_id = :'gf70_merge_destination'
) and (
  select operational_inception_at = :'gf70_merge_at'::timestamptz
  from livestock_cohorts_read where id = :'gf70_merge_destination'
) then 1 else 0 end as future_merge_destination_has_no_current_quantity;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1,
    %L::timestamptz - interval '1 hour', null, null, 'gf70-future-merge-birth-early'
  )$q$, :'gf70_project', :'gf70_merge_destination', :'gf70_merge_at')) like '%precedes Cohort inception%'
then 1 else 0 end as future_merge_birth_before_inception_rejected;

select 'GF-022 Cohort inception and future-derived provenance PASS' result;
