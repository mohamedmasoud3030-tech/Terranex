-- GF-022 — births, mortality, split, merge, and the exact as-of quantity rollforward.
--
-- Reuses the tenant-A hierarchy and the gf20_run / gf20_catch / gf20_count /
-- gf20_owner_catch harness created by the GF-020 and GF-021 suites.

-- Site/Herd references are unique per project, not globally: tenant B uses the
-- same human-readable references, so every lookup is project-scoped.
select id gf22_project from investment_projects where internal_reference = 'GF020-LS-A' \gset
select id gf22_site_a from livestock_sites
 where internal_reference = 'SITE-A' and project_id = :'gf22_project' \gset
select id gf22_site_b from livestock_sites
 where internal_reference = 'SITE-B' and project_id = :'gf22_project' \gset
select id gf22_herd_a from livestock_herds
 where internal_reference = 'HERD-A' and project_id = :'gf22_project' \gset
select id gf22_herd_b from livestock_herds
 where internal_reference = 'HERD-B' and project_id = :'gf22_project' \gset

-- ---------------------------------------------------------------------------
-- GF-022.A — the six real classes are registered, with correct signs.
-- ---------------------------------------------------------------------------
select 1/case when (
  select count(*) = 6 from livestock_quantity_event_types
  where code in ('BIRTH','MORTALITY','SPLIT_OUT','SPLIT_IN','MERGE_OUT','MERGE_IN')
) then 1 else 0 end as six_classes_registered;
select 1/case when (
  select bool_and(
    case code
      when 'BIRTH' then direction = 1
      when 'MORTALITY' then direction = -1
      when 'SPLIT_OUT' then direction = -1
      when 'SPLIT_IN' then direction = 1
      when 'MERGE_OUT' then direction = -1
      when 'MERGE_IN' then direction = 1
    end)
  from livestock_quantity_event_types
) then 1 else 0 end as class_directions_correct;

-- Sale/removal is explicitly NOT introduced in this slice.
select 1/case when not exists (
  select 1 from livestock_quantity_event_types
  where code in ('SALE','SOLD','REMOVAL','CULL','TRANSFER_OUT')
) then 1 else 0 end as no_sale_class_in_gf022;

-- ---------------------------------------------------------------------------
-- Fixture: an ACTIVE Cohort of 100 head.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة الأحداث الحيوية', 'PURCHASED', date '2026-08-01', 100, 'MIXED', null,
    null, null, null, null, null, 'gf22-cohort-main'
  )$q$, :'gf22_project', :'gf22_herd_a', :'gf22_site_a')) gf22_main \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل دفعة الأحداث', null, 'gf22-activate-main'
  )$q$, :'gf22_project', :'gf22_main')) gf22_main_active \gset

select (select count(*) from journal_batches) gf22_jb_before,
       (select count(*) from journal_lines) gf22_jl_before,
       (select count(*) from project_payments) gf22_pay_before \gset

-- ---------------------------------------------------------------------------
-- GF-022.B — Birth.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 12,
    timestamptz '2026-08-01 06:00+00', 'سجل ولادات', null, 'gf22-birth-1'
  )$q$, :'gf22_project', :'gf22_main')) gf22_birth \gset
select 1/case when (
  select opening_headcount = 100 and births = 12 and current_quantity = 112
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) then 1 else 0 end as birth_increases_derived_quantity;

-- The opening quantity is never mutated by an event.
select 1/case when (
  select opening_headcount = 100 from livestock_cohorts where id = :'gf22_main'
) then 1 else 0 end as birth_does_not_mutate_opening;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 0, now(), null, null,
    'gf22-birth-zero'
  )$q$, :'gf22_project', :'gf22_main')) like '%invalid livestock quantity%'
then 1 else 0 end as zero_birth_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, -3, now(), null, null,
    'gf22-birth-negative'
  )$q$, :'gf22_project', :'gf22_main')) like '%invalid livestock quantity%'
then 1 else 0 end as negative_birth_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000002', format($q$
  select public.record_livestock_birth(
    '20000000-0000-4000-8000-000000000002', %L, %L, 5, now(), null, null,
    'gf22-birth-tenant-b'
  )$q$, :'gf22_project', :'gf22_main')) <> 'NO_EXCEPTION'
then 1 else 0 end as cross_tenant_birth_rejected;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 12,
    timestamptz '2026-08-01 06:00+00', 'سجل ولادات', null, 'gf22-birth-1'
  )$q$, :'gf22_project', :'gf22_main')) = :'gf22_birth'
then 1 else 0 end as birth_replay_is_idempotent;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 99,
    timestamptz '2026-08-01 06:00+00', 'سجل ولادات', null, 'gf22-birth-1'
  )$q$, :'gf22_project', :'gf22_main')) like '%idempotency key payload mismatch%'
then 1 else 0 end as birth_payload_mismatch_rejected;
select 1/case when (
  select current_quantity = 112
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) and (
  select count(*) = 1 from audit_events
  where entity_id = :'gf22_main' and event_type = 'LIVESTOCK_BIRTH_RECORDED'
) then 1 else 0 end as birth_replay_no_duplicate;

-- ---------------------------------------------------------------------------
-- GF-022.C — Mortality.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 7,
    timestamptz '2026-08-02 06:00+00', 'DISEASE', 'التهاب رئوي',
    'تقرير بيطري', null, 'gf22-mortality-1'
  )$q$, :'gf22_project', :'gf22_main')) gf22_mortality \gset
select 1/case when (
  select mortality = 7 and current_quantity = 105
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) then 1 else 0 end as mortality_decreases_derived_quantity;

-- Mortality requires a cause; other classes must not carry one.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1, now(), 'SPONTANEOUS',
    null, null, null, 'gf22-mortality-cause'
  )$q$, :'gf22_project', :'gf22_main')) like '%invalid livestock mortality cause%'
then 1 else 0 end as invalid_mortality_cause_rejected;

-- Cannot exceed the current derived quantity, and can never go negative.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 106, now(), 'UNKNOWN',
    null, null, null, 'gf22-mortality-over'
  )$q$, :'gf22_project', :'gf22_main')) like '%exceeds the current derived quantity%'
then 1 else 0 end as mortality_cannot_exceed_current;
select 1/case when (
  select current_quantity = 105
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) then 1 else 0 end as failed_mortality_left_balance_intact;

select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 7,
    timestamptz '2026-08-02 06:00+00', 'DISEASE', 'التهاب رئوي',
    'تقرير بيطري', null, 'gf22-mortality-1'
  )$q$, :'gf22_project', :'gf22_main')) = :'gf22_mortality'
then 1 else 0 end as mortality_replay_is_idempotent;

-- Even a privileged path cannot drive the derived balance negative. The guard
-- is a DEFERRED constraint trigger so the atomic commands can write both legs
-- of an operation before it checks; making it IMMEDIATE here lets the same
-- rejection be observed inside the catch helper instead of at commit.
begin;
set constraints livestock_quantity_never_negative immediate;
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    cause_category, recorded_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, 'MORTALITY', 100000, now(),
    'UNKNOWN', '00000000-0000-4000-8000-000000000001', 'gf22-forced-negative',
    repeat('a',64)
  )
$q$, :'gf22_project', :'gf22_main')) like '%cannot go below zero%'
then 1 else 0 end as privileged_negative_balance_rejected;
rollback;

-- A quantity class that requires an operation cannot exist as a lone row.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    recorded_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, 'SPLIT_OUT', 5, now(),
    '00000000-0000-4000-8000-000000000001', 'gf22-orphan-split', repeat('b',64)
  )
$q$, :'gf22_project', :'gf22_main')) like '%requires an operation identity%'
then 1 else 0 end as orphan_split_leg_rejected;

-- A BIRTH may not smuggle in an operation identity or a cause.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    cause_category, recorded_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, 'BIRTH', 5, now(),
    'DISEASE', '00000000-0000-4000-8000-000000000001', 'gf22-birth-cause',
    repeat('c',64)
  )
$q$, :'gf22_project', :'gf22_main')) like '%must not carry a cause category%'
then 1 else 0 end as birth_with_cause_rejected;

-- ---------------------------------------------------------------------------
-- GF-022.D — Split: exact conservation through one operation identity.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 30,
    timestamptz '2026-08-03 06:00+00', 'دفعة التقسيم أ', %L, %L,
    'MIXED', null, 'فصل مجموعة التسمين', 'محضر تقسيم', null, 'gf22-split-1'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_herd_b', :'gf22_site_b'))
  gf22_split \gset

select id gf22_split_dest from livestock_cohorts
 where cohort_reference = 'دفعة التقسيم أ' and project_id = :'gf22_project' \gset

-- 105 − 30 = 75 at the source; exactly 30 at the destination.
select 1/case when (
  select split_out = 30 and current_quantity = 75
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) then 1 else 0 end as split_decreases_source;
select 1/case when (
  select opening_headcount = 0 and split_in = 30 and current_quantity = 30
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_split_dest'
) then 1 else 0 end as split_destination_exact;

-- The source's opening headcount is NOT rewritten.
select 1/case when (
  select opening_headcount = 100 from livestock_cohorts where id = :'gf22_main'
) then 1 else 0 end as split_does_not_rewrite_source_opening;

-- Conservation: out equals in, under one shared operation identity.
select 1/case when (
  select sum(case when t.direction = -1 then q.quantity else 0 end)
       = sum(case when t.direction = 1 then q.quantity else 0 end)
     and count(*) = 2
  from livestock_quantity_events q
  join livestock_quantity_event_types t on t.code = q.event_type
  where q.operation_id = :'gf22_split'
) then 1 else 0 end as split_conserves_quantity_exactly;

-- Both legs share ONE operation identity: never two unrelated rows.
select 1/case when (
  select count(distinct operation_id) = 1 and count(*) = 2
  from livestock_quantity_events where operation_id = :'gf22_split'
) then 1 else 0 end as split_has_single_operation_identity;

-- Explicit lineage links source and destination.
select 1/case when (
  select count(*) = 1 from livestock_cohort_lineage
  where operation_id = :'gf22_split'
    and source_cohort_id = :'gf22_main'
    and destination_cohort_id = :'gf22_split_dest'
    and quantity = 30
) then 1 else 0 end as split_lineage_exact;

-- The destination Cohort has coherent, explicitly chosen context.
select 1/case when (
  select c.origin_type = 'SPLIT_FROM_COHORT' and c.herd_id = :'gf22_herd_b'
     and public.livestock_current_cohort_state(c.id) = 'ACTIVE'
  from livestock_cohorts c where c.id = :'gf22_split_dest'
) and (
  select site_id = :'gf22_site_b'
  from livestock_cohort_initial_placements where cohort_id = :'gf22_split_dest'
) and (
  select placement_source = 'OPENING' and current_site_id = :'gf22_site_b'
  from livestock_cohort_current_placement where cohort_id = :'gf22_split_dest'
) then 1 else 0 end as split_destination_context_coherent;

-- Oversplit is refused.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 76, now(),
    'دفعة تقسيم زائدة', %L, %L, null, null, 'تقسيم زائد', null, null,
    'gf22-split-over'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_herd_b', :'gf22_site_b'))
  like '%exceeds the current derived quantity%'
then 1 else 0 end as oversplit_rejected;

-- A cross-project destination Herd/Site is refused.
select id gf22_project_2 from investment_projects where internal_reference = 'GF021-LS-A2' \gset
select id gf22_herd_p2 from livestock_herds
 where internal_reference = 'HERD-P2' and project_id = :'gf22_project_2' \gset
select id gf22_site_p2 from livestock_sites
 where internal_reference = 'SITE-P2' and project_id = :'gf22_project_2' \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 5, now(),
    'تقسيم عابر للمشروع', %L, %L, null, null, 'مرفوض', null, null,
    'gf22-split-xproject'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_herd_p2', :'gf22_site_p2'))
  like '%livestock herd not found%'
then 1 else 0 end as cross_project_split_rejected;

-- Splitting a PLANNED (not yet operational) Cohort is refused.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة مخططة 022', 'PURCHASED', date '2026-08-01', 10, null, null,
    null, null, null, null, null, 'gf22-planned-cohort'
  )$q$, :'gf22_project', :'gf22_herd_a', :'gf22_site_a')) gf22_planned \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 5, now(),
    'تقسيم دفعة مخططة', %L, %L, null, null, 'مرفوض', null, null,
    'gf22-split-planned'
  )$q$, :'gf22_project', :'gf22_planned', :'gf22_herd_b', :'gf22_site_b'))
  like '%livestock cohort is not active%'
then 1 else 0 end as split_of_planned_cohort_rejected;

-- Idempotent replay creates no second destination Cohort, legs, or audit event.
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 30,
    timestamptz '2026-08-03 06:00+00', 'دفعة التقسيم أ', %L, %L,
    'MIXED', null, 'فصل مجموعة التسمين', 'محضر تقسيم', null, 'gf22-split-1'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_herd_b', :'gf22_site_b'))
  = :'gf22_split'
then 1 else 0 end as split_replay_returns_same_operation;
select 1/case when (
  select count(*) = 1 from livestock_cohorts
  where cohort_reference = 'دفعة التقسيم أ' and project_id = :'gf22_project'
) and (
  select count(*) = 2 from livestock_quantity_events where operation_id = :'gf22_split'
) and (
  select count(*) = 1 from livestock_cohort_lineage where operation_id = :'gf22_split'
) and (
  select count(*) = 1 from audit_events
  where entity_id = :'gf22_split' and event_type = 'LIVESTOCK_COHORT_SPLIT'
) and (
  select current_quantity = 75
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) then 1 else 0 end as split_replay_duplicates_nothing;

-- ---------------------------------------------------------------------------
-- GF-022.E — Merge: exact conservation, species compatibility enforced.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة الدمج ب', 'PURCHASED', date '2026-08-15', 40, 'MIXED', null,
    null, null, null, null, null, 'gf22-cohort-merge-b'
  )$q$, :'gf22_project', :'gf22_herd_a', :'gf22_site_a')) gf22_merge_b \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل دفعة الدمج', null, 'gf22-activate-merge-b'
  )$q$, :'gf22_project', :'gf22_merge_b')) gf22_merge_b_active \gset

select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.merge_livestock_cohorts(
    '10000000-0000-4000-8000-000000000001', %L,
    array[%L,%L]::uuid[], array[25,40]::integer[],
    timestamptz '2026-08-04 06:00+00', 'دفعة الدمج الموحدة', %L, %L,
    'MIXED', null, 'توحيد مجموعتين', 'محضر دمج', null, 'gf22-merge-1'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_merge_b',
       :'gf22_herd_a', :'gf22_site_a')) gf22_merge \gset

select id gf22_merge_dest from livestock_cohorts
 where cohort_reference = 'دفعة الدمج الموحدة' and project_id = :'gf22_project' \gset

-- Sources are consumed exactly; the destination receives exactly the sum.
select 1/case when (
  select merge_out = 25 and current_quantity = 50
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) then 1 else 0 end as merge_consumes_source_a;
select 1/case when (
  select merge_out = 40 and current_quantity = 0
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_merge_b'
) then 1 else 0 end as merge_consumes_source_b;
select 1/case when (
  select opening_headcount = 0 and merge_in = 65 and current_quantity = 65
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_merge_dest'
) then 1 else 0 end as merge_destination_is_exact_sum;

-- Conservation across the whole operation.
select 1/case when (
  select sum(case when t.direction = -1 then q.quantity else 0 end) = 65
     and sum(case when t.direction = 1 then q.quantity else 0 end) = 65
     and count(distinct q.operation_id) = 1
  from livestock_quantity_events q
  join livestock_quantity_event_types t on t.code = q.event_type
  where q.operation_id = :'gf22_merge'
) then 1 else 0 end as merge_conserves_quantity_exactly;
select 1/case when (
  select count(*) = 2 and sum(quantity) = 65
  from livestock_cohort_lineage where operation_id = :'gf22_merge'
) then 1 else 0 end as merge_lineage_exact;

-- GF-022.F — a Cohort at zero truthfully shows zero and its lifecycle is NOT
-- silently mutated. No implicit close is invented.
select 1/case when (
  select current_quantity = 0
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_merge_b'
) and public.livestock_current_cohort_state(:'gf22_merge_b') = 'ACTIVE'
then 1 else 0 end as zero_quantity_does_not_mutate_lifecycle;

-- Cross-species merge is refused.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_herd(
    '10000000-0000-4000-8000-000000000001', %L, 'قطيع الأغنام',
    'HERD-SHEEP', 'SHEEP', 'MEAT', null, 'gf22-herd-sheep'
  )$q$, :'gf22_project')) gf22_herd_sheep \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة أغنام', 'PURCHASED', date '2026-08-20', 20, null, null,
    null, null, null, null, null, 'gf22-cohort-sheep'
  )$q$, :'gf22_project', :'gf22_herd_sheep', :'gf22_site_a')) gf22_sheep \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل دفعة الأغنام', null, 'gf22-activate-sheep'
  )$q$, :'gf22_project', :'gf22_sheep')) gf22_sheep_active \gset

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.merge_livestock_cohorts(
    '10000000-0000-4000-8000-000000000001', %L,
    array[%L,%L]::uuid[], array[5,5]::integer[], now(),
    'دمج غير متوافق', %L, %L, null, null, 'مرفوض', null, null,
    'gf22-merge-species'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_sheep',
       :'gf22_herd_a', :'gf22_site_a')) like '%compatible species%'
then 1 else 0 end as cross_species_merge_rejected;

-- A merge needs at least two distinct sources with matching quantities.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.merge_livestock_cohorts(
    '10000000-0000-4000-8000-000000000001', %L,
    array[%L]::uuid[], array[5]::integer[], now(),
    'دمج مصدر واحد', %L, %L, null, null, 'مرفوض', null, null,
    'gf22-merge-single'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_herd_a', :'gf22_site_a'))
  like '%at least two source cohorts%'
then 1 else 0 end as single_source_merge_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.merge_livestock_cohorts(
    '10000000-0000-4000-8000-000000000001', %L,
    array[%L,%L]::uuid[], array[5]::integer[], now(),
    'دمج غير متسق', %L, %L, null, null, 'مرفوض', null, null,
    'gf22-merge-mismatch'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_merge_b',
       :'gf22_herd_a', :'gf22_site_a')) like '%must match the source cohorts%'
then 1 else 0 end as merge_quantity_arity_mismatch_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.merge_livestock_cohorts(
    '10000000-0000-4000-8000-000000000001', %L,
    array[%L,%L]::uuid[], array[5,5]::integer[], now(),
    'دمج مكرر', %L, %L, null, null, 'مرفوض', null, null,
    'gf22-merge-duplicate'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_main',
       :'gf22_herd_a', :'gf22_site_a')) like '%must be distinct%'
then 1 else 0 end as duplicate_merge_source_rejected;

-- Overdrawing any source refuses the whole atomic merge.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.merge_livestock_cohorts(
    '10000000-0000-4000-8000-000000000001', %L,
    array[%L,%L]::uuid[], array[10,999]::integer[], now(),
    'دمج زائد', %L, %L, null, null, 'مرفوض', null, null,
    'gf22-merge-over'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_sheep',
       :'gf22_herd_a', :'gf22_site_a')) <> 'NO_EXCEPTION'
then 1 else 0 end as merge_overdraw_rejected;
select 1/case when (
  select current_quantity = 50
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) then 1 else 0 end as failed_merge_left_balance_intact;

-- Cross-tenant merge is refused.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000002', format($q$
  select public.merge_livestock_cohorts(
    '20000000-0000-4000-8000-000000000002', %L,
    array[%L,%L]::uuid[], array[1,1]::integer[], now(),
    'دمج عابر للمستأجر', %L, %L, null, null, 'مرفوض', null, null,
    'gf22-merge-tenant-b'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_merge_b',
       :'gf22_herd_a', :'gf22_site_a')) <> 'NO_EXCEPTION'
then 1 else 0 end as cross_tenant_merge_rejected;

-- Idempotent merge replay duplicates neither destination nor lineage.
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.merge_livestock_cohorts(
    '10000000-0000-4000-8000-000000000001', %L,
    array[%L,%L]::uuid[], array[25,40]::integer[],
    timestamptz '2026-08-04 06:00+00', 'دفعة الدمج الموحدة', %L, %L,
    'MIXED', null, 'توحيد مجموعتين', 'محضر دمج', null, 'gf22-merge-1'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_merge_b',
       :'gf22_herd_a', :'gf22_site_a')) = :'gf22_merge'
then 1 else 0 end as merge_replay_returns_same_operation;
select 1/case when (
  select count(*) = 1 from livestock_cohorts
  where cohort_reference = 'دفعة الدمج الموحدة' and project_id = :'gf22_project'
) and (
  select count(*) = 3 from livestock_quantity_events where operation_id = :'gf22_merge'
) and (
  select count(*) = 2 from livestock_cohort_lineage where operation_id = :'gf22_merge'
) and (
  select count(*) = 1 from audit_events
  where entity_id = :'gf22_merge' and event_type = 'LIVESTOCK_COHORTS_MERGED'
) then 1 else 0 end as merge_replay_duplicates_nothing;

-- An unbalanced operation cannot be forged, even by the owner. Same deferred
-- constraint, made immediate so the rejection is observable in the helper.
begin;
set constraints livestock_operation_conserves_quantity immediate;
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_quantity_operations(
    organization_id, project_id, operation_type, effective_at, reason,
    performed_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, 'SPLIT', now(), 'عملية مزورة',
    '00000000-0000-4000-8000-000000000001', 'gf22-forged-op', repeat('d',64)
  )
$q$, :'gf22_project')) like '%requires both an outgoing and an incoming leg%'
then 1 else 0 end as unbalanced_operation_rejected;
rollback;

-- ---------------------------------------------------------------------------
-- GF-022.G — Rollforward arithmetic is exact for every class.
-- ---------------------------------------------------------------------------
-- 100 opening + 12 births − 7 mortality − 30 split_out − 25 merge_out = 50.
select 1/case when (
  select opening_headcount = 100 and births = 12 and mortality = 7
     and split_out = 30 and split_in = 0
     and merge_out = 25 and merge_in = 0
     and current_quantity = 50
     and current_quantity =
       opening_headcount + births + split_in + merge_in
       - mortality - split_out - merge_out
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) then 1 else 0 end as rollforward_arithmetic_exact;

-- The invariant holds for EVERY cohort, and no balance is ever negative.
select 1/case when (
  select bool_and(
    current_quantity =
      opening_headcount + births + split_in + merge_in
      - mortality - split_out - merge_out
    and current_quantity >= 0)
  from livestock_cohort_quantity_rollforward
) then 1 else 0 end as rollforward_invariant_holds_globally;

-- Every event class is reflected exactly once in the rollforward.
select 1/case when (
  select bool_and(r.quantity_increase = e.increase and r.quantity_decrease = e.decrease)
  from livestock_cohort_quantity_rollforward r
  join lateral (
    select
      coalesce(sum(case when t.direction = 1 then q.quantity else 0 end), 0) as increase,
      coalesce(sum(case when t.direction = -1 then q.quantity else 0 end), 0) as decrease
    from livestock_quantity_events q
    join livestock_quantity_event_types t on t.code = q.event_type
    where q.cohort_id = r.cohort_id
  ) e on true
) then 1 else 0 end as every_class_counted_once;

-- Headcount stays exact integer; no floating point on this path.
select 1/case when (
  select bool_and(data_type = 'integer')
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'livestock_cohort_quantity_rollforward'
    and column_name in (
      'opening_headcount','births','mortality','split_in','split_out',
      'merge_in','merge_out','current_quantity'
    )
) then 1 else 0 end as rollforward_is_exact_integer;

-- ---------------------------------------------------------------------------
-- Security and isolation.
-- ---------------------------------------------------------------------------
select 1/case when (
  select count(*) = 5 and bool_and(relrowsecurity and relforcerowsecurity)
  from pg_class where relnamespace = 'public'::regnamespace
    and relname in (
      'livestock_quantity_events', 'livestock_quantity_operations',
      'livestock_cohort_lineage', 'livestock_cohort_movements',
      'livestock_weight_events'
    )
) then 1 else 0 end as gf022_force_rls_preserved;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    recorded_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, 'BIRTH', 5, now(),
    '00000000-0000-4000-8000-000000000001', 'gf22-direct-dml', repeat('e',64)
  )
$q$, :'gf22_project', :'gf22_main')) like '%permission denied%'
then 1 else 0 end as quantity_direct_insert_denied;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  update public.livestock_quantity_events set quantity = 1 where id = %L
$q$, :'gf22_birth')) like '%permission denied%'
then 1 else 0 end as quantity_direct_update_denied;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  delete from public.livestock_cohort_lineage where operation_id = %L
$q$, :'gf22_split')) like '%permission denied%'
then 1 else 0 end as lineage_direct_delete_denied;
select 1/case when gf20_owner_catch(format($q$
  update public.livestock_cohort_lineage set quantity = 1 where operation_id = %L
$q$, :'gf22_split')) like '%append-only%'
then 1 else 0 end as lineage_owner_update_rejected;

-- Actor cannot be spoofed: every event records auth.uid().
select 1/case when (
  select bool_and(recorded_by = '00000000-0000-4000-8000-000000000001')
  from livestock_quantity_events
) and (
  select bool_and(performed_by = '00000000-0000-4000-8000-000000000001')
  from livestock_quantity_operations
) then 1 else 0 end as gf022_actor_server_authoritative;

-- Sector guard: no Livestock quantity row can attach to another sector.
select id gf22_re_project from investment_projects where sector = 'REAL_ESTATE' order by id limit 1 \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 5, now(), null, null,
    'gf22-birth-sector'
  )$q$, :'gf22_re_project', :'gf22_main')) like '%livestock project not found%'
then 1 else 0 end as gf022_sector_guard;

-- Tenant B sees none of tenant A's quantity truth.
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002',
  format('select count(*) from public.livestock_quantity_events_read where project_id = %L',
         :'gf22_project')) = 0 then 1 else 0 end as quantity_rls_isolated;
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002',
  format('select count(*) from public.livestock_cohort_lineage_read where project_id = %L',
         :'gf22_project')) = 0 then 1 else 0 end as lineage_rls_isolated;

-- Finance isolation: births, deaths, splits and merges post nothing.
select 1/case when (select count(*) from journal_batches) = :'gf22_jb_before'
  and (select count(*) from journal_lines) = :'gf22_jl_before'
  and (select count(*) from project_payments) = :'gf22_pay_before'
then 1 else 0 end as gf022_produced_no_finance_artifact;

-- Still no mutable authoritative derived state on any base table.
select 1/case when not exists (
  select 1 from information_schema.columns c
  join information_schema.tables t
    on t.table_schema = c.table_schema and t.table_name = c.table_name
  where c.table_schema = 'public' and c.table_name like 'livestock%'
    and t.table_type = 'BASE TABLE'
    and c.column_name in (
      'current_site_id', 'current_herd_id', 'current_headcount',
      'current_weight', 'available_animals', 'mortality_total', 'births_total'
    )
) then 1 else 0 end as gf022_no_mutable_derived_state;

select 'GF-022 biological quantity events, split and merge PASS' result;
