-- =============================================================================
-- Terranex — Phase 2B — Non-destructive data migration
-- =============================================================================
-- Preserves all existing project_partners records and creates initial
-- equity_change_events for each one. No data is modified or deleted.
--
-- Diagnostic checks run BEFORE the migration to detect invalid data.
-- If invalid data is found, the migration halts with a clear diagnostic message.
-- =============================================================================

-- ─── Diagnostic preflight ────────────────────────────────────────────────────
-- Check for data integrity issues before migration.

do $preflight$
declare
  v_duplicate_count int;
  v_overlap_count int;
  v_over_100_count int;
begin
  -- Check 1: Duplicate active records (same project+partner, both active)
  select count(*) into v_duplicate_count
  from (
    select project_id, partner_id, count(*) as cnt
    from public.project_partners
    where effective_to is null
    group by project_id, partner_id
    having count(*) > 1
  ) duplicates;

  if v_duplicate_count > 0 then
    raise exception using errcode = '23514',
      message = format(
        'DATA MIGRATION BLOCKED: found %s projects with duplicate active ownership records for the same partner. Manual cleanup required before migration.',
        v_duplicate_count
      );
  end if;

  -- Check 2: Overlapping periods for same project+partner
  select count(*) into v_overlap_count
  from public.project_partners pp1
  join public.project_partners pp2
    on pp1.project_id = pp2.project_id
    and pp1.partner_id = pp2.partner_id
    and pp1.owner_id = pp2.owner_id
    and pp1.id < pp2.id
  where (pp1.effective_to is null or pp1.effective_to >= pp2.effective_from)
    and (pp2.effective_to is null or pp2.effective_to >= pp1.effective_from);

  if v_overlap_count > 0 then
    raise exception using errcode = '23514',
      message = format(
        'DATA MIGRATION BLOCKED: found %s overlapping ownership periods for the same project+partner. Manual cleanup required.',
        v_overlap_count
      );
  end if;

  -- Check 3: Projects where active equity sum exceeds 100%
  select count(*) into v_over_100_count
  from (
    select project_id, sum(equity_pct) as total_pct
    from public.project_partners
    where effective_to is null
    group by project_id
    having sum(equity_pct) > 100.0001
  ) over_allocated;

  if v_over_100_count > 0 then
    raise exception using errcode = '23514',
      message = format(
        'DATA MIGRATION BLOCKED: found %s projects where active equity exceeds 100%%. Manual correction required.',
        v_over_100_count
      );
  end if;

  raise notice 'DATA PREFLIGHT: all checks passed — % duplicates, % overlaps, % over-allocated',
    v_duplicate_count, v_overlap_count, v_over_100_count;
end;
$preflight$;

-- ─── Create initial equity_change_events from existing project_partners ─────
-- This is append-only: we only INSERT new records, never modify existing ones.

insert into public.equity_change_events (
  owner_id, project_id, partner_id, effective_date,
  previous_pct, new_pct, change_type, reason, created_by
)
select
  pp.owner_id,
  pp.project_id,
  pp.partner_id,
  pp.effective_from,
  0 as previous_pct,
  pp.equity_pct as new_pct,
  'entry'::public.terranex_equity_change_type as change_type,
  'Initial data migration from existing project_partners' as reason,
  pp.owner_id as created_by
from public.project_partners pp
where not exists (
  select 1 from public.equity_change_events ece
  where ece.project_id = pp.project_id
    and ece.partner_id = pp.partner_id
    and ece.effective_date = pp.effective_from
    and ece.owner_id = pp.owner_id
);

\echo '=== 2B DATA MIGRATION: COMPLETE ==='
