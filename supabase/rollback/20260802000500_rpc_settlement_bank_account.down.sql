-- Rollback: restore original record_settlement_atomic without bank_account_id.
create or replace function public.record_settlement_atomic(
  p_request_id uuid, p_settlement jsonb, p_allocations jsonb
) returns jsonb language plpgsql security definer set search_path = public as $fn$
declare
  v_owner_id uuid; v_allocation_owner uuid; v_cached jsonb;
  v_settlement_id uuid; v_allocation_ids uuid[] := '{}'::uuid[]; v_obligation_ids uuid[] := '{}'::uuid[];
  v_allocation jsonb; v_allocation_id uuid; v_total_allocated numeric; v_result jsonb;
begin
  select owner_id into v_owner_id from public.obligations where id = (p_settlement->>'obligation_id')::uuid for update;
  if not found then raise exception using errcode='23503', message='settlement obligation does not exist'; end if;
  perform public.terranex_assert_owner(v_owner_id);
  perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
  v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;
  if p_allocations is null or jsonb_typeof(p_allocations)<>'array' or jsonb_array_length(p_allocations)=0 then
    raise exception using errcode='22023', message='settlement requires at least one allocation';
  end if;
  select sum((item->>'allocated_amount_egp')::numeric) into v_total_allocated
    from jsonb_array_elements(p_allocations) item;
  if v_total_allocated is distinct from (p_settlement->>'amount_egp')::numeric then
    raise exception using errcode='23514', message='settlement allocations must equal settlement amount_egp';
  end if;
  insert into public.settlements (
    id, owner_id, obligation_id, amount, currency, fx_rate, amount_egp,
    settlement_date, payment_method, reference_number, receipt_document_id,
    notes, status, origin
  ) values (
    coalesce(nullif(p_settlement->>'id','')::uuid, gen_random_uuid()),
    v_owner_id, (p_settlement->>'obligation_id')::uuid,
    (p_settlement->>'amount')::numeric,
    (p_settlement->>'currency')::public.terranex_currency,
    (p_settlement->>'fx_rate')::numeric,
    (p_settlement->>'amount_egp')::numeric,
    (p_settlement->>'settlement_date')::date,
    (p_settlement->>'payment_method')::public.terranex_settlement_payment_method,
    p_settlement->>'reference_number',
    nullif(p_settlement->>'receipt_document_id','')::uuid,
    p_settlement->>'notes',
    'active'::public.terranex_settlement_status,
    'user'::public.terranex_settlement_origin
  ) returning id into v_settlement_id;
  for v_allocation in select value from jsonb_array_elements(p_allocations) loop
    select owner_id into v_allocation_owner from public.obligations
      where id = (v_allocation->>'obligation_id')::uuid for update;
    if not found or v_allocation_owner <> v_owner_id then
      raise exception using errcode='42501', message='allocation obligation belongs to a different owner or does not exist';
    end if;
    insert into public.settlement_allocations (id, owner_id, settlement_id, obligation_id, allocated_amount_egp)
    values (coalesce(nullif(v_allocation->>'id','')::uuid, gen_random_uuid()), v_owner_id, v_settlement_id,
            (v_allocation->>'obligation_id')::uuid, (v_allocation->>'allocated_amount_egp')::numeric)
      returning id into v_allocation_id;
    v_allocation_ids := array_append(v_allocation_ids, v_allocation_id);
    v_obligation_ids := array_append(v_obligation_ids, (v_allocation->>'obligation_id')::uuid);
    update public.obligations set amount_settled_egp = amount_settled_egp + (v_allocation->>'allocated_amount_egp')::numeric,
      status = case when amount_settled_egp + (v_allocation->>'allocated_amount_egp')::numeric = amount_egp
                    then 'settled'::public.terranex_obligation_status else 'partial'::public.terranex_obligation_status end,
      updated_at = now()
      where id = (v_allocation->>'obligation_id')::uuid and owner_id = v_owner_id;
  end loop;
  v_result := jsonb_build_object('settlement_id',v_settlement_id,'allocation_ids',v_allocation_ids,'obligation_ids',v_obligation_ids);
  perform public.terranex_audit_log(p_request_id,'record_settlement','settlement',
    array[v_settlement_id] || v_allocation_ids,
    jsonb_build_object('settlement',p_settlement,'allocations',p_allocations), v_result, v_owner_id);
  return v_result;
end; $fn$;
