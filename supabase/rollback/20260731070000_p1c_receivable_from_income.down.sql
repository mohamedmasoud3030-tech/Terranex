-- Rollback for 20260731070000_p1c_receivable_from_income.sql
-- Restores record_transaction_atomic to hardcoding 'payable' direction,
-- regardless of transaction direction or any p_payable->>'direction' value.
--
-- NOTE: any receivable obligations already created under P1C remain in the
-- table untouched — this only reverts the function's future behavior.

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
