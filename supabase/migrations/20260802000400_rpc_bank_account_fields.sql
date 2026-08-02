-- Migration: Extend the record_transaction_atomic / update_transaction_atomic
-- RPCs to accept bank_account_id so that cash/bank payments are recorded on
-- the bank_accounts ledger directly inside the financial write boundary.
-- We still rely on the client to create the matching bank_transaction row via
-- link_financial_movement() in this phase to keep the change small.
-- Date: 2026-08-02

-- Re-define record_transaction_atomic to include bank_account_id in insert.
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
  v_bank_account uuid;
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

  v_bank_account := nullif(p_transaction->>'bank_account_id', '')::uuid;
  if v_bank_account is not null then
    -- Ensure the referenced bank account belongs to the same owner.
    perform 1 from public.bank_accounts
      where id = v_bank_account and owner_id = v_owner_id;
    if not found then
      raise exception using errcode = '23503', message = 'bank_account_id does not reference an existing account for this owner';
    end if;
  end if;

  perform public.terranex_assert_owner(v_owner_id);
  perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
  v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;

  insert into public.transactions (
    id, owner_id, project_id, asset_id, partner_id, operational_event_id,
    bank_account_id,
    direction, category, description, amount, currency, fx_rate, amount_egp,
    transaction_date, document_id, notes
  ) values (
    coalesce(nullif(p_transaction->>'id', '')::uuid, gen_random_uuid()),
    v_owner_id,
    v_project_id,
    nullif(p_transaction->>'asset_id', '')::uuid,
    nullif(p_transaction->>'partner_id', '')::uuid,
    nullif(p_transaction->>'operational_event_id', '')::uuid,
    v_bank_account,
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
      case when (p_payable->>'direction') = 'receivable' then 'receivable'::public.terranex_obligation_direction else 'payable'::public.terranex_obligation_direction end,
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

-- Extend update_transaction_atomic to permit bank_account_id updates.
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
  v_bank_account uuid;
begin
  select owner_id into v_owner_id
  from public.transactions
  where id = p_transaction_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'transaction not found';
  end if;

  if p_updates ? 'bank_account_id' then
    v_bank_account := nullif(p_updates->>'bank_account_id', '')::uuid;
    if v_bank_account is not null then
      perform 1 from public.bank_accounts
        where id = v_bank_account and owner_id = v_owner_id;
      if not found then
        raise exception using errcode = '23503', message = 'bank_account_id does not reference an existing account for this owner';
      end if;
    end if;
  end if;

  perform public.terranex_assert_owner(v_owner_id);
  perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
  v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;

  if exists (
    select 1 from jsonb_object_keys(coalesce(p_updates, '{}'::jsonb)) as k(key)
    where key <> all (array[
      'project_id','asset_id','partner_id','operational_event_id','bank_account_id','direction',
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
      bank_account_id = case when p_updates ? 'bank_account_id' then v_bank_account else bank_account_id end,
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
        'project_id','partner_id','direction','amount','currency','amount_egp','due_date',
        'status','amount_settled_egp','document_id','notes'
      ]::text[])
    ) then
      raise exception using errcode = '22023', message = 'unsupported payable update field';
    end if;

    select id into v_payable_id
    from public.obligations
    where source_transaction_id = p_transaction_id
      and direction in ('payable','receivable')
      and owner_id = v_owner_id
    limit 1
    for update;

    if v_payable_id is not null then
      update public.obligations
      set project_id = case when p_payable_updates ? 'project_id' then nullif(p_payable_updates->>'project_id', '')::uuid else project_id end,
          partner_id = case when p_payable_updates ? 'partner_id' then (p_payable_updates->>'partner_id')::uuid else partner_id end,
          direction = case when p_payable_updates ? 'direction' then (p_payable_updates->>'direction')::public.terranex_obligation_direction else direction end,
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
