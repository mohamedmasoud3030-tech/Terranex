-- =============================================================================
-- ROLLBACK P1B — Financial Atomicity RPCs & Audit Trail
-- =============================================================================
-- Drops all 6 atomic RPCs, 2 helper functions, and the financial_audit_logs
-- table. After this rollback, financeWriteBoundary.ts must revert to the
-- multi-request write pattern (or the app will fail with PGRST202).
-- =============================================================================

-- Drop atomic RPCs
drop function if exists public.record_stock_adjustment_atomic(uuid, jsonb);
drop function if exists public.reverse_settlement_atomic(uuid, uuid, text);
drop function if exists public.record_settlement_atomic(uuid, jsonb, jsonb);
drop function if exists public.delete_transaction_atomic(uuid, uuid);
drop function if exists public.update_transaction_atomic(uuid, uuid, jsonb, jsonb);
drop function if exists public.record_transaction_atomic(uuid, jsonb, jsonb);

-- Drop helper functions
drop function if exists public.terranex_audit_log(uuid, text, text, uuid[], jsonb, jsonb);
drop function if exists public.terranex_audit_check_idempotent(uuid);

-- Drop financial_audit_logs table (cascades indexes, constraints, RLS policies)
drop table if exists public.financial_audit_logs cascade;
