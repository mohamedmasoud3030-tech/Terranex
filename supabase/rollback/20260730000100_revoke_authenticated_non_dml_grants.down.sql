-- =============================================================================
-- Rollback — 20260730000100_revoke_authenticated_non_dml_grants
-- =============================================================================
-- Restores the state that existed before the TRUNCATE fix: `authenticated`
-- holding Supabase's default ACL (arwdDxtm) on every table in `public`.
--
-- ⚠️  SECURITY WARNING
-- Applying this rollback REOPENS the vulnerability. TRUNCATE is a table-level
-- operation that bypasses row-level security entirely, so any signed-in user
-- would again be able to wipe every other user's rows — including the
-- append-only financial_audit_logs.
--
-- Only run this if you must reproduce the pre-fix state (e.g. to re-verify the
-- finding). Do not leave a project in this state.
-- =============================================================================

grant select, insert, update, delete, truncate, references, trigger
  on all tables in schema public
  to authenticated;

alter default privileges in schema public
  grant truncate, references, trigger on tables to authenticated;

alter default privileges for role postgres in schema public
  grant truncate, references, trigger on tables to authenticated;
