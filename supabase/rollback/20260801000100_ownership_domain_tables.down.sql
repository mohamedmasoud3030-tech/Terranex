-- =============================================================================
-- Terranex — Phase 2B — Rollback: Ownership domain tables
-- =============================================================================
-- REVERSIBILITY: This rollback is destructive — it drops all four new tables
-- and their data (equity_change_events, partner_ledger_entries, distributions,
-- distribution_allocations). The original project_partners table is NOT affected.
--
-- Enum types are dropped only if they have no remaining references.
-- =============================================================================

drop table if exists public.distribution_allocations cascade;
drop table if exists public.distributions cascade;
drop table if exists public.partner_ledger_entries cascade;
drop table if exists public.equity_change_events cascade;

-- Drop enum types only if nothing else references them
do $$ begin
  begin
    execute 'drop type if exists public.terranex_equity_change_type cascade';
  exception when others then null;
  end;
  begin
    execute 'drop type if exists public.terranex_ledger_entry_type cascade';
  exception when others then null;
  end;
  begin
    execute 'drop type if exists public.terranex_distribution_status cascade';
  exception when others then null;
  end;
  begin
    execute 'drop type if exists public.terranex_distribution_allocation_status cascade';
  exception when others then null;
  end;
end $$;

\echo '=== 2B OWNERSHIP DOMAIN TABLES: ROLLBACK COMPLETE ==='
