-- =============================================================================
-- Terranex — Phase 1A — 0004 — Row Level Security
-- =============================================================================
-- One policy set per table. Every table is reached through exactly one write
-- path (`createSupabaseStore`), proven by `grep -rn "\.from(" src/` returning no
-- direct table access outside the factory — so this is the complete surface.
--
-- Policy form is mandated by the owner decision:
--     USING      ((select auth.uid()) = owner_id)
--     WITH CHECK ((select auth.uid()) = owner_id)
--
-- `(select auth.uid())` rather than bare `auth.uid()`: the scalar sub-select is
-- evaluated once per statement instead of once per row (initplan caching).
-- On a 10k-row hydrate that is the difference between one call and 10k.
--
-- Why WITH CHECK stops owner_id spoofing:
--   INSERT with a forged owner_id fails WITH CHECK, because the row's owner_id
--   is compared to the caller's uid AFTER defaults are applied.
--   UPDATE is checked twice — USING against the existing row (you may only
--   touch rows you own) and WITH CHECK against the new row (you may not hand a
--   row to someone else). Both directions are therefore closed.
--
-- Cross-tenant references are already impossible via the composite FKs in 0002;
-- RLS is the second, independent layer. Neither relies on a join.
--
-- FORCE ROW LEVEL SECURITY: without it the table owner role bypasses RLS.
-- Non-destructive: enables RLS and creates policies only.
-- =============================================================================

-- ─── projects ────────────────────────────────────────────────────────────────
alter table public.projects enable row level security;
alter table public.projects force row level security;

create policy projects_select on public.projects
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy projects_insert on public.projects
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy projects_update on public.projects
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy projects_delete on public.projects
  for delete to authenticated using ((select auth.uid()) = owner_id);

-- ─── partners ────────────────────────────────────────────────────────────────
alter table public.partners enable row level security;
alter table public.partners force row level security;

create policy partners_select on public.partners
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy partners_insert on public.partners
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy partners_update on public.partners
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy partners_delete on public.partners
  for delete to authenticated using ((select auth.uid()) = owner_id);

-- ─── assets ──────────────────────────────────────────────────────────────────
alter table public.assets enable row level security;
alter table public.assets force row level security;

create policy assets_select on public.assets
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy assets_insert on public.assets
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy assets_update on public.assets
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy assets_delete on public.assets
  for delete to authenticated using ((select auth.uid()) = owner_id);

-- ─── documents ───────────────────────────────────────────────────────────────
alter table public.documents enable row level security;
alter table public.documents force row level security;

create policy documents_select on public.documents
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy documents_insert on public.documents
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy documents_update on public.documents
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy documents_delete on public.documents
  for delete to authenticated using ((select auth.uid()) = owner_id);

-- ─── project_partners ────────────────────────────────────────────────────────
alter table public.project_partners enable row level security;
alter table public.project_partners force row level security;

create policy project_partners_select on public.project_partners
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy project_partners_insert on public.project_partners
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy project_partners_update on public.project_partners
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy project_partners_delete on public.project_partners
  for delete to authenticated using ((select auth.uid()) = owner_id);

-- ─── transactions ────────────────────────────────────────────────────────────
alter table public.transactions enable row level security;
alter table public.transactions force row level security;

create policy transactions_select on public.transactions
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy transactions_insert on public.transactions
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy transactions_update on public.transactions
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy transactions_delete on public.transactions
  for delete to authenticated using ((select auth.uid()) = owner_id);

-- ─── obligations ─────────────────────────────────────────────────────────────
alter table public.obligations enable row level security;
alter table public.obligations force row level security;

create policy obligations_select on public.obligations
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy obligations_insert on public.obligations
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy obligations_update on public.obligations
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy obligations_delete on public.obligations
  for delete to authenticated using ((select auth.uid()) = owner_id);

-- ─── settlements ─────────────────────────────────────────────────────────────
alter table public.settlements enable row level security;
alter table public.settlements force row level security;

create policy settlements_select on public.settlements
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy settlements_insert on public.settlements
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy settlements_update on public.settlements
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy settlements_delete on public.settlements
  for delete to authenticated using ((select auth.uid()) = owner_id);

-- ─── settlement_allocations ──────────────────────────────────────────────────
alter table public.settlement_allocations enable row level security;
alter table public.settlement_allocations force row level security;

create policy settlement_allocations_select on public.settlement_allocations
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy settlement_allocations_insert on public.settlement_allocations
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy settlement_allocations_update on public.settlement_allocations
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy settlement_allocations_delete on public.settlement_allocations
  for delete to authenticated using ((select auth.uid()) = owner_id);

-- ─── operational_events ──────────────────────────────────────────────────────
alter table public.operational_events enable row level security;
alter table public.operational_events force row level security;

create policy operational_events_select on public.operational_events
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy operational_events_insert on public.operational_events
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy operational_events_update on public.operational_events
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy operational_events_delete on public.operational_events
  for delete to authenticated using ((select auth.uid()) = owner_id);

-- ─── stock_adjustments ───────────────────────────────────────────────────────
alter table public.stock_adjustments enable row level security;
alter table public.stock_adjustments force row level security;

create policy stock_adjustments_select on public.stock_adjustments
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy stock_adjustments_insert on public.stock_adjustments
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy stock_adjustments_update on public.stock_adjustments
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy stock_adjustments_delete on public.stock_adjustments
  for delete to authenticated using ((select auth.uid()) = owner_id);
