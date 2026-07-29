-- =============================================================================
-- Terranex — Phase 1B — Financial Atomicity RPCs & Audit Trail
-- =============================================================================
-- Introduces the financial_audit_logs table and 6 atomic RPCs that replace the
-- multi-request write patterns in financeWriteBoundary.ts. Each RPC wraps the
-- full write graph in a single Postgres transaction, preventing partial state
-- and providing idempotency via request_id.
--
-- Idempotency contract: every RPC accepts a p_request_id parameter. If a row
-- with that request_id already exists in financial_audit_logs, the RPC returns
-- the cached result without re-executing. This prevents double-click and
-- network-retry from creating duplicate financial effects.
--
-- Audit contract: every successful write logs to financial_audit_logs with the
-- request_id, operation type, affected entity IDs, and a JSON snapshot of the
-- write payload. This provides a complete financial audit trail independent of
-- the operational tables.
-- =============================================================================

-- ── financial_audit_logs table ──────────────────────────────────────────────
-- Append-Only: no UPDATE or DELETE allowed via RLS policies
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
  constraint financial_audit_logs_request_id_unique unique (request_id)
);

-- owner_id NOT NULL + DEFAULT auth.uid() — matches the 11-table contract
-- UNIQUE(id, owner_id) — enables composite FKs if needed later
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'financial_audit_logs_unique_id_owner'
  ) then
    alter table public.financial_audit_logs
      add constraint financial_audit_logs_unique_id_owner unique (id, owner_id);
  end if;
end $$;

-- Indexes for audit queries
create index if not exists idx_financial_audit_logs_request_id
  on public.financial_audit_logs (request_id);
create index if not exists idx_financial_audit_logs_operation
  on public.financial_audit_logs (operation);
create index if not exists idx_financial_audit_logs_entity_type
  on public.financial_audit_logs (entity_type);
create index if not exists idx_financial_audit_logs_created_at
  on public.financial_audit_logs (created_at desc);

-- ── RLS for financial_audit_logs (Append-Only: SELECT + INSERT only) ─────────
alter table public.financial_audit_logs enable row level security;
alter table public.financial_audit_logs force row level security;

drop policy if exists financial_audit_logs_select_own on public.financial_audit_logs;
create policy financial_audit_logs_select_own
  on public.financial_audit_logs for select
  using (owner_id = auth.uid());

drop policy if exists financial_audit_logs_insert_own on public.financial_audit_logs;
create policy financial_audit_logs_insert_own
  on public.financial_audit_logs for insert
  with check (owner_id = auth.uid());

-- Audit trail is append-only: update and delete policies reject all rows.
-- The RPCs use `security definer` to bypass RLS for INSERT.
drop policy if exists financial_audit_logs_update_own on public.financial_audit_logs;
create policy financial_audit_logs_update_own
  on public.financial_audit_logs for update
  using (false)
  with check (false);

drop policy if exists financial_audit_logs_delete_own on public.financial_audit_logs;
create policy financial_audit_logs_delete_own
  on public.financial_audit_logs for delete
  using (false);

-- ── Grants (Append-Only: SELECT + INSERT only) ──────────────────────────────
grant select, insert on public.financial_audit_logs to authenticated;
revoke all on public.financial_audit_logs from anon;

-- ── Update preflight view to include financial_audit_logs ───────────────────
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

-- ── Helper: idempotency check ───────────────────────────────────────────────
create or replace function public.terranex_audit_check_idempotent(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_cached jsonb;
begin
  select result into v_cached
  from public.financial_audit_logs
  where request_id = p_request_id
  limit 1;
  
  return v_cached;
end;
$fn$;

-- ── Helper: audit log insert ────────────────────────────────────────────────
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
  insert into public.financial_audit_logs (
    request_id, operation, entity_type, entity_ids, payload, result
  ) values (
    p_request_id, p_operation, p_entity_type, p_entity_ids, p_payload, p_result
  );
end;
$fn$;

-- ── RPC 1: record_transaction_atomic ────────────────────────────────────────
create or replace function public.record_transaction_atomic(
  p_request_id uuid,
  p_transaction jsonb,
  p_payable jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_cached jsonb;
  v_transaction_id uuid;
  v_payable_id uuid;
  v_result jsonb;
begin
  -- Idempotency check
  v_cached := public.terranex_audit_check_idempotent(p_request_id);
  if v_cached is not null then
    return v_cached;
  end if;

  -- Insert transaction
  insert into public.transactions (
    id, project_id, asset_id, partner_id, operational_event_id,
    direction, category, description, amount, currency, fx_rate, amount_egp,
    transaction_date, document_id, notes, owner_id
  )
  select
    (p_transaction->>'id')::uuid,
    (p_transaction->>'project_id')::uuid,
    (p_transaction->>'asset_id')::uuid,
    (p_transaction->>'partner_id')::uuid,
    (p_transaction->>'operational_event_id')::uuid,
    (p_transaction->>'direction')::public.terranex_transaction_direction,
    p_transaction->>'category',
    p_transaction->>'description',
    (p_transaction->>'amount')::numeric,
    (p_transaction->>'currency')::public.terranex_currency,
    (p_transaction->>'fx_rate')::numeric,
    (p_transaction->>'amount_egp')::numeric,
    (p_transaction->>'transaction_date')::date,
    (p_transaction->>'document_id')::uuid,
    p_transaction->>'notes',
    auth.uid()
  returning id into v_transaction_id;

  -- Insert payable obligation if provided
  if p_payable is not null then
    insert into public.obligations (
      id, project_id, partner_id, direction, amount, currency, amount_egp,
      amount_settled_egp, due_date, status, source_transaction_id,
      document_id, notes, owner_id
    )
    select
      (p_payable->>'id')::uuid,
      (p_payable->>'project_id')::uuid,
      (p_payable->>'partner_id')::uuid,
      'payable'::public.terranex_obligation_direction,
      (p_payable->>'amount')::numeric,
      (p_payable->>'currency')::public.terranex_currency,
      (p_payable->>'amount_egp')::numeric,
      0,
      (p_payable->>'due_date')::date,
      'open'::public.terranex_obligation_status,
      v_transaction_id,
      (p_payable->>'document_id')::uuid,
      p_payable->>'notes',
      auth.uid()
    returning id into v_payable_id;
  end if;

  -- Build result
  v_result := jsonb_build_object(
    'transaction_id', v_transaction_id,
    'payable_id', v_payable_id
  );

  -- Audit log
  perform public.terranex_audit_log(
    p_request_id,
    'record_transaction',
    'transaction',
    case when v_payable_id is not null then array[v_transaction_id, v_payable_id] else array[v_transaction_id] end,
    p_transaction,
    v_result
  );

  return v_result;
end;
$fn$;

-- ── RPC 2: update_transaction_atomic ────────────────────────────────────────
create or replace function public.update_transaction_atomic(
  p_request_id uuid,
  p_transaction_id uuid,
  p_updates jsonb,
  p_payable_updates jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_cached jsonb;
  v_result jsonb;
  v_payable_id uuid;
begin
  -- Idempotency check
  v_cached := public.terranex_audit_check_idempotent(p_request_id);
  if v_cached is not null then
    return v_cached;
  end if;

  -- Update transaction (dynamic SET via jsonb)
  execute format(
    'update public.transactions set %s where id = $1 and owner_id = auth.uid()',
    (
      select string_agg(
        format('%I = $2->>%L', key, key),
        ', '
      )
      from jsonb_object_keys(p_updates) as key
    )
  ) using p_transaction_id, p_updates;

  -- Update linked payable if provided
  if p_payable_updates is not null then
    select id into v_payable_id
    from public.obligations
    where source_transaction_id = p_transaction_id
      and direction = 'payable'
      and owner_id = auth.uid()
    limit 1;

    if v_payable_id is not null then
      execute format(
        'update public.obligations set %s where id = $1 and owner_id = auth.uid()',
        (
          select string_agg(
            format('%I = $2->>%L', key, key),
            ', '
          )
          from jsonb_object_keys(p_payable_updates) as key
        )
      ) using v_payable_id, p_payable_updates;
    end if;
  end if;

  v_result := jsonb_build_object(
    'transaction_id', p_transaction_id,
    'payable_id', v_payable_id
  );

  perform public.terranex_audit_log(
    p_request_id,
    'update_transaction',
    'transaction',
    case when v_payable_id is not null then array[p_transaction_id, v_payable_id] else array[p_transaction_id] end,
    p_updates,
    v_result
  );

  return v_result;
end;
$fn$;

-- ── RPC 3: delete_transaction_atomic ────────────────────────────────────────
create or replace function public.delete_transaction_atomic(
  p_request_id uuid,
  p_transaction_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_cached jsonb;
  v_payable_ids uuid[];
  v_result jsonb;
begin
  -- Idempotency check
  v_cached := public.terranex_audit_check_idempotent(p_request_id);
  if v_cached is not null then
    return v_cached;
  end if;

  -- Collect linked payables
  select array_agg(id) into v_payable_ids
  from public.obligations
  where source_transaction_id = p_transaction_id
    and direction = 'payable'
    and owner_id = auth.uid();

  -- Delete linked payables
  if v_payable_ids is not null and array_length(v_payable_ids, 1) > 0 then
    delete from public.obligations
    where id = any(v_payable_ids) and owner_id = auth.uid();
  end if;

  -- Delete transaction
  delete from public.transactions
  where id = p_transaction_id and owner_id = auth.uid();

  v_result := jsonb_build_object(
    'transaction_id', p_transaction_id,
    'deleted_payable_ids', coalesce(v_payable_ids, '{}')
  );

  perform public.terranex_audit_log(
    p_request_id,
    'delete_transaction',
    'transaction',
    array[p_transaction_id] || coalesce(v_payable_ids, '{}'),
    jsonb_build_object('transaction_id', p_transaction_id),
    v_result
  );

  return v_result;
end;
$fn$;

-- ── RPC 4: record_settlement_atomic ─────────────────────────────────────────
create or replace function public.record_settlement_atomic(
  p_request_id uuid,
  p_settlement jsonb,
  p_allocations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_cached jsonb;
  v_settlement_id uuid;
  v_allocation_ids uuid[];
  v_obligation_ids uuid[];
  v_allocation jsonb;
  v_allocation_id uuid;
  v_result jsonb;
begin
  -- Idempotency check
  v_cached := public.terranex_audit_check_idempotent(p_request_id);
  if v_cached is not null then
    return v_cached;
  end if;

  -- Insert settlement (matching actual schema columns)
  insert into public.settlements (
    id, obligation_id, amount, currency, fx_rate, amount_egp,
    settlement_date, payment_method, reference_number,
    receipt_document_id, notes, status, origin, owner_id
  )
  select
    (p_settlement->>'id')::uuid,
    (p_settlement->>'obligation_id')::uuid,
    (p_settlement->>'amount')::numeric,
    (p_settlement->>'currency')::public.terranex_currency,
    (p_settlement->>'fx_rate')::numeric,
    (p_settlement->>'amount_egp')::numeric,
    (p_settlement->>'settlement_date')::date,
    (p_settlement->>'payment_method')::public.terranex_settlement_payment_method,
    p_settlement->>'reference_number',
    (p_settlement->>'receipt_document_id')::uuid,
    p_settlement->>'notes',
    'active'::public.terranex_settlement_status,
    'user'::public.terranex_settlement_origin,
    auth.uid()
  returning id into v_settlement_id;

  -- Insert allocations
  for v_allocation in select * from jsonb_array_elements(p_allocations) loop
    insert into public.settlement_allocations (
      id, settlement_id, obligation_id, allocated_amount_egp, owner_id
    )
    select
      (v_allocation->>'id')::uuid,
      v_settlement_id,
      (v_allocation->>'obligation_id')::uuid,
      (v_allocation->>'allocated_amount_egp')::numeric,
      auth.uid()
    returning id into v_allocation_id;
    
    v_allocation_ids := array_append(v_allocation_ids, v_allocation_id);
    v_obligation_ids := array_append(v_obligation_ids, (v_allocation->>'obligation_id')::uuid);

    -- Update obligation settled amount and status
    update public.obligations
    set amount_settled_egp = amount_settled_egp + (v_allocation->>'allocated_amount_egp')::numeric,
        status = case
          when amount_settled_egp + (v_allocation->>'allocated_amount_egp')::numeric >= amount_egp then 'settled'::public.terranex_obligation_status
          when amount_settled_egp + (v_allocation->>'allocated_amount_egp')::numeric > 0 then 'partial'::public.terranex_obligation_status
          else status
        end,
        updated_at = now()
    where id = (v_allocation->>'obligation_id')::uuid and owner_id = auth.uid();
  end loop;

  v_result := jsonb_build_object(
    'settlement_id', v_settlement_id,
    'allocation_ids', coalesce(v_allocation_ids, '{}'),
    'obligation_ids', coalesce(v_obligation_ids, '{}')
  );

  perform public.terranex_audit_log(
    p_request_id,
    'record_settlement',
    'settlement',
    array[v_settlement_id] || coalesce(v_allocation_ids, '{}'),
    p_settlement,
    v_result
  );

  return v_result;
end;
$fn$;

-- ── RPC 5: reverse_settlement_atomic ────────────────────────────────────────
create or replace function public.reverse_settlement_atomic(
  p_request_id uuid,
  p_settlement_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_cached jsonb;
  v_obligation_ids uuid[];
  v_result jsonb;
  v_allocation record;
  v_now timestamptz := now();
begin
  -- Idempotency check
  v_cached := public.terranex_audit_check_idempotent(p_request_id);
  if v_cached is not null then
    return v_cached;
  end if;

  -- Mark settlement as reversed (satisfies CHECK: status='reversed' requires reversed_at + reversal_reason)
  update public.settlements
  set status = 'reversed'::public.terranex_settlement_status,
      reversed_at = v_now,
      reversal_reason = p_reason,
      updated_at = v_now
  where id = p_settlement_id and owner_id = auth.uid();

  -- Reverse allocations and update obligations
  for v_allocation in
    select obligation_id, allocated_amount_egp
    from public.settlement_allocations
    where settlement_id = p_settlement_id and owner_id = auth.uid()
  loop
    v_obligation_ids := array_append(v_obligation_ids, v_allocation.obligation_id);

    update public.obligations
    set amount_settled_egp = greatest(0, amount_settled_egp - v_allocation.allocated_amount_egp),
        status = case
          when greatest(0, amount_settled_egp - v_allocation.allocated_amount_egp) = 0 then 'open'::public.terranex_obligation_status
          when greatest(0, amount_settled_egp - v_allocation.allocated_amount_egp) < amount_egp then 'partial'::public.terranex_obligation_status
          else status
        end,
        updated_at = v_now
    where id = v_allocation.obligation_id and owner_id = auth.uid();
  end loop;

  v_result := jsonb_build_object(
    'settlement_id', p_settlement_id,
    'reversed_obligation_ids', coalesce(v_obligation_ids, '{}'),
    'reason', p_reason,
    'reversed_at', v_now
  );

  perform public.terranex_audit_log(
    p_request_id,
    'reverse_settlement',
    'settlement',
    array[p_settlement_id] || coalesce(v_obligation_ids, '{}'),
    jsonb_build_object('settlement_id', p_settlement_id, 'reason', p_reason),
    v_result
  );

  return v_result;
end;
$fn$;

-- ── RPC 6: record_stock_adjustment_atomic ───────────────────────────────────
create or replace function public.record_stock_adjustment_atomic(
  p_request_id uuid,
  p_adjustment jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_cached jsonb;
  v_adjustment_id uuid;
  v_result jsonb;
  v_quantity_before numeric;
  v_quantity_after numeric;
  v_value_egp_before numeric;
  v_value_egp_after numeric;
  v_asset_record record;
begin
  -- Idempotency check
  v_cached := public.terranex_audit_check_idempotent(p_request_id);
  if v_cached is not null then
    return v_cached;
  end if;

  -- Read current asset state to compute before/after values
  select coalesce(quantity, 0), coalesce(current_value_egp, 0)
  into v_quantity_before, v_value_egp_before
  from public.assets
  where id = (p_adjustment->>'asset_id')::uuid and owner_id = auth.uid();

  if v_quantity_before is null then
    raise exception 'Asset not found or not owned by current user';
  end if;

  -- Compute after values
  v_quantity_after := v_quantity_before + (p_adjustment->>'quantity_delta')::numeric;
  v_value_egp_after := v_value_egp_before + (p_adjustment->>'value_egp_delta')::numeric;

  -- Insert stock adjustment (matching actual schema columns)
  insert into public.stock_adjustments (
    id, asset_id, project_id, adjustment_date,
    quantity_before, quantity_after,
    value_egp_before, value_egp_after,
    reason, notes, owner_id
  )
  select
    (p_adjustment->>'id')::uuid,
    (p_adjustment->>'asset_id')::uuid,
    (p_adjustment->>'project_id')::uuid,
    (p_adjustment->>'adjustment_date')::date,
    v_quantity_before,
    v_quantity_after,
    v_value_egp_before,
    v_value_egp_after,
    (p_adjustment->>'reason')::public.terranex_adjustment_reason,
    p_adjustment->>'notes',
    auth.uid()
  returning id into v_adjustment_id;

  -- Update asset quantity and value
  update public.assets
  set quantity = v_quantity_after,
      current_value_egp = v_value_egp_after
  where id = (p_adjustment->>'asset_id')::uuid and owner_id = auth.uid();

  v_result := jsonb_build_object(
    'adjustment_id', v_adjustment_id,
    'quantity_before', v_quantity_before,
    'quantity_after', v_quantity_after,
    'value_egp_before', v_value_egp_before,
    'value_egp_after', v_value_egp_after
  );

  perform public.terranex_audit_log(
    p_request_id,
    'record_stock_adjustment',
    'stock_adjustment',
    array[v_adjustment_id],
    p_adjustment,
    v_result
  );

  return v_result;
end;
$fn$;

\echo '=== P1B FINANCIAL RPCs AND AUDIT: MIGRATION COMPLETE ==='
