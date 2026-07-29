-- =============================================================================
-- Terranex — Phase P1B — Financial audit foundation
-- =============================================================================
-- Creates the owner-scoped, append-only audit store used by the atomic finance
-- RPC boundary. Function implementations are installed by the next migration.
-- =============================================================================

create table if not exists public.financial_audit_logs (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null,
  operation text not null,
  entity_type text not null,
  entity_ids uuid[] not null default '{}',
  payload jsonb not null default '{}',
  result jsonb not null default '{}',
  owner_id uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  constraint financial_audit_logs_owner_request_unique unique (owner_id, request_id),
  constraint financial_audit_logs_unique_id_owner unique (id, owner_id)
);

create index if not exists idx_financial_audit_logs_request_id
  on public.financial_audit_logs (request_id);
create index if not exists idx_financial_audit_logs_owner_created_at
  on public.financial_audit_logs (owner_id, created_at desc);
create index if not exists idx_financial_audit_logs_operation
  on public.financial_audit_logs (operation);
create index if not exists idx_financial_audit_logs_entity_type
  on public.financial_audit_logs (entity_type);

alter table public.financial_audit_logs enable row level security;
alter table public.financial_audit_logs force row level security;

drop policy if exists financial_audit_logs_select_own on public.financial_audit_logs;
create policy financial_audit_logs_select_own
  on public.financial_audit_logs
  for select
  using (owner_id = auth.uid());

-- No direct INSERT/UPDATE/DELETE policy is created. Successful SECURITY DEFINER
-- RPCs are the only writers, keeping the financial audit trail append-only.
drop policy if exists financial_audit_logs_insert_own on public.financial_audit_logs;
drop policy if exists financial_audit_logs_update_own on public.financial_audit_logs;
drop policy if exists financial_audit_logs_delete_own on public.financial_audit_logs;

revoke all on public.financial_audit_logs from anon;
revoke insert, update, delete on public.financial_audit_logs from authenticated;
grant select on public.financial_audit_logs to authenticated;

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
  union all select 'stock_adjustments',      count(*), count(*) filter (where owner_id is null) from public.stock_adjustments
  union all select 'financial_audit_logs',   count(*), count(*) filter (where owner_id is null) from public.financial_audit_logs;

alter view public.terranex_ownership_preflight set (security_invoker = true);

\echo '=== P1B FINANCIAL AUDIT FOUNDATION: MIGRATION COMPLETE ==='
