-- GF-021/GF-022 reviewer regressions: temporal truth, species continuity,
-- ACTIVE/zero guards, operation business time, and exact-shape surface.

select id gf22h_project from investment_projects where internal_reference='GF020-LS-A' \gset
select id gf22h_site_a from livestock_sites where internal_reference='SITE-A' and project_id=:'gf22h_project' \gset
select id gf22h_site_b from livestock_sites where internal_reference='SITE-B' and project_id=:'gf22h_project' \gset
select id gf22h_herd_a from livestock_herds where internal_reference='HERD-A' and project_id=:'gf22h_project' \gset

select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_herd(
    '10000000-0000-4000-8000-000000000001', %L,
    'قطيع أغنام مراجعة 022','HERD-SHEEP-HARD','SHEEP','MEAT',null,'gf22h-herd-sheep'
  )$q$, :'gf22h_project')) gf22h_sheep_herd \gset

-- ---------------------------------------------------------------------------
-- Temporal truth: quantity/movement actual facts are never future facts, and
-- an outflow is checked at its own effective time rather than against all-time.
-- WeightEvent is a dated log only in GF-021; it derives no current-weight state.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001',%L,%L,%L,
    'دفعة مراجعة الزمن 022','PURCHASED',current_date-1,10,'MIXED',null,
    null,null,null,null,null,'gf22h-time-cohort'
  )$q$, :'gf22h_project', :'gf22h_herd_a', :'gf22h_site_a')) gf22h_time \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001',%L,%L,'PLANNED','ACTIVE',
    'تفعيل اختبار الزمن',null,'gf22h-time-active'
  )$q$, :'gf22h_project', :'gf22h_time')) gf22h_time_active \gset

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001',%L,%L,3,
    now()+interval '1 day',null,null,'gf22h-future-birth'
  )$q$, :'gf22h_project', :'gf22h_time')) like '%future livestock actual event is not allowed%'
then 1 else 0 end as future_quantity_actual_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001',%L,%L,1,
    (current_date-2)::timestamptz,null,null,'gf22h-before-opening'
  )$q$, :'gf22h_project', :'gf22h_time')) like '%precedes cohort opening%'
then 1 else 0 end as event_before_opening_rejected;

select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001',%L,%L,10,
    now()-interval '1 minute',null,null,'gf22h-later-inflow'
  )$q$, :'gf22h_project', :'gf22h_time')) gf22h_birth \gset
select 1/case when public.livestock_current_cohort_quantity(:'gf22h_time')=20
then 1 else 0 end as current_quantity_includes_effective_inflow;
select 1/case when public.livestock_cohort_quantity_as_of(
  :'gf22h_time', now()-interval '2 minutes')=10
then 1 else 0 end as asof_resolver_excludes_later_inflow;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001',%L,%L,15,
    now()-interval '2 minutes','UNKNOWN',null,null,null,'gf22h-backdated-outflow'
  )$q$, :'gf22h_project', :'gf22h_time')) like '%exceeds quantity as of effective time%'
then 1 else 0 end as backdated_outflow_cannot_borrow_later_inflow;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,%L,%L,
    now()+interval '1 hour','حركة مستقبلية مرفوضة',null,null,'gf22h-future-move'
  )$q$, :'gf22h_project', :'gf22h_time', :'gf22h_site_a', :'gf22h_herd_a',
       :'gf22h_site_b', :'gf22h_herd_a')) like '%future livestock actual event is not allowed%'
then 1 else 0 end as future_movement_rejected;

-- ---------------------------------------------------------------------------
-- Species continuity: command paths and privileged identity rewrites.
-- ---------------------------------------------------------------------------
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,%L,%L,
    now(),'محاولة تغيير النوع',null,null,'gf22h-move-species'
  )$q$, :'gf22h_project', :'gf22h_time', :'gf22h_site_a', :'gf22h_herd_a',
       :'gf22h_site_a', :'gf22h_sheep_herd')) like '%must preserve cohort species%'
then 1 else 0 end as movement_cross_species_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001',%L,%L,1,now(),
    'ناتج تقسيم نوع خاطئ',%L,%L,null,null,'اختبار النوع',null,null,'gf22h-split-species'
  )$q$, :'gf22h_project', :'gf22h_time', :'gf22h_sheep_herd', :'gf22h_site_a'))
  like '%must preserve species%'
then 1 else 0 end as split_cross_species_rejected;
select 1/case when gf20_owner_catch(format(
  'update public.livestock_herds set species=''GOAT'' where id=%L', :'gf22h_herd_a'
)) like '%species is immutable after cohort use%'
then 1 else 0 end as privileged_species_rewrite_rejected;

-- ---------------------------------------------------------------------------
-- Zero quantity is truthful ACTIVE state, but not an operational population.
-- Birth remains additive and may restore it.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001',%L,%L,%L,
    'دفعة صفر مراجعة 022','PURCHASED',current_date-1,5,null,null,
    null,null,null,null,null,'gf22h-zero-cohort'
  )$q$, :'gf22h_project', :'gf22h_herd_a', :'gf22h_site_a')) gf22h_zero \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001',%L,%L,'PLANNED','ACTIVE',
    'تفعيل دفعة الصفر',null,'gf22h-zero-active'
  )$q$, :'gf22h_project', :'gf22h_zero')) gf22h_zero_active \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001',%L,%L,5,now(),'UNKNOWN',
    null,null,null,'gf22h-zero-consume'
  )$q$, :'gf22h_project', :'gf22h_zero')) gf22h_zero_event \gset
select 1/case when public.livestock_current_cohort_quantity(:'gf22h_zero')=0
  and public.livestock_current_cohort_state(:'gf22h_zero')='ACTIVE'
then 1 else 0 end as zero_remains_truthful_active_state;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001',%L,%L,now(),'COHORT_TOTAL',1,'KG',
    null,null,null,null,'gf22h-zero-weight'
  )$q$, :'gf22h_project', :'gf22h_zero')) like '%zero quantity for this operation%'
then 1 else 0 end as zero_weight_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,%L,%L,
    now(),'حركة دفعة صفر',null,null,'gf22h-zero-move'
  )$q$, :'gf22h_project', :'gf22h_zero', :'gf22h_site_a', :'gf22h_herd_a',
       :'gf22h_site_b', :'gf22h_herd_a')) like '%zero quantity for this operation%'
then 1 else 0 end as zero_movement_rejected;
select 1/case when (
  gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
    select public.record_livestock_mortality(
      '10000000-0000-4000-8000-000000000001',%L,%L,1,now(),'UNKNOWN',null,null,null,
      'gf22h-zero-mortality'
    )$q$, :'gf22h_project', :'gf22h_zero')) like '%zero quantity for this operation%'
  or gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
    select public.record_livestock_mortality(
      '10000000-0000-4000-8000-000000000001',%L,%L,1,now(),'UNKNOWN',null,null,null,
      'gf22h-zero-mortality-2'
    )$q$, :'gf22h_project', :'gf22h_zero')) like '%exceeds the current derived quantity%'
) then 1 else 0 end as zero_mortality_rejected;
select 1/case when (
  gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
    select public.split_livestock_cohort(
      '10000000-0000-4000-8000-000000000001',%L,%L,1,now(),
      'تقسيم دفعة صفر أ',%L,%L,null,null,'اختبار الصفر',null,null,'gf22h-zero-split-a'
    )$q$, :'gf22h_project', :'gf22h_zero', :'gf22h_herd_a', :'gf22h_site_a')) like '%zero quantity for this operation%'
  or gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
    select public.split_livestock_cohort(
      '10000000-0000-4000-8000-000000000001',%L,%L,1,now(),
      'تقسيم دفعة صفر ب',%L,%L,null,null,'اختبار الصفر',null,null,'gf22h-zero-split-b'
    )$q$, :'gf22h_project', :'gf22h_zero', :'gf22h_herd_a', :'gf22h_site_a')) like '%exceeds the current derived quantity%'
) then 1 else 0 end as zero_split_source_rejected;
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001',%L,%L,2,now(),null,null,'gf22h-zero-birth'
  )$q$, :'gf22h_project', :'gf22h_zero')) gf22h_zero_birth \gset
select 1/case when public.livestock_current_cohort_quantity(:'gf22h_zero')=2
then 1 else 0 end as birth_can_restore_zero_active_cohort;

-- Privileged/import paths cannot place operational quantity facts on PLANNED.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001',%L,%L,%L,
    'دفعة مخططة مراجعة 022','PURCHASED',current_date-1,3,null,null,
    null,null,null,null,null,'gf22h-planned'
  )$q$, :'gf22h_project', :'gf22h_herd_a', :'gf22h_site_a')) gf22h_planned \gset
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_quantity_events(
    organization_id,project_id,cohort_id,event_type,quantity,effective_at,
    recorded_by,idempotency_key,request_hash
  ) values ('10000000-0000-4000-8000-000000000001',%L,%L,'BIRTH',1,now(),
    '00000000-0000-4000-8000-000000000001','gf22h-owner-planned',repeat('a',64))
$q$, :'gf22h_project', :'gf22h_planned')) like '%livestock cohort is not active%'
then 1 else 0 end as privileged_quantity_requires_active;

-- Derived placement starts at the operation business time, not row-write time.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001',%L,%L,1,
    now()-interval '10 seconds','ناتج توقيت مراجعة 022',%L,%L,
    null,null,'اختبار وقت الوضع',null,null,'gf22h-placement-time'
  )$q$, :'gf22h_project', :'gf22h_time', :'gf22h_herd_a', :'gf22h_site_b')) gf22h_split \gset
select id gf22h_split_dest from livestock_cohorts
 where project_id=:'gf22h_project' and cohort_reference='ناتج توقيت مراجعة 022' \gset
select 1/case when (
  select p.placed_at=o.effective_at
  from livestock_cohort_initial_placements p
  join livestock_cohort_lineage l on l.destination_cohort_id=p.cohort_id
  join livestock_quantity_operations o on o.id=l.operation_id
  where p.cohort_id=:'gf22h_split_dest'
) then 1 else 0 end as derived_placement_uses_operation_time;

-- Exact operation shape is enforced by three deferred constraint triggers;
-- real COMMIT rejection for malformed SPLIT/MERGE is exercised in 69.
select 1/case when (
  select count(*)=3 and bool_and(tgdeferrable and tginitdeferred)
  from pg_trigger
  where tgname in ('livestock_operation_shape_exact','livestock_operation_leg_shape_exact','livestock_operation_lineage_shape_exact')
) then 1 else 0 end as exact_shape_triggers_are_deferred;
select 1/case when not exists (
  select 1 from livestock_quantity_operations o
  where not exists (select 1 from livestock_cohort_lineage l where l.operation_id=o.id)
) then 1 else 0 end as every_committed_operation_has_lineage;

select 'GF-022 review hardening SQL regressions PASS' result;