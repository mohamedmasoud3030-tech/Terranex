-- =============================================================================
-- Terranex — Phase 2B — Grants and revokes for ownership domain
-- =============================================================================
-- Same pattern as migration 0006: revoke from anon, grant to authenticated.
-- =============================================================================

revoke all on public.equity_change_events from anon;
revoke all on public.partner_ledger_entries from anon;
revoke all on public.distributions from anon;
revoke all on public.distribution_allocations from anon;

grant select, insert, update, delete on public.equity_change_events to authenticated;
grant select, insert, update, delete on public.partner_ledger_entries to authenticated;
grant select, insert, update, delete on public.distributions to authenticated;
grant select, insert, update, delete on public.distribution_allocations to authenticated;

\echo '=== 2B OWNERSHIP GRANTS: MIGRATION COMPLETE ==='
