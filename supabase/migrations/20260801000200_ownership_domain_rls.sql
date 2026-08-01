-- =============================================================================
-- Terranex — Phase 2B — RLS policies for ownership domain
-- =============================================================================
-- Same pattern as migration 0004: enable + force RLS, four policies per table
-- (select, insert, update, delete), all using owner_id = auth.uid().
-- =============================================================================

-- ─── equity_change_events ────────────────────────────────────────────────────
alter table public.equity_change_events enable row level security;
alter table public.equity_change_events force row level security;

drop policy if exists equity_change_events_select_own on public.equity_change_events;
create policy equity_change_events_select_own on public.equity_change_events
  for select using ((select auth.uid()) = owner_id);

drop policy if exists equity_change_events_insert_own on public.equity_change_events;
create policy equity_change_events_insert_own on public.equity_change_events
  for insert with check ((select auth.uid()) = owner_id);

drop policy if exists equity_change_events_update_own on public.equity_change_events;
create policy equity_change_events_update_own on public.equity_change_events
  for update using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

drop policy if exists equity_change_events_delete_own on public.equity_change_events;
create policy equity_change_events_delete_own on public.equity_change_events
  for delete using ((select auth.uid()) = owner_id);

-- ─── partner_ledger_entries ──────────────────────────────────────────────────
alter table public.partner_ledger_entries enable row level security;
alter table public.partner_ledger_entries force row level security;

drop policy if exists partner_ledger_entries_select_own on public.partner_ledger_entries;
create policy partner_ledger_entries_select_own on public.partner_ledger_entries
  for select using ((select auth.uid()) = owner_id);

drop policy if exists partner_ledger_entries_insert_own on public.partner_ledger_entries;
create policy partner_ledger_entries_insert_own on public.partner_ledger_entries
  for insert with check ((select auth.uid()) = owner_id);

drop policy if exists partner_ledger_entries_update_own on public.partner_ledger_entries;
create policy partner_ledger_entries_update_own on public.partner_ledger_entries
  for update using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

drop policy if exists partner_ledger_entries_delete_own on public.partner_ledger_entries;
create policy partner_ledger_entries_delete_own on public.partner_ledger_entries
  for delete using ((select auth.uid()) = owner_id);

-- ─── distributions ───────────────────────────────────────────────────────────
alter table public.distributions enable row level security;
alter table public.distributions force row level security;

drop policy if exists distributions_select_own on public.distributions;
create policy distributions_select_own on public.distributions
  for select using ((select auth.uid()) = owner_id);

drop policy if exists distributions_insert_own on public.distributions;
create policy distributions_insert_own on public.distributions
  for insert with check ((select auth.uid()) = owner_id);

drop policy if exists distributions_update_own on public.distributions;
create policy distributions_update_own on public.distributions
  for update using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

drop policy if exists distributions_delete_own on public.distributions;
create policy distributions_delete_own on public.distributions
  for delete using ((select auth.uid()) = owner_id);

-- ─── distribution_allocations ────────────────────────────────────────────────
alter table public.distribution_allocations enable row level security;
alter table public.distribution_allocations force row level security;

drop policy if exists distribution_allocations_select_own on public.distribution_allocations;
create policy distribution_allocations_select_own on public.distribution_allocations
  for select using ((select auth.uid()) = owner_id);

drop policy if exists distribution_allocations_insert_own on public.distribution_allocations;
create policy distribution_allocations_insert_own on public.distribution_allocations
  for insert with check ((select auth.uid()) = owner_id);

drop policy if exists distribution_allocations_update_own on public.distribution_allocations;
create policy distribution_allocations_update_own on public.distribution_allocations
  for update using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

drop policy if exists distribution_allocations_delete_own on public.distribution_allocations;
create policy distribution_allocations_delete_own on public.distribution_allocations
  for delete using ((select auth.uid()) = owner_id);

\echo '=== 2B OWNERSHIP RLS POLICIES: MIGRATION COMPLETE ==='
