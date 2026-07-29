-- =============================================================================
-- ROLLBACK P1B — Financial atomicity and audit foundation
-- =============================================================================

-- Public RPCs and the private transaction core.
drop function if exists public.record_stock_adjustment_atomic(uuid, jsonb);
drop function if exists public.reverse_settlement_atomic(uuid, uuid, text);
drop function if exists public.record_settlement_atomic(uuid, jsonb, jsonb);
drop function if exists public.delete_transaction_atomic(uuid, uuid);
drop function if exists public.update_transaction_atomic(uuid, uuid, jsonb, jsonb);
drop function if exists public.record_transaction_atomic(uuid, jsonb, jsonb);
drop function if exists public.record_transaction_atomic_core(uuid, jsonb, jsonb);

-- Internal ownership, locking, idempotency and audit helpers.
drop function if exists public.terranex_audit_log(uuid, text, text, uuid[], jsonb, jsonb, uuid);
drop function if exists public.terranex_audit_log(uuid, text, text, uuid[], jsonb, jsonb);
drop function if exists public.terranex_audit_check_idempotent(uuid, uuid);
drop function if exists public.terranex_audit_check_idempotent(uuid);
drop function if exists public.terranex_lock_financial_request(uuid, uuid);
drop function if exists public.terranex_assert_owner(uuid);

drop table if exists public.financial_audit_logs cascade;

create or replace view public.terranex_ownership_preflight as
  select 'projects'::text as table_name,
         count(*) as total_rows,
         count(*) filter (where owner_id is null) as unowned_rows
    from public.projects
  union all select 'partners',               count(*), count(*) filter (where owner_id is null) from public.partners
  union all select 'assets',                 count(*), count(*) filter (where owner_id is null) from public.assets
  union all select 'documents',              count(*), count(*) filter (where owner_id is null) from public.documents
  union all select 'project_partners',       count(*), count(*) filter (where owner_id is null) from public.project_partners
  union all select 'transactions',           count(*), count(*) filter (where owner_id is null) from public.transactions
  union all select 'obligations',            count(*), count(*) filter (where owner_id is null) from public.obligations
  union all select 'settlements',            count(*), count(*) filter (where owner_id is null) from public.settlements
  union all select 'settlement_allocations', count(*), count(*) filter (where owner_id is null) from public.settlement_allocations
  union all select 'operational_events',     count(*), count(*) filter (where owner_id is null) from public.operational_events
  union all select 'stock_adjustments',      count(*), count(*) filter (where owner_id is null) from public.stock_adjustments;

alter view public.terranex_ownership_preflight set (security_invoker = true);

\echo '=== ROLLBACK P1B FINANCIAL ATOMICITY: COMPLETE ==='
