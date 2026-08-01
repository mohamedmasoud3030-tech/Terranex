-- =============================================================================
-- Terranex — Phase 2B — Rollback: Ownership domain RPCs
-- =============================================================================
-- Drops all ownership-domain RPCs added in the forward migration.
-- =============================================================================

drop function if exists public.change_ownership_atomic(uuid, uuid, uuid, date, numeric, public.terranex_equity_change_type, numeric, public.terranex_currency, uuid, text, text);
drop function if exists public.record_distribution_atomic(uuid, uuid, date, date, numeric, public.terranex_currency, numeric, text, uuid);
drop function if exists public.record_partner_ledger_entry_atomic(uuid, uuid, uuid, public.terranex_ledger_entry_type, numeric, public.terranex_currency, numeric, date, uuid, uuid, uuid, text, uuid);
drop function if exists public.get_ownership_as_of(uuid, date);

\echo '=== 2B OWNERSHIP RPCs: ROLLBACK COMPLETE ==='
