-- GF-022 — births, mortality, split, merge, and exact quantity rollforward.
-- Uses fixed historical business times so this suite remains deterministic
-- under the GF-022 future-actual-fact guard.

select id gf22_project from investment_projects where internal_reference = 'GF020-LS-A' \gset
select id gf22_site_a from livestock_sites
 where internal_reference = 'SITE-A' and project_id = :'gf22_project' \gset
select id gf22_site_b from livestock_sites
 where internal_reference = 'SITE-B' and project_id = :'gf22_project' \gset
select id gf22_herd_a from livestock_herds
 where internal_reference = 'HERD-A' and project_id = :'gf22_project' \gset
select id gf22_herd_b from livestock_herds
 where internal_reference = 'HERD-B' and project_id = :'gf22_project' \gset

-- Six quantity classes, and deliberately no sale/removal class yet.
select 1/case when (
  select count(*) = 6 from livestock_quantity_event_types
  where code in ('BIRTH','MORTALITY','SPLIT_OUT','SPLIT_IN','MERGE_OUT','MERGE_IN')
) then 1 else 0 end as six_classes_registered;
select 1/case when (
  select bool_and(case code
    when 'BIRTH' then direction = 1
    when 'MORTALITY' then direction = -1
    when 'SPLIT_OUT' then direction = -1
    when 'SPLIT_IN' then direction = 1
    when 'MERGE_OUT' then direction = -1
    when 'MERGE_IN' then direction = 1
  end) from livestock_quantity_event_types
) then 1 else 0 end as class_directions_correct;
select 1/case when not exists (
  select 1 from livestock_quantity_event_types
  where code in ('SALE','SOLD','REMOVAL','CULL','TRANSFER_OUT')
) then 1 else 0 end as no_sale_class_in_gf022;

-- Main ACTIVE Cohort: opening 100.
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

-- Birth: 100 + 12 = 112.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 12,
    timestamptz '2026-08-06 06:00+00', 'سجل ولادات', null, 'gf22-birth-1'
  )$q$, :'gf22_project', :'gf22_main')) gf22_birth \gset
select 1/case when (
  select opening_headcount = 100 and births = 12 and current_quantity = 112
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) then 1 else 0 end as birth_increases_derived_quantity;
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
    timestamptz '2026-08-06 06:00+00', 'سجل ولادات', null, 'gf22-birth-1'
  )$q$, :'gf22_project', :'gf22_main')) = :'gf22_birth'
then 1 else 0 end as birth_replay_is_idempotent;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_birth(
    '10000000-0000-4000-8000-000000000001', %L, %L, 99,
    timestamptz '2026-08-06 06:00+00', 'سجل ولادات', null, 'gf22-birth-1'
  )$q$, :'gf22_project', :'gf22_main')) like '%idempotency key payload mismatch%'
then 1 else 0 end as birth_payload_mismatch_rejected;

-- Mortality: 112 - 7 = 105, with a mandatory cause.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 7,
    timestamptz '2026-08-07 06:00+00', 'DISEASE', 'التهاب رئوي',
    'تقرير بيطري', null, 'gf22-mortality-1'
  )$q$, :'gf22_project', :'gf22_main')) gf22_mortality \gset
select 1/case when (
  select mortality = 7 and current_quantity = 105
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) then 1 else 0 end as mortality_decreases_derived_quantity;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1, now(), 'SPONTANEOUS',
    null, null, null, 'gf22-mortality-cause'
  )$q$, :'gf22_project', :'gf22_main')) like '%invalid livestock mortality cause%'
then 1 else 0 end as invalid_mortality_cause_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 106, now(), 'UNKNOWN',
    null, null, null, 'gf22-mortality-over'
  )$q$, :'gf22_project', :'gf22_main')) like '%exceeds the current derived quantity%'
then 1 else 0 end as mortality_cannot_exceed_current;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 7,
    timestamptz '2026-08-07 06:00+00', 'DISEASE', 'التهاب رئوي',
    'تقرير بيطري', null, 'gf22-mortality-1'
  )$q$, :'gf22_project', :'gf22_main')) = :'gf22_mortality'
then 1 else 0 end as mortality_replay_is_idempotent;

-- Registry-driven guards cannot be bypassed by privileged inserts.
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

-- Split: exact 30 OUT / 30 IN under one operation and lineage identity.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 30,
    timestamptz '2026-08-08 06:00+00', 'دفعة التقسيم أ', %L, %L,
    'MIXED', null, 'فصل مجموعة التسمين', 'محضر تقسيم', null, 'gf22-split-1'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_herd_b', :'gf22_site_b')) gf22_split \gset
select id gf22_split_dest from livestock_cohorts
 where cohort_reference = 'دفعة التقسيم أ' and project_id = :'gf22_project' \gset
select 1/case when (
  select split_out = 30 and current_quantity = 75
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_main'
) then 1 else 0 end as split_decreases_source;
select 1/case when (
  select opening_headcount = 0 and split_in = 30 and current_quantity = 30
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf22_split_dest'
) then 1 else 0 end as split_destination_exact;
select 1/case when (
  select count(*) = 2
    and sum(case when t.direction=-1 then q.quantity else 0 end) = 30
    and sum(case when t.direction=1 then q.quantity else 0 end) = 30
  from livestock_quantity_events q
  join livestock_quantity_event_types t on t.code=q.event_type
  where q.operation_id = :'gf22_split'
) then 1 else 0 end as split_conserves_quantity_exactly;
select 1/case when (
  select count(*) = 1 from livestock_cohort_lineage
  where operation_id = :'gf22_split' and source_cohort_id = :'gf22_main'
    and destination_cohort_id = :'gf22_split_dest' and quantity = 30
) then 1 else 0 end as split_lineage_exact;
select 1/case when (
  select c.origin_type='SPLIT_FROM_COHORT' and c.herd_id=:'gf22_herd_b'
    and public.livestock_current_cohort_state(c.id)='ACTIVE'
  from livestock_cohorts c where c.id=:'gf22_split_dest'
) and (
  select site_id=:'gf22_site_b' from livestock_cohort_initial_placements
   where cohort_id=:'gf22_split_dest'
) then 1 else 0 end as split_destination_context_coherent;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 76, now(),
    'دفعة تقسيم زائدة', %L, %L, null, null, 'تقسيم زائد', null, null,
    'gf22-split-over'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_herd_b', :'gf22_site_b'))
  like '%exceeds the current derived quantity%'
then 1 else 0 end as oversplit_rejected;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.split_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 30,
    timestamptz '2026-08-08 06:00+00', 'دفعة التقسيم أ', %L, %L,
    'MIXED', null, 'فصل مجموعة التسمين', 'محضر تقسيم', null, 'gf22-split-1'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_herd_b', :'gf22_site_b')) = :'gf22_split'
then 1 else 0 end as split_replay_returns_same_operation;

-- PLANNED Cohort remains ineligible for split.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة مخططة 022', 'PURCHASED', date '2026-08-02', 10, null, null,
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

-- Merge partner, then exact 25 + 40 -> 65 destination.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة الدمج ب', 'PURCHASED', date '2026-08-02', 40, 'MIXED', null,
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
    timestamptz '2026-08-09 06:00+00', 'دفعة الدمج الموحدة', %L, %L,
    'MIXED', null, 'توحيد مجموعتين', 'محضر دمج', null, 'gf22-merge-1'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_merge_b',
       :'gf22_herd_a', :'gf22_site_a')) gf22_merge \gset
select id gf22_merge_dest from livestock_cohorts
 where cohort_reference='دفعة الدمج الموحدة' and project_id=:'gf22_project' \gset
select 1/case when (
  select merge_out=25 and current_quantity=50 from livestock_cohort_quantity_rollforward
   where cohort_id=:'gf22_main'
) then 1 else 0 end as merge_consumes_source_a;
select 1/case when (
  select merge_out=40 and current_quantity=0 from livestock_cohort_quantity_rollforward
   where cohort_id=:'gf22_merge_b'
) then 1 else 0 end as merge_consumes_source_b;
select 1/case when (
  select opening_headcount=0 and merge_in=65 and current_quantity=65
  from livestock_cohort_quantity_rollforward where cohort_id=:'gf22_merge_dest'
) then 1 else 0 end as merge_destination_is_exact_sum;
select 1/case when (
  select count(*)=3
    and sum(case when t.direction=-1 then q.quantity else 0 end)=65
    and sum(case when t.direction=1 then q.quantity else 0 end)=65
  from livestock_quantity_events q
  join livestock_quantity_event_types t on t.code=q.event_type
  where q.operation_id=:'gf22_merge'
) then 1 else 0 end as merge_conserves_quantity_exactly;
select 1/case when (
  select count(*)=2 and sum(quantity)=65 from livestock_cohort_lineage
   where operation_id=:'gf22_merge'
) then 1 else 0 end as merge_lineage_exact;
select 1/case when public.livestock_current_cohort_state(:'gf22_merge_b')='ACTIVE'
then 1 else 0 end as zero_quantity_does_not_mutate_lifecycle;

-- Cross-species merge is refused at the command boundary.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_herd(
    '10000000-0000-4000-8000-000000000001', %L, 'قطيع الأغنام',
    'HERD-SHEEP', 'SHEEP', 'MEAT', null, 'gf22-herd-sheep'
  )$q$, :'gf22_project')) gf22_herd_sheep \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة أغنام', 'PURCHASED', date '2026-08-03', 20, null, null,
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
  )$q$, :'gf22_project', :'gf22_main', :'gf22_sheep',
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
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.merge_livestock_cohorts(
    '10000000-0000-4000-8000-000000000001', %L,
    array[%L,%L]::uuid[], array[25,40]::integer[],
    timestamptz '2026-08-09 06:00+00', 'دفعة الدمج الموحدة', %L, %L,
    'MIXED', null, 'توحيد مجموعتين', 'محضر دمج', null, 'gf22-merge-1'
  )$q$, :'gf22_project', :'gf22_main', :'gf22_merge_b',
       :'gf22_herd_a', :'gf22_site_a')) = :'gf22_merge'
then 1 else 0 end as merge_replay_returns_same_operation;

-- Existing conservation constraint still rejects a naked forged operation.
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

-- Exact arithmetic across all six classes for the main Cohort.
select 1/case when (
  select opening_headcount=100 and births=12 and mortality=7
    and split_out=30 and split_in=0 and merge_out=25 and merge_in=0
    and current_quantity=50
    and current_quantity = opening_headcount + births + split_in + merge_in
                           - mortality - split_out - merge_out
  from livestock_cohort_quantity_rollforward where cohort_id=:'gf22_main'
) then 1 else 0 end as rollforward_arithmetic_exact;
select 1/case when (
  select bool_and(current_quantity = opening_headcount + births + split_in + merge_in
                                    - mortality - split_out - merge_out
                  and current_quantity >= 0)
  from livestock_cohort_quantity_rollforward
) then 1 else 0 end as rollforward_invariant_holds_globally;
select 1/case when (
  select bool_and(data_type='integer') from information_schema.columns
  where table_schema='public' and table_name='livestock_cohort_quantity_rollforward'
    and column_name in ('opening_headcount','births','mortality','split_in','split_out','merge_in','merge_out','current_quantity')
) then 1 else 0 end as rollforward_is_exact_integer;

-- RLS/default-deny, actor authority, and Finance isolation remain intact.
select 1/case when (
  select count(*)=5 and bool_and(relrowsecurity and relforcerowsecurity)
  from pg_class where relnamespace='public'::regnamespace
    and relname in ('livestock_quantity_events','livestock_quantity_operations','livestock_cohort_lineage','livestock_cohort_movements','livestock_weight_events')
) then 1 else 0 end as gf022_force_rls_preserved;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  insert into public.livestock_quantity_events(
    organization_id,project_id,cohort_id,event_type,quantity,effective_at,
    recorded_by,idempotency_key,request_hash
  ) values ('10000000-0000-4000-8000-000000000001',%L,%L,'BIRTH',5,now(),
    '00000000-0000-4000-8000-000000000001','gf22-direct-dml',repeat('e',64))
$q$, :'gf22_project', :'gf22_main')) like '%permission denied%'
then 1 else 0 end as quantity_direct_insert_denied;
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002',
  format('select count(*) from public.livestock_quantity_events_read where project_id=%L', :'gf22_project'))=0
then 1 else 0 end as quantity_rls_isolated;
select 1/case when (
  select bool_and(recorded_by='00000000-0000-4000-8000-000000000001')
  from livestock_quantity_events
) and (
  select bool_and(performed_by='00000000-0000-4000-8000-000000000001')
  from livestock_quantity_operations
) then 1 else 0 end as gf022_actor_server_authoritative;
select 1/case when (select count(*) from journal_batches)=:'gf22_jb_before'
  and (select count(*) from journal_lines)=:'gf22_jl_before'
  and (select count(*) from project_payments)=:'gf22_pay_before'
then 1 else 0 end as gf022_produced_no_finance_artifact;

select 'GF-022 biological quantity events, split and merge PASS' result;