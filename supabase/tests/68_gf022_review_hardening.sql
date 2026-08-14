-- GF-022 review hardening: temporal/as-of, privileged species and operation
-- shape, lifecycle boundary, qualitative weight quality, and disposal evidence.
-- The fixtures are intentionally synthetic and project-scoped.

select id gf68_project from investment_projects where internal_reference = 'GF020-LS-A' \gset
select id gf68_site from livestock_sites
 where internal_reference = 'SITE-A' and project_id = :'gf68_project' \gset
select id gf68_herd_a from livestock_herds
 where internal_reference = 'HERD-A' and project_id = :'gf68_project' \gset
select id gf68_herd_b from livestock_herds
 where internal_reference = 'HERD-B' and project_id = :'gf68_project' \gset

select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_herd(
    '10000000-0000-4000-8000-000000000001', %L, 'قطيع أغنام الاختبار',
    'HERD-SHEEP-HARD', 'SHEEP', 'BREEDING', null, 'gf68-sheep-herd'
  )$q$, :'gf68_project')) gf68_sheep_herd \gset

-- ---------------------------------------------------------------------------
-- One as-of rule: current is now, same-time events are one atomic bucket.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة اختبار الزمن', 'PURCHASED', date '2026-08-01', 50, 'MIXED', null,
    null, null, null, null, null, 'gf68-asof-cohort'
  )$q$, :'gf68_project', :'gf68_herd_a', :'gf68_site')) gf68_asof \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل اختبار الزمن', null, 'gf68-asof-active'
  )$q$, :'gf68_project', :'gf68_asof')) gf68_asof_active \gset

select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 10,
    current_timestamp + interval '2 hours', 'ولادة مستقبلية', null, 'gf68-future-birth'
  )$q$, :'gf68_project', :'gf68_asof')) gf68_future_birth \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 60,
    current_timestamp + interval '4 hours', 'DISEASE', 'اختبار مستقبلي',
    'دليل مستقبلي', 'BURIAL', null, 'gf68-future-mortality'
  )$q$, :'gf68_project', :'gf68_asof')) gf68_future_mortality \gset

-- Both future events are visible as scheduled facts, but neither changes now.
select 1/case when (
  select current_quantity = 50 and births = 0 and mortality = 0
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf68_asof'
) then 1 else 0 end as future_events_do_not_change_current;
select 1/case when (
  select count(*) = 2 and bool_and(not is_effective_as_of_now)
  from livestock_quantity_events_read
  where cohort_id = :'gf68_asof'
) then 1 else 0 end as future_events_are_marked_scheduled;
select 1/case when (
  select public.livestock_cohort_quantity_as_of(
    :'gf68_asof', current_timestamp + interval '5 hours'
  ) = 0
) then 1 else 0 end as future_as_of_balance_is_resolved;

-- A mortality dated before a later birth cannot spend that later birth.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة اختبار الرجوع الزمني', 'PURCHASED', date '2026-08-01', 20, 'MIXED', null,
    null, null, null, null, null, 'gf68-backdated-cohort'
  )$q$, :'gf68_project', :'gf68_herd_a', :'gf68_site')) gf68_backdated \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل اختبار الرجوع الزمني', null, 'gf68-backdated-active'
  )$q$, :'gf68_project', :'gf68_backdated')) gf68_backdated_active \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 20,
    current_timestamp + interval '2 days', null, null, 'gf68-later-birth'
  )$q$, :'gf68_project', :'gf68_backdated')) gf68_later_birth \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 21,
    current_timestamp - interval '1 day', 'UNKNOWN', null, null, 'PENDING', null,
    'gf68-backdated-mortality'
  )$q$, :'gf68_project', :'gf68_backdated')) like '%exceeds the current derived quantity%'
then 1 else 0 end as backdated_destructive_event_rejected;

-- At one timestamp, the additive and destructive facts form one bucket. The
-- order of their recording is not a hidden business ordering.
select current_timestamp - interval '1 hour' gf68_same_time \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة اختبار التوقيت المتساوي', 'PURCHASED', date '2026-08-01', 5, 'MIXED', null,
    null, null, null, null, null, 'gf68-same-time-cohort'
  )$q$, :'gf68_project', :'gf68_herd_a', :'gf68_site')) gf68_same_time_cohort \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل اختبار التوقيت المتساوي', null, 'gf68-same-time-active'
  )$q$, :'gf68_project', :'gf68_same_time_cohort')) gf68_same_time_active \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 6, %L, null, null,
    'gf68-same-time-birth'
  )$q$, :'gf68_project', :'gf68_same_time_cohort', :'gf68_same_time')) gf68_same_time_birth \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 6, %L, 'UNKNOWN', null,
    null, 'PENDING', null, 'gf68-same-time-mortality'
  )$q$, :'gf68_project', :'gf68_same_time_cohort', :'gf68_same_time')) gf68_same_time_mortality \gset
select 1/case when (
  select public.livestock_cohort_quantity_as_of(:'gf68_same_time_cohort', :'gf68_same_time') = 5
) and (
  select current_quantity = 5 from livestock_cohort_quantity_rollforward
  where cohort_id = :'gf68_same_time_cohort'
) then 1 else 0 end as same_timestamp_bucket_is_atomic;

-- Weight population uses the weight effective time, not current now.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة اختبار وزن مستقبلي', 'PURCHASED', date '2026-08-01', 10, 'MIXED', null,
    null, null, null, null, null, 'gf68-weight-cohort'
  )$q$, :'gf68_project', :'gf68_herd_a', :'gf68_site')) gf68_weight_cohort \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل اختبار الوزن المستقبلي', null, 'gf68-weight-active'
  )$q$, :'gf68_project', :'gf68_weight_cohort')) gf68_weight_active \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 10,
    current_timestamp + interval '1 hour', null, null, 'gf68-weight-birth'
  )$q$, :'gf68_project', :'gf68_weight_cohort')) gf68_weight_birth \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    current_timestamp + interval '2 hours', 'SAMPLED_AVERAGE', 220, 'KG',
    null, 20, 'كشف وزن مستقبلي', 'HIGH', null, 'gf68-future-weight'
  )$q$, :'gf68_project', :'gf68_weight_cohort')) gf68_future_weight \gset
select 1/case when (
  select current_quantity = 10 from livestock_cohort_quantity_rollforward
  where cohort_id = :'gf68_weight_cohort'
) and (
  select confidence_level = 'HIGH' and sample_size = 20
  from livestock_weight_events_read where id = :'gf68_future_weight'
) then 1 else 0 end as weight_uses_event_time_balance;

-- ---------------------------------------------------------------------------
-- Species continuity: direct/import-style writes cannot bypass it.
-- ---------------------------------------------------------------------------
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_cohort_movements(
    organization_id, project_id, cohort_id, previous_movement_id, effective_at,
    source_site_id, source_herd_id, destination_site_id, destination_herd_id,
    reason, moved_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, null, now(),
    %L, %L, %L, %L, 'حركة بنوع خاطئ',
    '00000000-0000-4000-8000-000000000001', 'gf68-bad-species-move', repeat('a',64)
  )
$q$, :'gf68_project', :'gf68_asof', :'gf68_site', :'gf68_herd_a', :'gf68_site',
     :'gf68_sheep_herd')) like '%species%'
then 1 else 0 end as privileged_cross_species_movement_rejected;
select 1/case when gf20_owner_catch(format($q$
  update public.livestock_herds set species = 'SHEEP' where id = %L
$q$, :'gf68_herd_a')) like '%cannot change%'
then 1 else 0 end as privileged_herd_species_change_rejected;

-- A split lineage into a Sheep Herd is rejected even when the rows are written
-- directly by the database owner instead of through the RPC.
select public.gf022_create_derived_cohort(
  '10000000-0000-4000-8000-000000000001', :'gf68_project', :'gf68_sheep_herd',
  :'gf68_site', 'دفعة وجهة نوع خاطئ', 'SPLIT_FROM_COHORT',
  current_timestamp - interval '1 hour', null, null, null, null,
  '00000000-0000-4000-8000-000000000001', 'gf68-bad-lineage'
) gf68_bad_species_destination \gset
select 1/case when gf20_owner_catch(format($q$
  DO $do$
  BEGIN
    insert into public.livestock_quantity_operations(
      id, organization_id, project_id, operation_type, effective_at, reason,
      performed_by, idempotency_key, request_hash
    ) values (
      '68000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', %L,
      'SPLIT', current_timestamp - interval '1 hour', 'تقسيم بنوع خاطئ',
      '00000000-0000-4000-8000-000000000001', 'gf68-bad-lineage-op', repeat('b',64)
    );
    insert into public.livestock_quantity_events(
      organization_id, project_id, cohort_id, event_type, quantity, effective_at,
      operation_id, recorded_by, idempotency_key, request_hash
    ) values
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'SPLIT_OUT', 1,
       current_timestamp - interval '1 hour', '68000000-0000-4000-8000-000000000001',
       '00000000-0000-4000-8000-000000000001', 'gf68-bad-lineage-out', repeat('c',64)),
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'SPLIT_IN', 1,
       current_timestamp - interval '1 hour', '68000000-0000-4000-8000-000000000001',
       '00000000-0000-4000-8000-000000000001', 'gf68-bad-lineage-in', repeat('d',64));
    insert into public.livestock_cohort_lineage(
      organization_id, project_id, operation_id, source_cohort_id,
      destination_cohort_id, quantity
    ) values (
      '10000000-0000-4000-8000-000000000001', %L,
      '68000000-0000-4000-8000-000000000001', %L, %L, 1
    );
  END $do$;
$q$, :'gf68_project', :'gf68_asof', :'gf68_asof', :'gf68_bad_species_destination',
     :'gf68_asof', :'gf68_bad_species_destination')) like '%compatible species%'
then 1 else 0 end as privileged_cross_species_lineage_rejected;

-- ---------------------------------------------------------------------------
-- Exact SPLIT/MERGE semantic shape under privileged writes.
-- ---------------------------------------------------------------------------
-- Extra balanced SPLIT legs are rejected, even though sum(out) = sum(in).
select 1/case when gf20_owner_catch(format($q$
  DO $do$
  BEGIN
    insert into public.livestock_quantity_operations(
      id, organization_id, project_id, operation_type, effective_at, reason,
      performed_by, idempotency_key, request_hash
    ) values (
      '68000000-0000-0000-8000-000000000002', '10000000-0000-4000-8000-000000000001', %L,
      'SPLIT', current_timestamp - interval '1 hour', 'تقسيم بأطراف زائدة',
      '00000000-0000-4000-8000-000000000001', 'gf68-extra-split-op', repeat('e',64)
    );
    insert into public.livestock_quantity_events(
      organization_id, project_id, cohort_id, event_type, quantity, effective_at,
      operation_id, recorded_by, idempotency_key, request_hash
    ) values
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'SPLIT_OUT', 1,
       current_timestamp - interval '1 hour', '68000000-0000-0000-8000-000000000002',
       '00000000-0000-4000-8000-000000000001', 'gf68-extra-out-1', repeat('f',64)),
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'SPLIT_OUT', 1,
       current_timestamp - interval '1 hour', '68000000-0000-0000-8000-000000000002',
       '00000000-0000-4000-8000-000000000001', 'gf68-extra-out-2', repeat('1',64)),
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'SPLIT_IN', 2,
       current_timestamp - interval '1 hour', '68000000-0000-0000-8000-000000000002',
       '00000000-0000-4000-8000-000000000001', 'gf68-extra-in', repeat('2',64));
    EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  END $do$;
$q$, :'gf68_project', :'gf68_asof', :'gf68_asof', :'gf68_backdated', :'gf68_backdated')) like '%exactly one SPLIT_OUT%'
then 1 else 0 end as privileged_extra_split_legs_rejected;

-- Missing lineage is rejected even when the two split legs balance exactly.
select 1/case when gf20_owner_catch(format($q$
  DO $do$
  BEGIN
    insert into public.livestock_quantity_operations(
      id, organization_id, project_id, operation_type, effective_at, reason,
      performed_by, idempotency_key, request_hash
    ) values (
      '68000000-0000-0000-8000-000000000003', '10000000-0000-4000-8000-000000000001', %L,
      'SPLIT', current_timestamp - interval '1 hour', 'تقسيم بدون نسب',
      '00000000-0000-4000-8000-000000000001', 'gf68-no-lineage-op', repeat('3',64)
    );
    insert into public.livestock_quantity_events(
      organization_id, project_id, cohort_id, event_type, quantity, effective_at,
      operation_id, recorded_by, idempotency_key, request_hash
    ) values
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'SPLIT_OUT', 1,
       current_timestamp - interval '1 hour', '68000000-0000-0000-8000-000000000003',
       '00000000-0000-4000-8000-000000000001', 'gf68-no-lineage-out', repeat('4',64)),
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'SPLIT_IN', 1,
       current_timestamp - interval '1 hour', '68000000-0000-0000-8000-000000000003',
       '00000000-0000-4000-8000-000000000001', 'gf68-no-lineage-in', repeat('5',64));
    EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  END $do$;
$q$, :'gf68_project', :'gf68_asof', :'gf68_backdated')) like '%exactly one lineage%'
then 1 else 0 end as privileged_missing_split_lineage_rejected;

-- MERGE_IN must equal the source total; balanced leg counts alone are not enough.
select 1/case when gf20_owner_catch(format($q$
  DO $do$
  BEGIN
    insert into public.livestock_quantity_operations(
      id, organization_id, project_id, operation_type, effective_at, reason,
      performed_by, idempotency_key, request_hash
    ) values (
      '68000000-0000-0000-8000-000000000004', '10000000-0000-4000-8000-000000000001', %L,
      'MERGE', current_timestamp - interval '1 hour', 'دمج بكمية واردة خاطئة',
      '00000000-0000-4000-8000-000000000001', 'gf68-bad-merge-total', repeat('6',64)
    );
    insert into public.livestock_quantity_events(
      organization_id, project_id, cohort_id, event_type, quantity, effective_at,
      operation_id, recorded_by, idempotency_key, request_hash
    ) values
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'MERGE_OUT', 1,
       current_timestamp - interval '1 hour', '68000000-0000-0000-8000-000000000004',
       '00000000-0000-4000-8000-000000000001', 'gf68-bad-merge-out-1', repeat('7',64)),
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'MERGE_OUT', 1,
       current_timestamp - interval '1 hour', '68000000-0000-0000-8000-000000000004',
       '00000000-0000-4000-8000-000000000001', 'gf68-bad-merge-out-2', repeat('8',64)),
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'MERGE_IN', 1,
       current_timestamp - interval '1 hour', '68000000-0000-0000-8000-000000000004',
       '00000000-0000-4000-8000-000000000001', 'gf68-bad-merge-in', repeat('9',64));
    EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  END $do$;
$q$, :'gf68_project', :'gf68_asof', :'gf68_backdated', :'gf68_weight_cohort')) like '%MERGE_IN quantity must equal%'
then 1 else 0 end as privileged_merge_total_mismatch_rejected;

-- A lineage quantity/source mismatch is rejected independently of conservation.
select 1/case when gf20_owner_catch(format($q$
  DO $do$
  BEGIN
    insert into public.livestock_quantity_operations(
      id, organization_id, project_id, operation_type, effective_at, reason,
      performed_by, idempotency_key, request_hash
    ) values (
      '68000000-0000-0000-8000-000000000005', '10000000-0000-4000-8000-000000000001', %L,
      'MERGE', current_timestamp - interval '1 hour', 'دمج بنسب خاطئة',
      '00000000-0000-4000-8000-000000000001', 'gf68-bad-merge-lineage', repeat('a',64)
    );
    insert into public.livestock_quantity_events(
      organization_id, project_id, cohort_id, event_type, quantity, effective_at,
      operation_id, recorded_by, idempotency_key, request_hash
    ) values
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'MERGE_OUT', 1,
       current_timestamp - interval '1 hour', '68000000-0000-0000-8000-000000000005',
       '00000000-0000-4000-8000-000000000001', 'gf68-bad-lineage-out-1', repeat('b',64)),
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'MERGE_OUT', 1,
       current_timestamp - interval '1 hour', '68000000-0000-0000-8000-000000000005',
       '00000000-0000-4000-8000-000000000001', 'gf68-bad-lineage-out-2', repeat('c',64)),
      ('10000000-0000-4000-8000-000000000001', %L, %L, 'MERGE_IN', 2,
       current_timestamp - interval '1 hour', '68000000-0000-0000-8000-000000000005',
       '00000000-0000-4000-8000-000000000001', 'gf68-bad-lineage-in-2', repeat('d',64));
    insert into public.livestock_cohort_lineage(
      organization_id, project_id, operation_id, source_cohort_id, destination_cohort_id, quantity
    ) values
      ('10000000-0000-4000-8000-000000000001', %L,
       '68000000-0000-0000-8000-000000000005', %L, %L, 2),
      ('10000000-0000-4000-8000-000000000001', %L,
       '68000000-0000-0000-8000-000000000005', %L, %L, 1);
    EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  END $do$;
$q$, :'gf68_project', :'gf68_asof', :'gf68_backdated', :'gf68_weight_cohort',
     :'gf68_project', :'gf68_asof', :'gf68_backdated', :'gf68_weight_cohort')) like '%MERGE lineage does not match%'
then 1 else 0 end as privileged_merge_lineage_mismatch_rejected;

-- ---------------------------------------------------------------------------
-- Lifecycle, quality and disposal boundaries.
-- ---------------------------------------------------------------------------
-- A zero ACTIVE Cohort remains visible but consuming/measurement commands are
-- not accepted; no implicit CLOSED/LOST state is manufactured.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 50,
    current_timestamp, 'UNKNOWN', null, null, 'PENDING', null,
    'gf68-exhaust-main'
  )$q$, :'gf68_project', :'gf68_asof')) gf68_exhaust_event \gset
select 1/case when (
  select current_quantity = 0 from livestock_cohort_quantity_rollforward
  where cohort_id = :'gf68_asof'
) and (
  select lifecycle_state = 'ACTIVE' from livestock_cohorts_read
  where id = :'gf68_asof'
) then 1 else 0 end as exhausted_cohort_stays_active;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1,
    current_timestamp, 'UNKNOWN', null, null, 'PENDING', null,
    'gf68-exhaust-over'
  )$q$, :'gf68_project', :'gf68_asof')) like '%exceeds the current derived quantity%'
then 1 else 0 end as exhausted_mortality_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1, current_timestamp,
    'تقسيم دفعة مستنفدة', %L, %L, null, null, 'مرفوض', null, null,
    'gf68-exhaust-split'
  )$q$, :'gf68_project', :'gf68_asof', :'gf68_herd_a', :'gf68_site')) like '%exceeds the current derived quantity%'
then 1 else 0 end as exhausted_split_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.merge_livestock_cohorts(
    '10000000-0000-4000-8000-000000000001', %L,
    array[%L,%L]::uuid[], array[1,1]::integer[], current_timestamp,
    'دمج دفعة مستنفدة', %L, %L, null, null, 'مرفوض', null, null,
    'gf68-exhaust-merge'
  )$q$, :'gf68_project', :'gf68_asof', :'gf68_backdated', :'gf68_herd_a', :'gf68_site')) like '%exceeds the current derived quantity%'
then 1 else 0 end as exhausted_merge_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, current_timestamp,
    'COHORT_TOTAL', 220, 'KG', null, null, null, 'UNASSESSED', null,
    'gf68-exhaust-weight'
  )$q$, :'gf68_project', :'gf68_asof')) like '%no positive quantity%'
then 1 else 0 end as exhausted_weight_rejected;
select 1/case when (
  select disposal_method = 'BURIAL' from livestock_quantity_events
  where id = :'gf68_future_mortality'
) and (
  select confidence_level = 'HIGH' from livestock_weight_events
  where id = :'gf68_future_weight'
) then 1 else 0 end as mortality_disposal_and_weight_quality_stored;

select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    disposal_method, recorded_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, 'BIRTH', 1, now(),
    'BURIAL', '00000000-0000-4000-8000-000000000001', 'gf68-birth-disposal', repeat('e',64)
  )
$q$, :'gf68_project', :'gf68_backdated')) like '%must not carry a disposal method%'
then 1 else 0 end as non_mortality_disposal_rejected;

select 'GF-022 review hardening PASS' result;
