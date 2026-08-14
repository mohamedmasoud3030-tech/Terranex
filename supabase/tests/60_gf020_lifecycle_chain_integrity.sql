-- GF-020 causal lifecycle graph hardening through privileged/import paths.
create or replace function gf20_owner_catch(p_sql text)
returns text language plpgsql as $$
declare m text;
begin
  begin execute p_sql;
  exception when others then return sqlerrm;
  end;
  return 'NO_EXCEPTION';
end $$;

select id gf20_project from investment_projects where internal_reference = 'GF020-LS-A' \gset
select id gf20_site from livestock_sites where internal_reference = 'SITE-A' \gset
select id gf20_herd from livestock_herds where internal_reference = 'HERD-A' \gset
select id gf20_cohort from livestock_cohorts where cohort_reference = 'دفعة أغسطس 2026' \gset
select id gf20_root from livestock_cohort_state_history
 where cohort_id = :'gf20_cohort' and previous_history_id is null \gset
select id gf20_active from livestock_cohort_state_history
 where cohort_id = :'gf20_cohort' and new_state = 'ACTIVE' \gset

-- A second valid Cohort supplies a distinct causal chain for cross-link tests.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة سلامة ثانية', 'OPENING_BALANCE', date '2026-08-01', 5,
    null, null, null, null, null, null, null, 'gf20-chain-cohort-2'
  )$q$, :'gf20_project', :'gf20_herd', :'gf20_site')) gf20_cohort2 \gset
select id gf20_root2 from livestock_cohort_state_history
 where cohort_id = :'gf20_cohort2' and previous_history_id is null \gset

-- Exactly one root: a valid-looking second root is rejected by the partial unique index.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_cohort_state_history(
    organization_id, project_id, cohort_id, previous_history_id,
    previous_state, new_state, reason, changed_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, null,
    null, 'PLANNED', 'جذر ثان مرفوض',
    '00000000-0000-4000-8000-000000000001', 'gf20-duplicate-root', repeat('a',64)
  )
$q$, :'gf20_project', :'gf20_cohort')) like '%duplicate key%'
then 1 else 0 end as duplicate_root_rejected;

-- Root semantics cannot claim ACTIVE or a previous state.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_cohort_state_history(
    organization_id, project_id, cohort_id, previous_history_id,
    previous_state, new_state, reason, changed_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, null,
    null, 'ACTIVE', 'جذر مشوه مرفوض',
    '00000000-0000-4000-8000-000000000001', 'gf20-malformed-root', repeat('b',64)
  )
$q$, :'gf20_project', :'gf20_cohort2')) like '%root_or_child_check%'
then 1 else 0 end as malformed_root_rejected;

-- A predecessor from another Cohort is rejected before its composite FK can persist.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_cohort_state_history(
    organization_id, project_id, cohort_id, previous_history_id,
    previous_state, new_state, reason, changed_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'ACTIVE', 'ACTIVE', 'ربط عابر للدفعات',
    '00000000-0000-4000-8000-000000000001', 'gf20-cross-cohort', repeat('c',64)
  )
$q$, :'gf20_project', :'gf20_cohort2', :'gf20_active'))
  like '%predecessor must belong to the same cohort%'
then 1 else 0 end as cross_cohort_predecessor_rejected;

-- One predecessor cannot branch to a second child.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_cohort_state_history(
    organization_id, project_id, cohort_id, previous_history_id,
    previous_state, new_state, reason, changed_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'PLANNED', 'ACTIVE', 'فرع ثان مرفوض',
    '00000000-0000-4000-8000-000000000001', 'gf20-branch-child', repeat('d',64)
  )
$q$, :'gf20_project', :'gf20_cohort', :'gf20_root')) like '%duplicate key%'
then 1 else 0 end as branching_rejected;

-- A child must state the actual predecessor state.
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_cohort_state_history(
    organization_id, project_id, cohort_id, previous_history_id,
    previous_state, new_state, reason, changed_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'ACTIVE', 'ACTIVE', 'حالة سابقة غير صحيحة',
    '00000000-0000-4000-8000-000000000001', 'gf20-state-mismatch', repeat('e',64)
  )
$q$, :'gf20_project', :'gf20_cohort2', :'gf20_root2'))
  like '%previous state mismatch%'
then 1 else 0 end as predecessor_state_mismatch_rejected;

-- A multiple-tip attempt through another root is rejected and the resolver sees one tip.
select 1/case when (
  select count(*) from livestock_cohort_state_history h
  where h.cohort_id = :'gf20_cohort'
    and not exists (
      select 1 from livestock_cohort_state_history child
      where child.cohort_id = h.cohort_id and child.previous_history_id = h.id
    )
) = 1 and public.livestock_current_cohort_tip(:'gf20_cohort') = :'gf20_active'
then 1 else 0 end as exactly_one_tip_preserved;

-- GF-020 still permits only PLANNED -> ACTIVE.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    'ACTIVE', 'PLANNED', 'رجوع غير مسموح', null, 'gf20-invalid-backward'
  )
$q$, :'gf20_project', :'gf20_cohort')) like '%invalid livestock cohort transition%'
then 1 else 0 end as invalid_transition_rejected;

-- Replay after state change returns the original transition without history/audit duplication.
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    'PLANNED', 'ACTIVE', 'بدء التشغيل', 'محضر تفعيل', 'gf20-active-001'
  )
$q$, :'gf20_project', :'gf20_cohort')) = :'gf20_active'
then 1 else 0 end as transition_replay_stable;
select 1/case when (
  select count(*) from livestock_cohort_state_history where cohort_id = :'gf20_cohort'
) = 2 and (
  select count(*) from audit_events
  where entity_id = :'gf20_cohort' and event_type = 'LIVESTOCK_COHORT_STATE_CHANGED'
) = 1 then 1 else 0 end as replay_does_not_duplicate_facts;

select 'GF-020 lifecycle chain integrity PASS' result;
