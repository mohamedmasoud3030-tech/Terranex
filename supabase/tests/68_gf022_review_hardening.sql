-- GF-021/GF-022 reviewer regressions: temporal truth, species continuity,
-- ACTIVE/zero guards, operation business time, and exact-shape surface.

select id gf22h_project from investment_projects
 where internal_reference = 'GF020-LS-A' \gset
select id gf22h_site_a from livestock_sites
 where internal_reference = 'SITE-A' and project_id = :'gf22h_project' \gset
select id gf22h_site_b from livestock_sites
 where internal_reference = 'SITE-B' and project_id = :'gf22h_project' \gset
select id gf22h_herd_a from livestock_herds
 where internal_reference = 'HERD-A' and project_id = :'gf22h_project' \gset

-- Dedicated incompatible Herd so this suite does not depend on GF-022's other
-- fixture names.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_herd(
    '10000000-0000-4000-8000-000000000001', %L,
    'قطيع أغنام مراجعة 022', 'HERD-SHEEP-HARD', 'SHEEP', 'MEAT', null,
    'gf22h-herd-sheep'
  )$q$, :'gf22h_project')) gf22h_sheep_herd \gset

-- ---------------------------------------------------------------------------
-- Temporal truth: current means as-of-now and availability means as-of-event.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة مراجعة الزمن 022', 'PURCHASED', current_date - 1, 10, 'MIXED', null,
    null, null, null, null, null, 'gf22h-time-cohort'
  )$q$, :'gf22h_project', :'gf22h_herd_a', :'gf22h_site_a')) gf22h_time \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل اختبار الزمن', null, 'gf22h-time-active'
  )$q$, :'gf22h_project', :'gf22h_time')) gf22h_time_active \gset

-- Confirmed facts are not a scheduling mechanism. A future fact is refused.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 3,
    now() + interval '1 day', null, null, 'gf22h-future-birth'
  )$q$, :'gf22h_project', :'gf22h_time')) like '%future livestock actual event is not allowed%'
then 1 else 0 end as future_actual_fact_rejected;

-- Nor may an event predate the Cohort's business opening boundary.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1,
    (current_date - 2)::timestamptz, null, null, 'gf22h-before-opening'
  )$q$, :'gf22h_project', :'gf22h_time')) like '%precedes cohort opening%'
then 1 else 0 end as event_before_opening_rejected;

-- A later inflow exists, but a backdated outflow may not borrow it.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 10,
    now() - interval '1 minute', null, null, 'gf22h-later-inflow'
  )$q$, :'gf22h_project', :'gf22h_time')) gf22h_birth \gset
select 1/case when (
  select current_quantity = 20 from livestock_cohort_quantity_rollforward
   where cohort_id = :'gf22h_time'
) then 1 else 0 end as current_includes_only_effective_facts;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 15,
    now() - interval '2 minutes', 'UNKNOWN', null, null, null,
    'gf22h-backdated-outflow'
  )$q$, :'gf22h_project', :'gf22h_time')) like '%exceeds quantity as of effective time%'
then 1 else 0 end as backdated_outflow_cannot_borrow_later_inflow;
select 1/case when public.livestock_cohort_quantity_as_of(
  :'gf22h_time', now() - interval '2 minutes'
) = 10 then 1 else 0 end as asof_resolver_excludes_later_inflow;

-- Future movement/weight paths are covered by the same DB guard, not UI trust.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    now() + interval '1 hour', 'حركة مستقبلية مرفوضة', null, null,
    'gf22h-future-move'
  )$q$, :'gf22h_project', :'gf22h_time', :'gf22h_site_a', :'gf22h_herd_a',
       :'gf22h_site_b', :'gf22h_herd_a')) like '%future livestock actual event is not allowed%'
then 1 else 0 end as future_movement_rejected;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    now() + interval '1 hour', 'COHORT_TOTAL', 4000, 'KG', null, null,
    null, null, 'gf22h-future-weight'
  )$q$, :'gf22h_project', :'gf22h_time')) like '%future livestock actual event is not allowed%'
then 1 else 0 end as future_weight_rejected;

-- ---------------------------------------------------------------------------
-- Species continuity is a database invariant for command and owner paths.
-- ---------------------------------------------------------------------------
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    now(), 'محاولة تغيير النوع', null, null, 'gf22h-move-species'
  )$q$, :'gf22h_project', :'gf22h_time', :'gf22h_site_a', :'gf22h_herd_a',
       :'gf22h_site_a', :'gf22h_sheep_herd')) like '%must preserve cohort species%'
then 1 else 0 end as movement_cross_species_rejected;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1, now(),
    'ناتج تقسيم نوع خاطئ', %L, %L, null, null, 'اختبار النوع', null, null,
    'gf22h-split-species'
  )$q$, :'gf22h_project', :'gf22h_time', :'gf22h_sheep_herd', :'gf22h_site_a'))
  like '%must preserve species%'
then 1 else 0 end as split_cross_species_rejected;

select 1/case when gf20_owner_catch(format($q$
  update public.livestock_herds set species = 'GOAT' where id = %L
$q$, :'gf22h_herd_a')) like '%species is immutable after cohort use%'
then 1 else 0 end as privileged_herd_species_rewrite_rejected;

-- ---------------------------------------------------------------------------
-- ACTIVE and zero-quantity boundary is enforced on inserted facts.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة صفر مراجعة 022', 'PURCHASED', current_date - 1, 5, null, null,
    null, null, null, null, null, 'gf22h-zero-cohort'
  )$q$, :'gf22h_project', :'gf22h_herd_a', :'gf22h_site_a')) gf22h_zero \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل دفعة الصفر', null, 'gf22h-zero-active'
  )$q$, :'gf22h_project', :'gf22h_zero')) gf22h_zero_active \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 5, now(), 'UNKNOWN',
    null, null, null, 'gf22h-zero-consume'
  )$q$, :'gf22h_project', :'gf22h_zero')) gf22h_zero_event \gset
select 1/case when (
  select current_quantity = 0 from livestock_cohort_quantity_rollforward
   where cohort_id = :'gf22h_zero'
) and public.livestock_current_cohort_state(:'gf22h_zero') = 'ACTIVE'
then 1 else 0 end as zero_remains_truthful_active_state;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(),
    'COHORT_TOTAL', 1, 'KG', null, null, null, null, 'gf22h-zero-weight'
  )$q$, :'gf22h_project', :'gf22h_zero')) like '%zero quantity for this operation%'
then 1 else 0 end as zero_weight_rejected;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    now(), 'حركة دفعة صفر', null, null, 'gf22h-zero-move'
  )$q$, :'gf22h_project', :'gf22h_zero', :'gf22h_site_a', :'gf22h_herd_a',
       :'gf22h_site_b', :'gf22h_herd_a')) like '%zero quantity for this operation%'
then 1 else 0 end as zero_movement_rejected;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1, now(), 'UNKNOWN',
    null, null, null, 'gf22h-zero-mortality'
  )$q$, :'gf22h_project', :'gf22h_zero')) like '%zero quantity for this operation%'
then 1 else 0 end as zero_mortality_rejected;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1, now(),
    'تقسيم دفعة صفر', %L, %L, null, null, 'اختبار الصفر', null, null,
    'gf22h-zero-split'
  )$q$, :'gf22h_project', :'gf22h_zero', :'gf22h_herd_a', :'gf22h_site_a'))
  like '%zero quantity for this operation%'
then 1 else 0 end as zero_split_source_rejected;

-- Birth is additive and is deliberately the only GF-022 quantity command that
-- can restore a zero ACTIVE Cohort without consuming a population.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 2, now(), null, null,
    'gf22h-zero-birth'
  )$q$, :'gf22h_project', :'gf22h_zero')) gf22h_zero_birth \gset
select 1/case when (
  select current_quantity = 2 from livestock_cohort_quantity_rollforward
   where cohort_id = :'gf22h_zero'
) then 1 else 0 end as birth_can_restore_zero_active_cohort;

-- Privileged/import paths cannot place an operational fact on PLANNED.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة مخططة مراجعة 022', 'PURCHASED', current_date - 1, 3, null, null,
    null, null, null, null, null, 'gf22h-planned'
  )$q$, :'gf22h_project', :'gf22h_herd_a', :'gf22h_site_a')) gf22h_planned \gset
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    recorded_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, 'BIRTH', 1, now(),
    '00000000-0000-4000-8000-000000000001', 'gf22h-owner-planned', repeat('a',64)
  )
$q$, :'gf22h_project', :'gf22h_planned')) like '%livestock cohort is not active%'
then 1 else 0 end as privileged_quantity_requires_active;

-- ---------------------------------------------------------------------------
-- Derived placement is effective at the operation business time.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1,
    now() - interval '10 seconds', 'ناتج توقيت مراجعة 022', %L, %L,
    null, null, 'اختبار وقت الوضع', null, null, 'gf22h-placement-time'
  )$q$, :'gf22h_project', :'gf22h_time', :'gf22h_herd_a', :'gf22h_site_b'))
  gf22h_split \gset
select id gf22h_split_dest from livestock_cohorts
 where project_id = :'gf22h_project' and cohort_reference = 'ناتج توقيت مراجعة 022' \gset
select 1/case when (
  select p.placed_at = o.effective_at
  from livestock_cohort_initial_placements p
  join livestock_cohort_lineage l on l.destination_cohort_id = p.cohort_id
  join livestock_quantity_operations o on o.id = l.operation_id
  where p.cohort_id = :'gf22h_split_dest'
) then 1 else 0 end as derived_opening_placement_uses_operation_time;

-- Exact-shape enforcement is genuinely deferred and attached to operation,
-- leg and lineage writes. Multi-session/COMMIT rejection is covered in 69.
select 1/case when (
  select count(*) = 3 and bool_and(c.condeferrable and c.condeferred)
  from pg_constraint c
  where c.conname in (
    'livestock_operation_shape_exact',
    'livestock_operation_leg_shape_exact',
    'livestock_operation_lineage_shape_exact'
  )
) then 1 else 0 end as exact_operation_shape_constraints_are_deferred;
select 1/case when not exists (
  select 1 from livestock_quantity_operations o
  where not exists (
    select 1 from livestock_cohort_lineage l where l.operation_id = o.id
  )
) then 1 else 0 end as every_committed_operation_has_lineage;

select 'GF-022 review hardening SQL regressions PASS' result;