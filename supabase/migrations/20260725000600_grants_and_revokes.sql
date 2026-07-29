-- =============================================================================
-- Terranex — Phase 1A — 0006 — Privileges
-- =============================================================================
-- Terranex has no public/unauthenticated surface: the app requires a Supabase
-- Auth session (src/core/auth/AuthProvider.tsx) before any data is read. So
-- `anon` gets nothing, and `authenticated` gets exactly the DML the stores use.
--
-- Table privileges are the FIRST gate; RLS is the second. A missing GRANT means
-- "no access at all"; RLS then narrows the granted access to owned rows. Both
-- are required — RLS alone does not grant, and a GRANT alone does not scope.
--
-- Non-destructive: privilege changes only, no data touched.
-- =============================================================================

-- ─── revoke the permissive defaults ──────────────────────────────────────────
-- PUBLIC is the implicit grantee on newly created objects in some setups; strip
-- it explicitly rather than assuming the cluster default is tight.
revoke all on all tables    in schema public from public;
revoke all on all functions in schema public from public;
revoke all on all sequences in schema public from public;

-- `anon` is the unauthenticated Supabase role. Terranex has no anonymous
-- surface: no public dashboards, no shared links. It gets nothing.
revoke all on all tables    in schema public from anon;
revoke all on all functions in schema public from anon;
revoke all on all sequences in schema public from anon;

-- ─── grant the authenticated role exactly what the stores need ───────────────
-- createSupabaseStore issues select / insert / update / delete. No TRUNCATE, no
-- REFERENCES, no TRIGGER.
grant select, insert, update, delete on
  public.projects,
  public.partners,
  public.assets,
  public.documents,
  public.project_partners,
  public.transactions,
  public.obligations,
  public.settlements,
  public.settlement_allocations,
  public.operational_events,
  public.stock_adjustments
to authenticated;

-- Schema visibility. Without USAGE the grants above are unreachable.
grant usage on schema public to authenticated;

-- ─── function execution ──────────────────────────────────────────────────────
-- Only the five guards the client actually calls.
revoke all on function public.guard_project_deletion(uuid)     from public, anon;
revoke all on function public.guard_partner_deletion(uuid)     from public, anon;
revoke all on function public.guard_asset_deletion(uuid)       from public, anon;
revoke all on function public.guard_document_deletion(uuid)    from public, anon;
revoke all on function public.guard_transaction_deletion(uuid) from public, anon;

grant execute on function public.guard_project_deletion(uuid)     to authenticated;
grant execute on function public.guard_partner_deletion(uuid)     to authenticated;
grant execute on function public.guard_asset_deletion(uuid)       to authenticated;
grant execute on function public.guard_document_deletion(uuid)    to authenticated;
grant execute on function public.guard_transaction_deletion(uuid) to authenticated;

-- The message-builder helpers are internal. They are called from inside the
-- guards (which run as the invoker), so the caller does need EXECUTE — but
-- anon and PUBLIC must not have it.
revoke all on function public.terranex_block_if(bigint, text)      from public, anon;
revoke all on function public.terranex_guard_result(text[], text)  from public, anon;
grant execute on function public.terranex_block_if(bigint, text)     to authenticated;
grant execute on function public.terranex_guard_result(text[], text) to authenticated;

-- ─── defaults for anything added later ───────────────────────────────────────
-- Without these, a future migration that forgets an explicit GRANT silently
-- creates a table nobody can read, or worse, one PUBLIC can.
alter default privileges in schema public
  revoke all on tables from public, anon;
alter default privileges in schema public
  revoke all on functions from public, anon;
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;

-- NOTE: no sequence grants. Every primary key is a uuid with
-- `default gen_random_uuid()`; there are no serial columns and therefore no
-- sequences to expose.
