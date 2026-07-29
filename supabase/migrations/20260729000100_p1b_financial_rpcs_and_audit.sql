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

-- Explicit deny policies satisfy the shared four-operation RLS contract while
-- preserving append-only semantics. Table mutation privileges are also revoked.
drop policy if exists financial_audit_logs_insert_own on public.financial_audit_logs;
create policy financial_audit_logs_insert_own
  on public.financial_audit_logs
  for insert
  with check (false);

drop policy if exists financial_audit_logs_update_own on public.financial_audit_logs;
create policy financial_audit_logs_update_own
  on public.financial_audit_logs
  for update
  using (false)
  with check (false);

drop policy if exists financial_audit_logs_delete_own on public.financial_audit_logs;
create policy financial_audit_logs_delete_own
  on public.financial_audit_logs
  for delete
  using (false);

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

-- Compatibility signatures exist before the RPC migration revokes their public
-- execution. The replay layer replaces the one-argument lookup and removes the
-- obsolete six-argument writer once all final helpers are installed.
create or replace function public.terranex_audit_check_idempotent(p_request_id uuid)
returns jsonb
language sql
security definer
set search_path = public
stable
as $fn$
  select result
  from public.financial_audit_logs
  where request_id = p_request_id
    and (auth.uid() is null or owner_id = auth.uid())
  order by owner_id
  limit 1;
$fn$;

create or replace function public.terranex_audit_log(
  p_request_id uuid,
  p_operation text,
  p_entity_type text,
  p_entity_ids uuid[],
  p_payload jsonb,
  p_result jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  raise exception using
    errcode = '42501',
    message = 'legacy audit writer is disabled; use the owner-scoped RPC boundary';
end;
$fn$;

revoke execute on function public.terranex_audit_check_idempotent(uuid)
  from public, anon, authenticated;
revoke execute on function public.terranex_audit_log(uuid, text, text, uuid[], jsonb, jsonb)
  from public, anon, authenticated;

\echo '=== P1B FINANCIAL AUDIT FOUNDATION: MIGRATION COMPLETE ==='
