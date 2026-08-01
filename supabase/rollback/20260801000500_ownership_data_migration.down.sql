-- =============================================================================
-- Terranex — Phase 2B — Rollback: Ownership data migration
-- =============================================================================
-- REVERSIBILITY: Deletes equity_change_events rows created by the data migration
-- (those with reason = 'Initial data migration from existing project_partners').
-- Other equity_change_events rows created by the RPC are NOT affected because
-- the table itself was already dropped by 20260801000100.down.sql.
-- This script is only needed if the RPCs are kept but the migration data removed.
-- =============================================================================

delete from public.equity_change_events
where reason = 'Initial data migration from existing project_partners';

\echo '=== 2B DATA MIGRATION: ROLLBACK COMPLETE ==='
