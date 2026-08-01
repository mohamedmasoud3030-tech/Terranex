-- =============================================================================
-- Terranex — Phase 2B — Rollback: Ownership domain grants
-- =============================================================================
-- Reverses grants added in the forward migration.
-- =============================================================================

revoke all on public.equity_change_events from authenticated;
revoke all on public.partner_ledger_entries from authenticated;
revoke all on public.distributions from authenticated;
revoke all on public.distribution_allocations from authenticated;

\echo '=== 2B OWNERSHIP GRANTS: ROLLBACK COMPLETE ==='
