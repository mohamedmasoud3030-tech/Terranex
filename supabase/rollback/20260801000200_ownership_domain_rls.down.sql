-- =============================================================================
-- Terranex — Phase 2B — Rollback: Ownership domain RLS policies
-- =============================================================================
-- Reverses RLS policies added in the forward migration.
-- Drops RLS enable/force from the four tables (but does not drop the tables).
-- =============================================================================

alter table if exists public.equity_change_events disable row level security;
alter table if exists public.partner_ledger_entries disable row level security;
alter table if exists public.distributions disable row level security;
alter table if exists public.distribution_allocations disable row level security;

\echo '=== 2B OWNERSHIP RLS: ROLLBACK COMPLETE ==='
