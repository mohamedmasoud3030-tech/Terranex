-- =============================================================================
-- Terranex — revoke non-DML privileges from `authenticated`
-- =============================================================================
-- 20260725000600 states the intent plainly:
--
--     "createSupabaseStore issues select / insert / update / delete.
--      No TRUNCATE, no REFERENCES, no TRIGGER."
--
-- It revokes from PUBLIC and anon, but never from `authenticated`. Supabase's
-- default ACL (authenticated=arwdDxtm) is applied at CREATE TABLE time, so the
-- later GRANT only adds — it removes nothing. The result is that every signed-in
-- user holds TRUNCATE, REFERENCES and TRIGGER on all 12 tables and the
-- preflight view.
--
-- TRUNCATE is the dangerous one: it is a table-level operation and does NOT go
-- through row-level security. RLS constrains DELETE row by row, but TRUNCATE
-- bypasses policies entirely, letting any authenticated user wipe every other
-- user's rows — including the append-only financial_audit_logs.
--
-- This migration revokes everything from `authenticated`, then re-grants exactly
-- the DML each store needs, preserving the current shape:
--   - 11 operational tables : SELECT, INSERT, UPDATE, DELETE
--   - financial_audit_logs  : SELECT only (append-only; writes go through the
--                             SECURITY DEFINER audit function)
--   - terranex_ownership_preflight (view) : SELECT only (read-only diagnostic)
--
-- It also fixes ALTER DEFAULT PRIVILEGES so tables created later do not
-- reintroduce the same hole.
--
-- Idempotent: safe to re-run. No data is touched.
-- =============================================================================

-- ─── 1. strip every privilege currently held by `authenticated` ──────────────
revoke all on all tables    in schema public from authenticated;
revoke all on all sequences in schema public from authenticated;

-- ─── 2. re-grant exactly the DML the stores issue ────────────────────────────
-- Mirrors the grant list in 20260725000600 (11 operational tables).
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

-- ─── 3. append-only audit trail: read access only ────────────────────────────
-- Rows are written by public.terranex_audit_log (security definer). The RLS
-- policies already pin INSERT/UPDATE/DELETE to `false`; removing the table
-- privilege makes that a two-layer guarantee rather than policy-only.
grant select on public.financial_audit_logs to authenticated;

-- ─── 4. read-only diagnostic view ────────────────────────────────────────────
grant select on public.terranex_ownership_preflight to authenticated;

-- ─── 5. schema visibility (revoked in step 1 if it had been granted here) ────
grant usage on schema public to authenticated;

-- ─── 6. stop future tables from inheriting the hole ──────────────────────────
-- Supabase's default ACL grants arwdDxtm to authenticated on new tables. Strip
-- the three non-DML bits for both role grantors that own defaults in this
-- schema, so a table added by a later migration is safe by construction.
alter default privileges in schema public
  revoke truncate, references, trigger on tables from authenticated;

alter default privileges for role postgres in schema public
  revoke truncate, references, trigger on tables from authenticated;

-- =============================================================================
-- Verification (expects zero rows):
--
--   select table_name, privilege_type
--   from information_schema.role_table_grants
--   where table_schema = 'public'
--     and grantee = 'authenticated'
--     and privilege_type not in ('SELECT','INSERT','UPDATE','DELETE');
-- =============================================================================
