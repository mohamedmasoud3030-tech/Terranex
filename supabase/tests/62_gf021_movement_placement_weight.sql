-- GF-021 — movement, derived placement, quantity foundation and weight events.
--
-- Reuses the GF-020 tenant-A hierarchy created by 58_gf020_livestock_foundation
-- and the gf20_run / gf20_catch / gf20_count harness defined there.

select id gf21_project from investment_projects where internal_reference = 'GF020-LS-A' \gset
select id gf21_site_a from livestock_sites where internal_reference = 'SITE-A' \gset
select id gf21_herd_a from livestock_herds where internal_reference = 'HERD-A' \gset
select id gf21_cohort from livestock_cohorts where cohort_reference = 'دفعة أغسطس 2026' \gset

-- ---------------------------------------------------------------------------
-- Fixtures: a second Site, a second Herd, and an activated movement Cohort.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_site(
    '10000000-0000-4000-8000-000000000001', %L, 'حظيرة التسمين الثانية',
    'SITE-B', 'BARN', 'الفيوم', null, 'gf21-site-b'
  )$q$, :'gf21_project')) gf21_site_b \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_herd(
    '10000000-0000-4000-8000-000000000001', %L, 'قطيع الإكثار',
    'HERD-B', 'CATTLE', 'BREEDING', null, 'gf21-herd-b'
  )$q$, :'gf21_project')) gf21_herd_b \gset

select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة الحركة', 'PURCHASED', date '2026-08-05', 40, 'MIXED', null,
    null, null, null, null, null, 'gf21-cohort-move'
  )$q$, :'gf21_project', :'gf21_herd_a', :'gf21_site_a')) gf21_mover \gset

-- An operational event requires an ACTIVE Cohort.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    now(), 'نقل قبل التفعيل', null, null, 'gf21-move-planned'
  )$q$, :'gf21_project', :'gf21_mover', :'gf21_site_a', :'gf21_herd_a',
       :'gf21_site_b', :'gf21_herd_a')) like '%livestock cohort is not active%'
then 1 else 0 end as movement_requires_active_cohort;

select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'بدء تشغيل دفعة الحركة', null, 'gf21-activate-mover'
  )$q$, :'gf21_project', :'gf21_mover')) gf21_mover_active \gset

-- ---------------------------------------------------------------------------
-- GF-021.B — Opening-only Cohort resolves to exactly one OPENING placement.
-- ---------------------------------------------------------------------------
select 1/case when (
  select count(*) = 1 and bool_and(
    placement_source = 'OPENING'
    and current_site_id = :'gf21_site_a'
    and current_herd_id = :'gf21_herd_a'
    and movement_id is null
  )
  from livestock_cohort_current_placement where cohort_id = :'gf21_mover'
) then 1 else 0 end as opening_only_placement_exact;

-- Every valid Cohort resolves to exactly one current placement row.
select 1/case when (
  select count(*) = (select count(*) from livestock_cohorts)
  from livestock_cohort_current_placement
) then 1 else 0 end as one_current_placement_per_cohort;

-- ---------------------------------------------------------------------------
-- GF-021.A — Valid Site transfer, keeping the Herd.
-- ---------------------------------------------------------------------------
select (select count(*) from journal_batches) gf21_jb_before,
       (select count(*) from project_payments) gf21_pay_before,
       (select count(*) from journal_lines) gf21_jl_before \gset

select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    timestamptz '2026-08-10 08:00+00', 'نقل إلى الحظيرة الثانية',
    'محضر نقل اصطناعي', null, 'gf21-move-site'
  )$q$, :'gf21_project', :'gf21_mover', :'gf21_site_a', :'gf21_herd_a',
       :'gf21_site_b', :'gf21_herd_a')) gf21_move_1 \gset

select 1/case when (
  select placement_source = 'MOVEMENT'
    and current_site_id = :'gf21_site_b'
    and current_herd_id = :'gf21_herd_a'
    and movement_id = :'gf21_move_1'
  from livestock_cohort_current_placement where cohort_id = :'gf21_mover'
) then 1 else 0 end as site_transfer_updates_derived_placement;
select 1/case when (
  select site_changed and not herd_changed
  from livestock_cohort_movements_read where id = :'gf21_move_1'
) then 1 else 0 end as site_only_movement_classified;

-- The GF-020 opening placement is untouched by movement.
select 1/case when (
  select site_id = :'gf21_site_a'
  from livestock_cohort_initial_placements where cohort_id = :'gf21_mover'
) then 1 else 0 end as opening_placement_immutable_after_movement;

-- ---------------------------------------------------------------------------
-- GF-021.A — Valid Herd reassignment, keeping the Site.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    timestamptz '2026-08-12 08:00+00', 'إعادة تصنيف إلى قطيع الإكثار',
    null, null, 'gf21-move-herd'
  )$q$, :'gf21_project', :'gf21_mover', :'gf21_site_b', :'gf21_herd_a',
       :'gf21_site_b', :'gf21_herd_b')) gf21_move_2 \gset
select 1/case when (
  select current_site_id = :'gf21_site_b' and current_herd_id = :'gf21_herd_b'
  from livestock_cohort_current_placement where cohort_id = :'gf21_mover'
) then 1 else 0 end as herd_reassignment_updates_derived_placement;
select 1/case when (
  select not site_changed and herd_changed
  from livestock_cohort_movements_read where id = :'gf21_move_2'
) then 1 else 0 end as herd_only_movement_classified;
select 1/case when (
  select previous_movement_id = :'gf21_move_1'
  from livestock_cohort_movements where id = :'gf21_move_2'
) then 1 else 0 end as movement_chain_is_causal;

-- ---------------------------------------------------------------------------
-- GF-021.A — Valid combined Site + Herd movement.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    timestamptz '2026-08-14 08:00+00', 'نقل مزدوج للموقع والقطيع',
    null, null, 'gf21-move-both'
  )$q$, :'gf21_project', :'gf21_mover', :'gf21_site_b', :'gf21_herd_b',
       :'gf21_site_a', :'gf21_herd_a')) gf21_move_3 \gset
select 1/case when (
  select site_changed and herd_changed
  from livestock_cohort_movements_read where id = :'gf21_move_3'
) then 1 else 0 end as combined_movement_classified;
select 1/case when (
  select current_site_id = :'gf21_site_a' and current_herd_id = :'gf21_herd_a'
  from livestock_cohort_current_placement where cohort_id = :'gf21_mover'
) then 1 else 0 end as combined_movement_derived_placement;

-- Exactly one unconsumed chain tip after three movements.
select 1/case when (
  select count(*) = 3 from livestock_cohort_movements where cohort_id = :'gf21_mover'
) and public.livestock_current_placement_movement(:'gf21_mover') = :'gf21_move_3'
then 1 else 0 end as single_movement_tip;

-- ---------------------------------------------------------------------------
-- GF-021.A — Rejections.
-- ---------------------------------------------------------------------------

-- No-op movement.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    now(), 'حركة بدون تغيير', null, null, 'gf21-move-noop'
  )$q$, :'gf21_project', :'gf21_mover', :'gf21_site_a', :'gf21_herd_a',
       :'gf21_site_a', :'gf21_herd_a')) like '%must change site or herd%'
then 1 else 0 end as no_op_movement_rejected;

-- Stale source: the client declares a placement that is no longer current.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    now(), 'مصدر قديم', null, null, 'gf21-move-stale'
  )$q$, :'gf21_project', :'gf21_mover', :'gf21_site_b', :'gf21_herd_b',
       :'gf21_site_b', :'gf21_herd_a')) like '%source is not the current placement%'
then 1 else 0 end as stale_source_rejected;

-- Cross-project destination Site (an Agriculture/Real-Estate-era foreign Site).
select gf20_run('00000000-0000-4000-8000-000000000001', $q$
  select public.create_investment_project(
    '10000000-0000-4000-8000-000000000001', 'مشروع ماشية ثانٍ', 'GF021-LS-A2',
    null, 'LIVESTOCK'
  )$q$) gf21_project_2 \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_site(
    '10000000-0000-4000-8000-000000000001', %L, 'موقع مشروع آخر',
    'SITE-P2', 'FARM', null, null, 'gf21-site-p2'
  )$q$, :'gf21_project_2')) gf21_site_p2 \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_herd(
    '10000000-0000-4000-8000-000000000001', %L, 'قطيع مشروع آخر',
    'HERD-P2', 'SHEEP', 'MEAT', null, 'gf21-herd-p2'
  )$q$, :'gf21_project_2')) gf21_herd_p2 \gset

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    now(), 'وجهة من مشروع آخر', null, null, 'gf21-move-xproject-site'
  )$q$, :'gf21_project', :'gf21_mover', :'gf21_site_a', :'gf21_herd_a',
       :'gf21_site_p2', :'gf21_herd_a')) like '%livestock site not found%'
then 1 else 0 end as cross_project_site_rejected;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    now(), 'قطيع من مشروع آخر', null, null, 'gf21-move-xproject-herd'
  )$q$, :'gf21_project', :'gf21_mover', :'gf21_site_a', :'gf21_herd_a',
       :'gf21_site_a', :'gf21_herd_p2')) like '%livestock herd not found%'
then 1 else 0 end as cross_project_herd_rejected;

-- Wrong sector: a Real Estate project can never host a Livestock movement.
select id gf21_re_project from investment_projects where sector = 'REAL_ESTATE' limit 1 \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    now(), 'قطاع خاطئ', null, null, 'gf21-move-sector'
  )$q$, :'gf21_re_project', :'gf21_mover', :'gf21_site_a', :'gf21_herd_a',
       :'gf21_site_b', :'gf21_herd_a')) like '%livestock project not found%'
then 1 else 0 end as wrong_sector_movement_rejected;

-- Cross-tenant: tenant B cannot command tenant A's Cohort.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000002', format($q$
  select public.record_livestock_movement(
    '20000000-0000-4000-8000-000000000002', %L, %L, %L, %L, %L, %L,
    now(), 'محاولة عابرة للمستأجر', null, null, 'gf21-move-tenant-b'
  )$q$, :'gf21_project', :'gf21_mover', :'gf21_site_a', :'gf21_herd_a',
       :'gf21_site_b', :'gf21_herd_a')) <> 'NO_EXCEPTION'
then 1 else 0 end as cross_tenant_movement_rejected;

-- Tenant B cannot read tenant A's placement or movement rows.
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002',
  format('select count(*) from public.livestock_cohort_movements_read where project_id = %L',
         :'gf21_project')) = 0 then 1 else 0 end as movement_rls_isolated;
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002',
  format('select count(*) from public.livestock_cohort_current_placement_read where project_id = %L',
         :'gf21_project')) = 0 then 1 else 0 end as placement_rls_isolated;

-- Idempotency: same key + same payload replays the same movement.
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    timestamptz '2026-08-10 08:00+00', 'نقل إلى الحظيرة الثانية',
    'محضر نقل اصطناعي', null, 'gf21-move-site'
  )$q$, :'gf21_project', :'gf21_mover', :'gf21_site_a', :'gf21_herd_a',
       :'gf21_site_b', :'gf21_herd_a')) = :'gf21_move_1'
then 1 else 0 end as movement_replay_returns_same_row;

-- Same key + different payload is refused.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_movement(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, %L, %L, %L,
    timestamptz '2026-08-10 08:00+00', 'سبب مختلف تمامًا',
    null, null, 'gf21-move-site'
  )$q$, :'gf21_project', :'gf21_mover', :'gf21_site_a', :'gf21_herd_a',
       :'gf21_site_b', :'gf21_herd_a')) like '%idempotency key payload mismatch%'
then 1 else 0 end as movement_payload_mismatch_rejected;

-- Replay created no duplicate movement row and no duplicate audit event.
select 1/case when (
  select count(*) = 3 from livestock_cohort_movements where cohort_id = :'gf21_mover'
) and (
  select count(*) = 3 from audit_events
  where entity_id = :'gf21_mover' and event_type = 'LIVESTOCK_COHORT_MOVED'
) then 1 else 0 end as movement_replay_no_duplicate_audit;

-- Direct authenticated DML on the movement table is denied.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  update public.livestock_cohort_movements set destination_site_id = %L where id = %L
$q$, :'gf21_site_b', :'gf21_move_1')) like '%permission denied%'
then 1 else 0 end as movement_direct_dml_denied;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  delete from public.livestock_cohort_movements where id = %L
$q$, :'gf21_move_1')) like '%permission denied%'
then 1 else 0 end as movement_direct_delete_denied;

-- Even the owner/import path cannot rewrite or branch the placement chain.
select 1/case when gf20_owner_catch(format($q$
  update public.livestock_cohort_movements set reason = 'تعديل' where id = %L
$q$, :'gf21_move_1')) like '%append-only%'
then 1 else 0 end as movement_owner_update_rejected;

-- A forged successor consuming an already-consumed predecessor is rejected.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_cohort_movements(
    organization_id, project_id, cohort_id, previous_movement_id, effective_at,
    source_site_id, source_herd_id, destination_site_id, destination_herd_id,
    reason, moved_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, now(),
    %L, %L, %L, %L, 'فرع مرفوض',
    '00000000-0000-4000-8000-000000000001', 'gf21-branch-move', repeat('a',64)
  )
$q$, :'gf21_project', :'gf21_mover', :'gf21_move_1',
     :'gf21_site_b', :'gf21_herd_a', :'gf21_site_a', :'gf21_herd_a'))
  like '%duplicate key%'
then 1 else 0 end as movement_branch_rejected;

-- A forged root whose source is not the opening placement is rejected.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_cohort_movements(
    organization_id, project_id, cohort_id, previous_movement_id, effective_at,
    source_site_id, source_herd_id, destination_site_id, destination_herd_id,
    reason, moved_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, null, now(),
    %L, %L, %L, %L, 'جذر مزور',
    '00000000-0000-4000-8000-000000000001', 'gf21-forged-root', repeat('b',64)
  )
$q$, :'gf21_project', :'gf21_mover', :'gf21_site_b', :'gf21_herd_b',
     :'gf21_site_a', :'gf21_herd_a'))
  like '%source is not the current placement%'
then 1 else 0 end as movement_forged_root_rejected;

-- A predecessor belonging to a different Cohort is rejected by the composite FK.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_cohort_movements(
    organization_id, project_id, cohort_id, previous_movement_id, effective_at,
    source_site_id, source_herd_id, destination_site_id, destination_herd_id,
    reason, moved_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, now(),
    %L, %L, %L, %L, 'سلف من دفعة أخرى',
    '00000000-0000-4000-8000-000000000001', 'gf21-xcohort-pred', repeat('c',64)
  )
$q$, :'gf21_project', :'gf21_cohort', :'gf21_move_3',
     :'gf21_site_a', :'gf21_herd_a', :'gf21_site_b', :'gf21_herd_a'))
  <> 'NO_EXCEPTION'
then 1 else 0 end as movement_cross_cohort_predecessor_rejected;

-- A no-op cannot be forged through a privileged insert either.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_cohort_movements(
    organization_id, project_id, cohort_id, previous_movement_id, effective_at,
    source_site_id, source_herd_id, destination_site_id, destination_herd_id,
    reason, moved_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, now(),
    %L, %L, %L, %L, 'حركة صفرية مزورة',
    '00000000-0000-4000-8000-000000000001', 'gf21-forged-noop', repeat('d',64)
  )
$q$, :'gf21_project', :'gf21_mover', :'gf21_move_3',
     :'gf21_site_a', :'gf21_herd_a', :'gf21_site_a', :'gf21_herd_a'))
  like '%livestock_movement_not_a_no_op%'
then 1 else 0 end as movement_forged_no_op_rejected;

-- ---------------------------------------------------------------------------
-- GF-021.B — Ambiguity is rejected, never masked with LIMIT 1.
-- ---------------------------------------------------------------------------
-- A deliberately corrupted graph (two unconsumed tips) must make the resolver
-- raise instead of arbitrarily choosing one. Producing that corruption requires
-- disabling the validator AND dropping the single-successor unique constraint,
-- which is itself proof that no ordinary path can reach this state. The whole
-- corruption is rolled back afterwards.
begin;
  alter table public.livestock_cohort_movements disable trigger livestock_movements_validate_link;
  alter table public.livestock_cohort_movements drop constraint livestock_cohort_movements_previous_movement_id_key;
  insert into public.livestock_cohort_movements(
    organization_id, project_id, cohort_id, previous_movement_id, effective_at,
    source_site_id, source_herd_id, destination_site_id, destination_herd_id,
    reason, moved_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', :'gf21_project', :'gf21_mover',
    :'gf21_move_1', now(), :'gf21_site_b', :'gf21_herd_a',
    :'gf21_site_a', :'gf21_herd_b', 'تفرع متعمد للاختبار',
    '00000000-0000-4000-8000-000000000001', 'gf21-corrupt-branch', repeat('f',64)
  );
  select 1/case when gf20_owner_catch(format(
    'select public.livestock_current_placement_movement(%L)', :'gf21_mover'
  )) like '%invalid livestock placement chain tip count%'
  then 1 else 0 end as ambiguous_placement_rejected;
rollback;

-- The chain is intact again after the rolled-back corruption.
select 1/case when public.livestock_current_placement_movement(:'gf21_mover') = :'gf21_move_3'
then 1 else 0 end as placement_chain_intact_after_rollback;

-- ---------------------------------------------------------------------------
-- GF-021.C — Quantity rollforward foundation.
-- ---------------------------------------------------------------------------

-- GF-021 registers no quantity event class: the architecture exists, the
-- events do not, and current quantity truthfully equals opening headcount.
select 1/case when (
  select count(*) = 0 from livestock_quantity_event_types
) then 1 else 0 end as gf021_registers_no_quantity_event_type;
select 1/case when (
  select count(*) = 0 from livestock_quantity_events
) then 1 else 0 end as gf021_creates_no_quantity_event;
select 1/case when (
  select opening_headcount = 40 and current_quantity = 40
    and quantity_increase = 0 and quantity_decrease = 0
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf21_mover'
) then 1 else 0 end as rollforward_equals_opening_in_gf021;
select 1/case when public.livestock_current_cohort_quantity(:'gf21_mover') = 40
then 1 else 0 end as quantity_resolver_matches_opening;

-- Headcount is exact integer, never floating point.
select 1/case when (
  select bool_and(data_type = 'integer')
  from information_schema.columns
  where table_schema = 'public' and table_name = 'livestock_quantity_events'
    and column_name = 'quantity'
) then 1 else 0 end as quantity_is_exact_integer;

-- No mutable authoritative derived state exists on any Livestock BASE TABLE.
-- Derived views may legitimately expose a `current_*` column, because a view
-- recomputes it from the event history and cannot be written to.
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
) then 1 else 0 end as no_mutable_derived_state;

-- ---------------------------------------------------------------------------
-- GF-021.D — WeightEvent: every method, and its method-specific rules.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    timestamptz '2026-08-15 07:00+00', 'COHORT_TOTAL', 9600, 'KG',
    null, null, 'محضر وزن جماعي', null, 'gf21-weight-total'
  )$q$, :'gf21_project', :'gf21_mover')) gf21_weight_total \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    timestamptz '2026-08-16 07:00+00', 'INDIVIDUAL_MEASURED', 1250.500, 'KG',
    5, null, 'بطاقات وزن فردية', null, 'gf21-weight-individual'
  )$q$, :'gf21_project', :'gf21_mover')) gf21_weight_individual \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    timestamptz '2026-08-17 07:00+00', 'SAMPLED_AVERAGE', 242.750, 'KG',
    null, 8, 'كشف عينة موقعة', null, 'gf21-weight-sampled'
  )$q$, :'gf21_project', :'gf21_mover')) gf21_weight_sampled \gset
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    timestamptz '2026-08-18 07:00+00', 'ESTIMATED', 9800, 'KG',
    null, null, null, 'تقدير بصري', 'gf21-weight-estimated'
  )$q$, :'gf21_project', :'gf21_mover')) gf21_weight_estimated \gset

select 1/case when (
  select count(*) = 4 from livestock_weight_events where cohort_id = :'gf21_mover'
) then 1 else 0 end as all_four_weight_methods_recorded;

-- The read model states the meaning of each stored number.
select 1/case when (
  select value_meaning = 'AVERAGE_PER_ANIMAL_SAMPLED' and sample_size = 8 and not is_estimate
  from livestock_weight_events_read where id = :'gf21_weight_sampled'
) then 1 else 0 end as sampled_average_meaning_explicit;
select 1/case when (
  select value_meaning = 'COHORT_TOTAL_ESTIMATED' and is_estimate
  from livestock_weight_events_read where id = :'gf21_weight_estimated'
) then 1 else 0 end as estimate_is_flagged_as_estimate;
select 1/case when (
  select value_meaning = 'TOTAL_OF_MEASURED_ANIMALS' and measured_animal_count = 5
  from livestock_weight_events_read where id = :'gf21_weight_individual'
) then 1 else 0 end as individual_measurement_scope_explicit;

-- Zero and negative weights are rejected.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'COHORT_TOTAL',
    0, 'KG', null, null, null, null, 'gf21-weight-zero'
  )$q$, :'gf21_project', :'gf21_mover')) like '%invalid livestock weight value%'
then 1 else 0 end as zero_weight_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'COHORT_TOTAL',
    -5, 'KG', null, null, null, null, 'gf21-weight-negative'
  )$q$, :'gf21_project', :'gf21_mover')) like '%invalid livestock weight value%'
then 1 else 0 end as negative_weight_rejected;

-- A non-KG unit is rejected.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'COHORT_TOTAL',
    100, 'LB', null, null, null, null, 'gf21-weight-unit'
  )$q$, :'gf21_project', :'gf21_mover')) like '%invalid livestock weight unit%'
then 1 else 0 end as non_kg_unit_rejected;

-- SAMPLED_AVERAGE requires a sample size and evidence.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'SAMPLED_AVERAGE',
    200, 'KG', null, null, 'كشف', null, 'gf21-weight-nosample'
  )$q$, :'gf21_project', :'gf21_mover')) like '%requires a sample size%'
then 1 else 0 end as sampled_average_requires_sample_size;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'SAMPLED_AVERAGE',
    200, 'KG', null, 4, null, null, 'gf21-weight-noevidence'
  )$q$, :'gf21_project', :'gf21_mover')) like '%requires an evidence reference%'
then 1 else 0 end as sampled_average_requires_evidence;

-- Sample size may not exceed the current derived quantity (40).
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'SAMPLED_AVERAGE',
    200, 'KG', null, 41, 'كشف', null, 'gf21-weight-oversample'
  )$q$, :'gf21_project', :'gf21_mover')) like '%sample size exceeds current derived quantity%'
then 1 else 0 end as oversized_sample_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'INDIVIDUAL_MEASURED',
    200, 'KG', 41, null, null, null, 'gf21-weight-overmeasured'
  )$q$, :'gf21_project', :'gf21_mover')) like '%measured animal count exceeds current derived quantity%'
then 1 else 0 end as oversized_measured_count_rejected;

-- Incompatible metadata combinations are rejected.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'SAMPLED_AVERAGE',
    200, 'KG', 3, 4, 'كشف', null, 'gf21-weight-bothmeta'
  )$q$, :'gf21_project', :'gf21_mover')) like '%does not take a measured animal count%'
then 1 else 0 end as sampled_average_rejects_measured_count;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'COHORT_TOTAL',
    200, 'KG', null, 4, null, null, 'gf21-weight-totalsample'
  )$q$, :'gf21_project', :'gf21_mover')) like '%does not take population metadata%'
then 1 else 0 end as cohort_total_rejects_sample_size;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'ESTIMATED',
    200, 'KG', 4, null, null, null, 'gf21-weight-estmeta'
  )$q$, :'gf21_project', :'gf21_mover')) like '%does not take population metadata%'
then 1 else 0 end as estimate_rejects_measured_count;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'INDIVIDUAL_MEASURED',
    200, 'KG', null, null, null, null, 'gf21-weight-noindivcount'
  )$q$, :'gf21_project', :'gf21_mover')) like '%requires a measured animal count%'
then 1 else 0 end as individual_requires_measured_count;

-- An unknown method is rejected.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'GUESSED',
    200, 'KG', null, null, null, null, 'gf21-weight-method'
  )$q$, :'gf21_project', :'gf21_mover')) like '%invalid livestock weight method%'
then 1 else 0 end as unknown_weight_method_rejected;

-- Even a privileged path cannot store a sampled average without a sample size.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_weight_events(
    organization_id, project_id, cohort_id, effective_at, method,
    weight_value, weight_unit, evidence_reference, recorded_by,
    idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'SAMPLED_AVERAGE',
    200, 'KG', 'كشف', '00000000-0000-4000-8000-000000000001',
    'gf21-forged-sample', repeat('a',64)
  )
$q$, :'gf21_project', :'gf21_mover')) like '%livestock_weight_method_metadata%'
then 1 else 0 end as privileged_sampled_average_without_size_rejected;

-- Tenant/project mismatch is rejected.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'COHORT_TOTAL',
    200, 'KG', null, null, null, null, 'gf21-weight-xproject'
  )$q$, :'gf21_project_2', :'gf21_mover')) like '%livestock cohort not found%'
then 1 else 0 end as weight_cross_project_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000002', format($q$
  select public.record_livestock_weight_event(
    '20000000-0000-4000-8000-000000000002', %L, %L, now(), 'COHORT_TOTAL',
    200, 'KG', null, null, null, null, 'gf21-weight-tenant-b'
  )$q$, :'gf21_project', :'gf21_mover')) <> 'NO_EXCEPTION'
then 1 else 0 end as weight_cross_tenant_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'COHORT_TOTAL',
    200, 'KG', null, null, null, null, 'gf21-weight-sector'
  )$q$, :'gf21_re_project', :'gf21_mover')) like '%livestock project not found%'
then 1 else 0 end as weight_wrong_sector_rejected;

-- Weight replay is idempotent and does not duplicate the audit event.
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    timestamptz '2026-08-15 07:00+00', 'COHORT_TOTAL', 9600, 'KG',
    null, null, 'محضر وزن جماعي', null, 'gf21-weight-total'
  )$q$, :'gf21_project', :'gf21_mover')) = :'gf21_weight_total'
then 1 else 0 end as weight_replay_returns_same_row;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_weight_event(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    timestamptz '2026-08-15 07:00+00', 'COHORT_TOTAL', 9999, 'KG',
    null, null, 'محضر وزن جماعي', null, 'gf21-weight-total'
  )$q$, :'gf21_project', :'gf21_mover')) like '%idempotency key payload mismatch%'
then 1 else 0 end as weight_payload_mismatch_rejected;
select 1/case when (
  select count(*) = 4 from livestock_weight_events where cohort_id = :'gf21_mover'
) and (
  select count(*) = 4 from audit_events
  where entity_id = :'gf21_mover' and event_type = 'LIVESTOCK_WEIGHT_RECORDED'
) then 1 else 0 end as weight_replay_no_duplicate_audit;

-- Direct authenticated DML on weight events is denied.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  update public.livestock_weight_events set weight_value = 1 where id = %L
$q$, :'gf21_weight_total')) like '%permission denied%'
then 1 else 0 end as weight_direct_dml_denied;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  insert into public.livestock_weight_events(
    organization_id, project_id, cohort_id, effective_at, method,
    weight_value, weight_unit, recorded_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, now(), 'COHORT_TOTAL',
    1, 'KG', '00000000-0000-4000-8000-000000000001', 'gf21-direct-insert',
    repeat('a',64)
  )
$q$, :'gf21_project', :'gf21_mover')) like '%permission denied%'
then 1 else 0 end as weight_direct_insert_denied;

-- Actor spoofing is impossible: the recorded actor is always auth.uid().
select 1/case when (
  select bool_and(recorded_by = '00000000-0000-4000-8000-000000000001')
  from livestock_weight_events where cohort_id = :'gf21_mover'
) and (
  select bool_and(moved_by = '00000000-0000-4000-8000-000000000001')
  from livestock_cohort_movements where cohort_id = :'gf21_mover'
) then 1 else 0 end as actor_is_server_authoritative;

-- ---------------------------------------------------------------------------
-- Finance and other-sector isolation.
-- ---------------------------------------------------------------------------
select 1/case when (select count(*) from journal_batches) = :'gf21_jb_before'
  and (select count(*) from journal_lines) = :'gf21_jl_before'
  and (select count(*) from project_payments) = :'gf21_pay_before'
then 1 else 0 end as gf021_produced_no_finance_artifact;

-- Forced RLS on every new material table.
select 1/case when (
  select count(*) = 3 and bool_and(relrowsecurity and relforcerowsecurity)
  from pg_class
  where relnamespace = 'public'::regnamespace
    and relname in (
      'livestock_cohort_movements', 'livestock_quantity_events',
      'livestock_weight_events'
    )
) then 1 else 0 end as gf021_force_rls_on_all_material_tables;

-- Every new material table is tenant- and project-scoped NOT NULL.
select 1/case when (
  select count(*) = 6 and bool_and(is_nullable = 'NO')
  from information_schema.columns
  where table_schema = 'public'
    and table_name in (
      'livestock_cohort_movements', 'livestock_quantity_events',
      'livestock_weight_events'
    )
    and column_name in ('organization_id', 'project_id')
) then 1 else 0 end as gf021_tenant_project_scoped;

select 'GF-021 movement, placement, quantity foundation and weight PASS' result;
