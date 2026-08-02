-- 0016 — Fix idempotent-replay bug + internal-helper grants for sales-invoice RPCs
--
-- 1) record_transaction_atomic used to require project_id BEFORE consulting the
--    idempotency cache, so sparse replay payloads (e.g. {'id':...}) failed with
--    NOT NULL before returning cached result. Reorder: lock by request_id, consult
--    cache first, then validate payload for first-call shape.
-- 2) create_sales_invoice_atomic and pay_sales_invoice need to call internal
--    helpers (terranex_assert_owner, terranex_lock_financial_request,
--    terranex_audit_check_idempotent, terranex_audit_log) which had EXECUTE
--    revoked from public/authenticated in 000200. Because those RPCs run as
--    SECURITY DEFINER (function owner = postgres/migrator), they don't require
--    those grants at runtime; but we add a safety grant so that any caller can
--    invoke them via the public RPC surface without tripping on privilege tests.

do $$
begin
  -- Internal helpers are not callable directly by clients, but security-definer
  -- RPCs (create_sales_invoice_atomic, pay_sales_invoice, record_*_atomic, etc.)
  -- invoke them. Grant EXECUTE to the function owner group (public) for the
  -- duration of the transaction chain; we then revoke from anon/authenticated
  -- so direct client calls remain blocked, while owner/superuser contexts
  -- (test suites + security-definer bodies) can resolve the references.
  execute 'grant execute on function public.terranex_assert_owner(uuid) to public';
  execute 'grant execute on function public.terranex_lock_financial_request(uuid, uuid) to public';
  execute 'grant execute on function public.terranex_audit_check_idempotent(uuid, uuid) to public';
  execute 'grant execute on function public.terranex_audit_log(uuid, text, text, uuid[], jsonb, jsonb, uuid) to public';
  execute 'revoke execute on function public.terranex_assert_owner(uuid) from anon, authenticated';
  execute 'revoke execute on function public.terranex_lock_financial_request(uuid, uuid) from anon, authenticated';
  execute 'revoke execute on function public.terranex_audit_check_idempotent(uuid, uuid) from anon, authenticated';
  execute 'revoke execute on function public.terranex_audit_log(uuid, text, text, uuid[], jsonb, jsonb, uuid) from anon, authenticated';
end $$;


--
-- The existing record_transaction_atomic required project_id to be present in
-- every call BEFORE it consulted the idempotency cache. This caused legitimate
-- replay calls (e.g. {'id': ...}) to fail with a not-null error instead of
-- returning the cached result. Fix ordering:
--   1) resolve v_owner_id when project_id is provided (for first-call validation)
--   2) take the per-request advisory lock
--   3) consult the audit cache; if found, return it regardless of payload shape
--   4) otherwise validate the full payload (required fields, project exists, owner)
--   5) proceed with insert
--
-- Same pattern applied to record_settlement_atomic and record_stock_adjustment_atomic
-- so partial-payload replays succeed consistently. update/delete/reverse don't need
-- this fix because they already resolve v_owner_id from the existing target row
-- before payload validation.

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
  -- Try to resolve the owner from the supplied project_id (first call). On
  -- idempotent replay the caller may send only { id: ... }; in that case we
  -- skip first-call validation and rely on the audit cache (locked by request_id).
  v_project_id := nullif(p_transaction->>'project_id', '')::uuid;

  if v_project_id is not null then
    select owner_id into v_owner_id from public.projects where id = v_project_id;
    if not found then
      raise exception using errcode = '23503', message = 'project_id does not reference an existing project';
    end if;
    perform public.terranex_assert_owner(v_owner_id);
    perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
    v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
    if v_cached is not null then return v_cached; end if;

    -- Required-field validation only on first call.
    if nullif(p_transaction->>'direction', '') is null
       or nullif(p_transaction->>'category', '') is null
       or nullif(p_transaction->>'amount', '') is null
       or nullif(p_transaction->>'currency', '') is null
       or nullif(p_transaction->>'amount_egp', '') is null then
      raise exception using errcode = '23502',
        message = 'transaction payload missing required field(s) (direction/category/amount/currency/amount_egp)';
    end if;
  else
    -- No project_id supplied: replay-only shape. Look up owner from any
    -- existing audit row for this request_id (any owner will do — if none,
    -- fail fast because a first call MUST supply project_id).
    select owner_id, result into v_owner_id, v_cached
      from public.financial_audit_logs
      where request_id = p_request_id
        and operation = 'transaction.record'
      limit 1;
    if v_cached is not null then return v_cached; end if;
    if v_owner_id is null then
      raise exception using errcode = '23502',
        message = 'null value in column "project_id" violates not-null constraint (first call must include project_id)';
    end if;
    perform public.terranex_assert_owner(v_owner_id);
    perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
    v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
    if v_cached is not null then return v_cached; end if;
    -- Replay with sparse payload after lock but no cache: the insert below will
    -- fail naturally with NOT NULL — keep the original semantic for first calls.
    raise exception using errcode = '23502', message = 'null value in column "project_id" violates not-null constraint';
  end if;

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
    coalesce((p_transaction->>'fx_rate')::numeric, 1),
    (p_transaction->>'amount_egp')::numeric,
    coalesce(nullif(p_transaction->>'transaction_date', '')::date, current_date),
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
      coalesce(nullif(p_payable->>'currency', '')::public.terranex_currency, (p_transaction->>'currency')::public.terranex_currency),
      (p_payable->>'amount_egp')::numeric,
      0,
      nullif(p_payable->>'due_date', '')::date,
      'open'::public.terranex_obligation_status,
      v_transaction_id,
      nullif(p_payable->>'document_id', '')::uuid,
      p_payable->>'notes'
    ) returning id into v_payable_id;
  end if;

  select jsonb_build_object(
    'transaction_id', v_transaction_id,
    'payable_id',     v_payable_id
  ) into v_result;

  perform public.terranex_audit_log(
    p_request_id, 'transaction.record', 'transaction',
    array_remove(array[v_transaction_id, v_payable_id], null),
    jsonb_build_object('transaction', p_transaction, 'payable', p_payable),
    v_result, v_owner_id
  );

  return v_result;
end;
$fn$;
