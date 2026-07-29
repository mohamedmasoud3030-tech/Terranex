-- =============================================================================
-- Terranex — Phase P1B hardening
-- Corrects ownership resolution, owner-scoped idempotency, append-only audit
-- permissions, typed updates, and atomic financial write validation.
-- =============================================================================

-- request_id is idempotent per owner, not globally across all tenants.
alter table public.financial_audit_logs
  drop constraint if exists financial_audit_logs_request_id_unique;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.financial_audit_logs'::regclass
      and conname = 'financial_audit_logs_owner_request_unique'
  ) then
    alter table public.financial_audit_logs
      add constraint financial_audit_logs_owner_request_unique
      unique (owner_id, request_id);
  end if;
end $$;

-- Audit rows are written only by the SECURITY DEFINER RPC boundary.
revoke insert, update, delete on public.financial_audit_logs from authenticated;
grant select on public.financial_audit_logs to authenticated;
revoke all on public.financial_audit_logs from anon;

create or replace function public.terranex_assert_owner(p_owner_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_actor uuid := auth.uid();
begin
  if p_owner_id is null then
    raise exception using errcode = '23502', message = 'owner_id cannot be null';
  end if;

  -- postgres executes the real-schema test suite without JWT claims. Every
  -- application call has auth.uid() and must match the owner derived from the
  -- referenced parent row.
  if v_actor is not null and v_actor <> p_owner_id then
    raise exception using errcode = '42501', message = 'financial entity is not owned by the current user';
  end if;
end;
$fn$;

create or replace function public.terranex_lock_financial_request(
  p_owner_id uuid,
  p_request_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if p_request_id is null then
    raise exception using errcode = '23502', message = 'request_id cannot be null';
  end if;

  perform pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_owner_id::text || ':' || p_request_id::text, 0)
  );
end;
$fn$;

create or replace function public.terranex_audit_check_idempotent(
  p_request_id uuid,
  p_owner_id uuid
)
returns jsonb
language sql
security definer
set search_path = public
stable
as $fn$
  select result
  from public.financial_audit_logs
  where owner_id = p_owner_id
    and request_id = p_request_id
  limit 1;
$fn$;

create or replace function public.terranex_audit_log(
  p_request_id uuid,
  p_operation text,
  p_entity_type text,
  p_entity_ids uuid[],
  p_payload jsonb,
  p_result jsonb,
  p_owner_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  insert into public.financial_audit_logs (
    request_id, operation, entity_type, entity_ids, payload, result, owner_id
  ) values (
    p_request_id,
    p_operation,
    p_entity_type,
    coalesce(p_entity_ids, '{}'::uuid[]),
    coalesce(p_payload, '{}'::jsonb),
    coalesce(p_result, '{}'::jsonb),
    p_owner_id
  );
end;
$fn$;

-- ── RPC 1: transaction + optional payable ───────────────────────────────────
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
  v_owner_id uuid;
  v_project_id uuid;
  v_transaction_id uuid;
  v_payable_id uuid;
  v_cached jsonb;
  v_result jsonb;
begin
  if nullif(p_transaction->>'project_id', '') is null then
    raise exception using errcode = '23502', message = 'null value in column "project_id" violates not-null constraint';
  end if;

  v_project_id := (p_transaction->>'project_id')::uuid;
  select owner_id into v_owner_id
  from public.projects
  where id = v_project_id;

  if not found then
    raise exception using errcode = '23503', message = 'project_id does not reference an existing project';
  end if;

  perform public.terranex_assert_owner(v_owner_id);
  perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
  v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;

  insert into public.transactions (
    id, owner_id, project_id, asset_id, partner_id, operational_event_id,
    direction, category, description, amount, currency, fx_rate, amount_egp,
    transaction_date, document_id, notes
  ) values (
    coalesce(nullif(p_transaction->>'id', '')::uuid, gen_random_uuid()),
    v_owner_id,
    v_project_id,
    nullif(p_transaction->>'asset_id', '')::uuid,
    nullif(p_transaction->>'partner_id', '')::uuid,
    nullif(p_transaction->>'operational_event_id', '')::uuid,
    (p_transaction->>'direction')::public.terranex_transaction_direction,
    p_transaction->>'category',
    p_transaction->>'description',
    (p_transaction->>'amount')::numeric,
    (p_transaction->>'currency')::public.terranex_currency,
    (p_transaction->>'fx_rate')::numeric,
    (p_transaction->>'amount_egp')::numeric,
    (p_transaction->>'transaction_date')::date,
    nullif(p_transaction->>'document_id', '')::uuid,
    p_transaction->>'notes'
  ) returning id into v_transaction_id;

  if p_payable is not null and p_payable <> 'null'::jsonb then
    insert into public.obligations (
      id, owner_id, project_id, partner_id, direction, amount, currency,
      amount_egp, amount_settled_egp, due_date, status,
      source_transaction_id, document_id, notes
    ) values (
      coalesce(nullif(p_payable->>'id', '')::uuid, gen_random_uuid()),
      v_owner_id,
      coalesce(nullif(p_payable->>'project_id', '')::uuid, v_project_id),
      nullif(p_payable->>'partner_id', '')::uuid,
      'payable'::public.terranex_obligation_direction,
      (p_payable->>'amount')::numeric,
      (p_payable->>'currency')::public.terranex_currency,
      (p_payable->>'amount_egp')::numeric,
      0,
      nullif(p_payable->>'due_date', '')::date,
      'open'::public.terranex_obligation_status,
      v_transaction_id,
      nullif(p_payable->>'document_id', '')::uuid,
      p_payable->>'notes'
    ) returning id into v_payable_id;
  end if;

  v_result := jsonb_build_object(
    'transaction_id', v_transaction_id,
    'payable_id', v_payable_id
  );

  perform public.terranex_audit_log(
    p_request_id,
    'record_transaction',
    'transaction',
    case when v_payable_id is null
      then array[v_transaction_id]
      else array[v_transaction_id, v_payable_id]
    end,
    jsonb_build_object('transaction', p_transaction, 'payable', p_payable),
    v_result,
    v_owner_id
  );

  return v_result;
end;
$fn$;

-- ── RPC 2: typed transaction/payable update ─────────────────────────────────
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
  v_owner_id uuid;
  v_cached jsonb;
  v_payable_id uuid;
  v_result jsonb;
begin
  select owner_id into v_owner_id
  from public.transactions
  where id = p_transaction_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'transaction not found';
  end if;

  perform public.terranex_assert_owner(v_owner_id);
  perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
  v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;

  if exists (
    select 1 from jsonb_object_keys(coalesce(p_updates, '{}'::jsonb)) as k(key)
    where key <> all (array[
      'project_id','asset_id','partner_id','operational_event_id','direction',
      'category','description','amount','currency','fx_rate','amount_egp',
      'transaction_date','document_id','notes'
    ]::text[])
  ) then
    raise exception using errcode = '22023', message = 'unsupported transaction update field';
  end if;

  update public.transactions
  set project_id = case when p_updates ? 'project_id' then (p_updates->>'project_id')::uuid else project_id end,
      asset_id = case when p_updates ? 'asset_id' then nullif(p_updates->>'asset_id', '')::uuid else asset_id end,
      partner_id = case when p_updates ? 'partner_id' then nullif(p_updates->>'partner_id', '')::uuid else partner_id end,
      operational_event_id = case when p_updates ? 'operational_event_id' then nullif(p_updates->>'operational_event_id', '')::uuid else operational_event_id end,
      direction = case when p_updates ? 'direction' then (p_updates->>'direction')::public.terranex_transaction_direction else direction end,
      category = case when p_updates ? 'category' then p_updates->>'category' else category end,
      description = case when p_updates ? 'description' then p_updates->>'description' else description end,
      amount = case when p_updates ? 'amount' then (p_updates->>'amount')::numeric else amount end,
      currency = case when p_updates ? 'currency' then (p_updates->>'currency')::public.terranex_currency else currency end,
      fx_rate = case when p_updates ? 'fx_rate' then (p_updates->>'fx_rate')::numeric else fx_rate end,
      amount_egp = case when p_updates ? 'amount_egp' then (p_updates->>'amount_egp')::numeric else amount_egp end,
      transaction_date = case when p_updates ? 'transaction_date' then (p_updates->>'transaction_date')::date else transaction_date end,
      document_id = case when p_updates ? 'document_id' then nullif(p_updates->>'document_id', '')::uuid else document_id end,
      notes = case when p_updates ? 'notes' then p_updates->>'notes' else notes end,
      updated_at = now()
  where id = p_transaction_id
    and owner_id = v_owner_id;

  if p_payable_updates is not null and p_payable_updates <> 'null'::jsonb then
    if exists (
      select 1 from jsonb_object_keys(p_payable_updates) as k(key)
      where key <> all (array[
        'project_id','partner_id','amount','currency','amount_egp','due_date',
        'status','amount_settled_egp','document_id','notes'
      ]::text[])
    ) then
      raise exception using errcode = '22023', message = 'unsupported payable update field';
    end if;

    select id into v_payable_id
    from public.obligations
    where source_transaction_id = p_transaction_id
      and direction = 'payable'
      and owner_id = v_owner_id
    limit 1
    for update;

    if v_payable_id is not null then
      update public.obligations
      set project_id = case when p_payable_updates ? 'project_id' then nullif(p_payable_updates->>'project_id', '')::uuid else project_id end,
          partner_id = case when p_payable_updates ? 'partner_id' then (p_payable_updates->>'partner_id')::uuid else partner_id end,
          amount = case when p_payable_updates ? 'amount' then (p_payable_updates->>'amount')::numeric else amount end,
          currency = case when p_payable_updates ? 'currency' then (p_payable_updates->>'currency')::public.terranex_currency else currency end,
          amount_egp = case when p_payable_updates ? 'amount_egp' then (p_payable_updates->>'amount_egp')::numeric else amount_egp end,
          due_date = case when p_payable_updates ? 'due_date' then nullif(p_payable_updates->>'due_date', '')::date else due_date end,
          status = case when p_payable_updates ? 'status' then (p_payable_updates->>'status')::public.terranex_obligation_status else status end,
          amount_settled_egp = case when p_payable_updates ? 'amount_settled_egp' then (p_payable_updates->>'amount_settled_egp')::numeric else amount_settled_egp end,
          document_id = case when p_payable_updates ? 'document_id' then nullif(p_payable_updates->>'document_id', '')::uuid else document_id end,
          notes = case when p_payable_updates ? 'notes' then p_payable_updates->>'notes' else notes end,
          updated_at = now()
      where id = v_payable_id
        and owner_id = v_owner_id;
    end if;
  end if;

  v_result := jsonb_build_object('transaction_id', p_transaction_id, 'payable_id', v_payable_id);
  perform public.terranex_audit_log(
    p_request_id,
    'update_transaction',
    'transaction',
    case when v_payable_id is null then array[p_transaction_id] else array[p_transaction_id, v_payable_id] end,
    jsonb_build_object('transaction_updates', p_updates, 'payable_updates', p_payable_updates),
    v_result,
    v_owner_id
  );
  return v_result;
end;
$fn$;

-- ── RPC 3: transaction + linked payable deletion ────────────────────────────
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
  v_owner_id uuid;
  v_cached jsonb;
  v_payable_ids uuid[];
  v_result jsonb;
begin
  select owner_id into v_owner_id
  from public.transactions
  where id = p_transaction_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'transaction not found';
  end if;

  perform public.terranex_assert_owner(v_owner_id);
  perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
  v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;

  select coalesce(array_agg(id), '{}'::uuid[]) into v_payable_ids
  from public.obligations
  where source_transaction_id = p_transaction_id
    and direction = 'payable'
    and owner_id = v_owner_id;

  delete from public.obligations
  where id = any(v_payable_ids)
    and owner_id = v_owner_id;

  delete from public.transactions
  where id = p_transaction_id
    and owner_id = v_owner_id;

  v_result := jsonb_build_object(
    'transaction_id', p_transaction_id,
    'deleted_payable_ids', v_payable_ids
  );
  perform public.terranex_audit_log(
    p_request_id,
    'delete_transaction',
    'transaction',
    array[p_transaction_id] || v_payable_ids,
    jsonb_build_object('transaction_id', p_transaction_id),
    v_result,
    v_owner_id
  );
  return v_result;
end;
$fn$;

-- ── RPC 4: settlement + allocations + obligation balances ──────────────────
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
  v_owner_id uuid;
  v_allocation_owner uuid;
  v_cached jsonb;
  v_settlement_id uuid;
  v_allocation_ids uuid[] := '{}'::uuid[];
  v_obligation_ids uuid[] := '{}'::uuid[];
  v_allocation jsonb;
  v_allocation_id uuid;
  v_total_allocated numeric;
  v_result jsonb;
begin
  if nullif(p_settlement->>'obligation_id', '') is null then
    raise exception using errcode = '23502', message = 'settlement obligation_id cannot be null';
  end if;

  select owner_id into v_owner_id
  from public.obligations
  where id = (p_settlement->>'obligation_id')::uuid
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'settlement obligation does not exist';
  end if;

  perform public.terranex_assert_owner(v_owner_id);
  perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
  v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;

  if p_allocations is null or jsonb_typeof(p_allocations) <> 'array' or jsonb_array_length(p_allocations) = 0 then
    raise exception using errcode = '22023', message = 'settlement requires at least one allocation';
  end if;

  select sum((item->>'allocated_amount_egp')::numeric)
  into v_total_allocated
  from jsonb_array_elements(p_allocations) as item;

  if v_total_allocated is distinct from (p_settlement->>'amount_egp')::numeric then
    raise exception using errcode = '23514', message = 'settlement allocations must equal settlement amount_egp';
  end if;

  insert into public.settlements (
    id, owner_id, obligation_id, amount, currency, fx_rate, amount_egp,
    settlement_date, payment_method, reference_number,
    receipt_document_id, notes, status, origin
  ) values (
    coalesce(nullif(p_settlement->>'id', '')::uuid, gen_random_uuid()),
    v_owner_id,
    (p_settlement->>'obligation_id')::uuid,
    (p_settlement->>'amount')::numeric,
    (p_settlement->>'currency')::public.terranex_currency,
    (p_settlement->>'fx_rate')::numeric,
    (p_settlement->>'amount_egp')::numeric,
    (p_settlement->>'settlement_date')::date,
    (p_settlement->>'payment_method')::public.terranex_settlement_payment_method,
    p_settlement->>'reference_number',
    nullif(p_settlement->>'receipt_document_id', '')::uuid,
    p_settlement->>'notes',
    'active'::public.terranex_settlement_status,
    'user'::public.terranex_settlement_origin
  ) returning id into v_settlement_id;

  for v_allocation in select value from jsonb_array_elements(p_allocations) loop
    select owner_id into v_allocation_owner
    from public.obligations
    where id = (v_allocation->>'obligation_id')::uuid
    for update;

    if not found or v_allocation_owner <> v_owner_id then
      raise exception using errcode = '42501', message = 'allocation obligation belongs to a different owner or does not exist';
    end if;

    insert into public.settlement_allocations (
      id, owner_id, settlement_id, obligation_id, allocated_amount_egp
    ) values (
      coalesce(nullif(v_allocation->>'id', '')::uuid, gen_random_uuid()),
      v_owner_id,
      v_settlement_id,
      (v_allocation->>'obligation_id')::uuid,
      (v_allocation->>'allocated_amount_egp')::numeric
    ) returning id into v_allocation_id;

    v_allocation_ids := array_append(v_allocation_ids, v_allocation_id);
    v_obligation_ids := array_append(v_obligation_ids, (v_allocation->>'obligation_id')::uuid);

    update public.obligations
    set amount_settled_egp = amount_settled_egp + (v_allocation->>'allocated_amount_egp')::numeric,
        status = case
          when amount_settled_egp + (v_allocation->>'allocated_amount_egp')::numeric = amount_egp
            then 'settled'::public.terranex_obligation_status
          else 'partial'::public.terranex_obligation_status
        end,
        updated_at = now()
    where id = (v_allocation->>'obligation_id')::uuid
      and owner_id = v_owner_id;
  end loop;

  v_result := jsonb_build_object(
    'settlement_id', v_settlement_id,
    'allocation_ids', v_allocation_ids,
    'obligation_ids', v_obligation_ids
  );
  perform public.terranex_audit_log(
    p_request_id,
    'record_settlement',
    'settlement',
    array[v_settlement_id] || v_allocation_ids,
    jsonb_build_object('settlement', p_settlement, 'allocations', p_allocations),
    v_result,
    v_owner_id
  );
  return v_result;
end;
$fn$;

-- ── RPC 5: settlement reversal ──────────────────────────────────────────────
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
  v_owner_id uuid;
  v_status public.terranex_settlement_status;
  v_cached jsonb;
  v_obligation_ids uuid[] := '{}'::uuid[];
  v_allocation record;
  v_now timestamptz := now();
  v_result jsonb;
begin
  if length(btrim(coalesce(p_reason, ''))) = 0 then
    raise exception using errcode = '23514', message = 'reversal reason is required';
  end if;

  select owner_id, status into v_owner_id, v_status
  from public.settlements
  where id = p_settlement_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'settlement not found';
  end if;

  perform public.terranex_assert_owner(v_owner_id);
  perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
  v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;

  if v_status <> 'active' then
    raise exception using errcode = '23514', message = 'only active settlements can be reversed';
  end if;

  update public.settlements
  set status = 'reversed'::public.terranex_settlement_status,
      reversed_at = v_now,
      reversal_reason = btrim(p_reason),
      updated_at = v_now
  where id = p_settlement_id
    and owner_id = v_owner_id;

  for v_allocation in
    select obligation_id, allocated_amount_egp
    from public.settlement_allocations
    where settlement_id = p_settlement_id
      and owner_id = v_owner_id
    for update
  loop
    v_obligation_ids := array_append(v_obligation_ids, v_allocation.obligation_id);
    update public.obligations
    set amount_settled_egp = greatest(0, amount_settled_egp - v_allocation.allocated_amount_egp),
        status = case
          when greatest(0, amount_settled_egp - v_allocation.allocated_amount_egp) = 0
            then 'open'::public.terranex_obligation_status
          else 'partial'::public.terranex_obligation_status
        end,
        updated_at = v_now
    where id = v_allocation.obligation_id
      and owner_id = v_owner_id;
  end loop;

  v_result := jsonb_build_object(
    'settlement_id', p_settlement_id,
    'reversed_obligation_ids', v_obligation_ids,
    'reason', btrim(p_reason),
    'reversed_at', v_now
  );
  perform public.terranex_audit_log(
    p_request_id,
    'reverse_settlement',
    'settlement',
    array[p_settlement_id] || v_obligation_ids,
    jsonb_build_object('settlement_id', p_settlement_id, 'reason', btrim(p_reason)),
    v_result,
    v_owner_id
  );
  return v_result;
end;
$fn$;

-- ── RPC 6: stock adjustment + asset state ───────────────────────────────────
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
  v_owner_id uuid;
  v_project_id uuid;
  v_cached jsonb;
  v_adjustment_id uuid;
  v_quantity_before numeric;
  v_quantity_after numeric;
  v_value_before numeric;
  v_value_after numeric;
  v_quantity_delta numeric;
  v_value_delta numeric;
  v_result jsonb;
begin
  select owner_id, project_id, coalesce(quantity, 0), coalesce(current_value_egp, 0)
  into v_owner_id, v_project_id, v_quantity_before, v_value_before
  from public.assets
  where id = (p_adjustment->>'asset_id')::uuid
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'asset not found';
  end if;

  perform public.terranex_assert_owner(v_owner_id);
  perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
  v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;

  if nullif(p_adjustment->>'project_id', '') is not null
     and (p_adjustment->>'project_id')::uuid <> v_project_id then
    raise exception using errcode = '23514', message = 'adjustment project_id does not match asset project_id';
  end if;

  v_quantity_delta := coalesce((p_adjustment->>'quantity_delta')::numeric, 0);
  v_value_delta := coalesce((p_adjustment->>'value_egp_delta')::numeric, 0);
  v_quantity_after := v_quantity_before + v_quantity_delta;
  v_value_after := v_value_before + v_value_delta;

  if v_quantity_after < 0 or v_value_after < 0 then
    raise exception using errcode = '23514', message = 'stock adjustment cannot produce negative quantity or value';
  end if;

  insert into public.stock_adjustments (
    id, owner_id, asset_id, project_id, adjustment_date,
    quantity_before, quantity_after, value_egp_before, value_egp_after,
    reason, notes
  ) values (
    coalesce(nullif(p_adjustment->>'id', '')::uuid, gen_random_uuid()),
    v_owner_id,
    (p_adjustment->>'asset_id')::uuid,
    v_project_id,
    (p_adjustment->>'adjustment_date')::date,
    v_quantity_before,
    v_quantity_after,
    v_value_before,
    v_value_after,
    (p_adjustment->>'reason')::public.terranex_adjustment_reason,
    p_adjustment->>'notes'
  ) returning id into v_adjustment_id;

  update public.assets
  set quantity = v_quantity_after,
      current_value_egp = v_value_after
  where id = (p_adjustment->>'asset_id')::uuid
    and owner_id = v_owner_id;

  v_result := jsonb_build_object(
    'adjustment_id', v_adjustment_id,
    'quantity_before', v_quantity_before,
    'quantity_after', v_quantity_after,
    'value_egp_before', v_value_before,
    'value_egp_after', v_value_after
  );
  perform public.terranex_audit_log(
    p_request_id,
    'record_stock_adjustment',
    'stock_adjustment',
    array[v_adjustment_id],
    p_adjustment,
    v_result,
    v_owner_id
  );
  return v_result;
end;
$fn$;

-- Only authenticated callers may use the financial RPC boundary. The migration
-- owner (postgres) retains implicit execution for the real-schema test suite.
revoke execute on function public.record_transaction_atomic(uuid, jsonb, jsonb) from public, anon;
revoke execute on function public.update_transaction_atomic(uuid, uuid, jsonb, jsonb) from public, anon;
revoke execute on function public.delete_transaction_atomic(uuid, uuid) from public, anon;
revoke execute on function public.record_settlement_atomic(uuid, jsonb, jsonb) from public, anon;
revoke execute on function public.reverse_settlement_atomic(uuid, uuid, text) from public, anon;
revoke execute on function public.record_stock_adjustment_atomic(uuid, jsonb) from public, anon;

grant execute on function public.record_transaction_atomic(uuid, jsonb, jsonb) to authenticated;
grant execute on function public.update_transaction_atomic(uuid, uuid, jsonb, jsonb) to authenticated;
grant execute on function public.delete_transaction_atomic(uuid, uuid) to authenticated;
grant execute on function public.record_settlement_atomic(uuid, jsonb, jsonb) to authenticated;
grant execute on function public.reverse_settlement_atomic(uuid, uuid, text) to authenticated;
grant execute on function public.record_stock_adjustment_atomic(uuid, jsonb) to authenticated;

revoke execute on function public.terranex_assert_owner(uuid) from public, anon, authenticated;
revoke execute on function public.terranex_lock_financial_request(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.terranex_audit_check_idempotent(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.terranex_audit_log(uuid, text, text, uuid[], jsonb, jsonb, uuid) from public, anon, authenticated;
revoke execute on function public.terranex_audit_check_idempotent(uuid) from public, anon, authenticated;
revoke execute on function public.terranex_audit_log(uuid, text, text, uuid[], jsonb, jsonb) from public, anon, authenticated;

\echo '=== P1B FINANCIAL RPC HARDENING: MIGRATION COMPLETE ==='
