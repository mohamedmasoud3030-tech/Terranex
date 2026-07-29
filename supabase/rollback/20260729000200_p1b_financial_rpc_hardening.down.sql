-- =============================================================================
-- ROLLBACK P1B hardening
-- The preceding P1B rollback removes the six RPCs, original helpers and table.
-- This file removes only the additional helper overloads introduced by 00200.
-- =============================================================================

drop function if exists public.terranex_audit_log(uuid, text, text, uuid[], jsonb, jsonb, uuid);
drop function if exists public.terranex_audit_check_idempotent(uuid, uuid);
drop function if exists public.terranex_lock_financial_request(uuid, uuid);
drop function if exists public.terranex_assert_owner(uuid);

\echo '=== ROLLBACK P1B FINANCIAL RPC HARDENING: COMPLETE ==='
