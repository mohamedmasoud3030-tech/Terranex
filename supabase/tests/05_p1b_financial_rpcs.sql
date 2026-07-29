-- =============================================================================
-- Terranex DB test — P1B financial atomicity RPCs
-- =============================================================================
-- Proves all six RPCs against real PostgreSQL with atomic rollback,
-- owner isolation, request-id idempotency, audit immutability, and pinned
-- search_path. No fake client participates in this suite.
-- =============================================================================
\set ON_ERROR_STOP on
\timing off

create or replace function public.terranex_test_uuid(p_seed int)
returns uuid
language sql
immutable
as $fn$
  select ('00000000-0000-4000-8000-' || lpad(p_seed::text, 12, '0'))::uuid;
$fn$;

-- ═══ TEST 1: record + update + delete transaction graph ═════════════════════
begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.obligations where true;
delete from public.transactions where true;

insert into auth.users (id, email)
values ('11111111-1111-4111-8111-111111111111', 'p1b-transactions@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid(1),
  '11111111-1111-4111-8111-111111111111',
  'agriculture', 'مشروع اختبار', 'Test Project', 'active', '2026-01-01', 'EGP'
);

insert into public.partners (id, owner_id, name_ar, category, counterparty_role)
values (
  public.terranex_test_uuid(2),
  '11111111-1111-4111-8111-111111111111',
  'مورد اختبار', 'counterparty', 'supplier'
);

do $test$
declare
  v_record_request uuid := public.terranex_test_uuid(100);
  v_update_request uuid := public.terranex_test_uuid(101);
  v_delete_request uuid := public.terranex_test_uuid(102);
  v_transaction_id uuid := public.terranex_test_uuid(200);
  v_payable_id uuid := public.terranex_test_uuid(201);
  v_result jsonb;
  v_retry jsonb;
  v_count int;
  v_amount numeric;
begin
  select public.record_transaction_atomic(
    v_record_request,
    jsonb_build_object(
      'id', v_transaction_id,
      'project_id', public.terranex_test_uuid(1),
      'partner_id', public.terranex_test_uuid(2),
      'direction', 'expense',
      'category', 'maintenance',
      'description', 'مصروف اختبار',
      'amount', 500,
      'currency', 'EGP',
      'fx_rate', 1,
      'amount_egp', 500,
      'transaction_date', '2026-07-29'
    ),
    jsonb_build_object(
      'id', v_payable_id,
      'project_id', public.terranex_test_uuid(1),
      'partner_id', public.terranex_test_uuid(2),
      'amount', 500,
      'currency', 'EGP',
      'amount_egp', 500,
      'due_date', '2026-08-29'
    )
  ) into v_result;

  if v_result->>'transaction_id' is distinct from v_transaction_id::text
     or v_result->>'payable_id' is distinct from v_payable_id::text then
    raise exception 'FAIL record_transaction_atomic: unexpected result %', v_result;
  end if;

  select count(*) into v_count from public.transactions where id = v_transaction_id;
  if v_count <> 1 then raise exception 'FAIL record_transaction_atomic: transaction missing'; end if;
  select count(*) into v_count from public.obligations where id = v_payable_id;
  if v_count <> 1 then raise exception 'FAIL record_transaction_atomic: payable missing'; end if;

  -- A retry is resolved from the audit cache before validating its rebuilt body.
  select public.record_transaction_atomic(
    v_record_request,
    jsonb_build_object('id', public.terranex_test_uuid(999))
  ) into v_retry;
  if v_retry is distinct from v_result then
    raise exception 'FAIL record_transaction_atomic idempotency: cached result mismatch';
  end if;

  select public.update_transaction_atomic(
    v_update_request,
    v_transaction_id,
    jsonb_build_object(
      'amount', 550,
      'amount_egp', 550,
      'description', 'مصروف اختبار معدل'
    ),
    jsonb_build_object(
      'amount', 550,
      'amount_egp', 550,
      'notes', 'تم التعديل ذريًا'
    )
  ) into v_result;

  select amount into v_amount from public.transactions where id = v_transaction_id;
  if v_amount <> 550 then raise exception 'FAIL update_transaction_atomic: transaction not updated'; end if;
  select amount into v_amount from public.obligations where id = v_payable_id;
  if v_amount <> 550 then raise exception 'FAIL update_transaction_atomic: payable not updated'; end if;

  select public.delete_transaction_atomic(v_delete_request, v_transaction_id) into v_result;
  select count(*) into v_count from public.transactions where id = v_transaction_id;
  if v_count <> 0 then raise exception 'FAIL delete_transaction_atomic: transaction remains'; end if;
  select count(*) into v_count from public.obligations where id = v_payable_id;
  if v_count <> 0 then raise exception 'FAIL delete_transaction_atomic: payable remains'; end if;

  select count(*) into v_count
  from public.financial_audit_logs
  where request_id in (v_record_request, v_update_request, v_delete_request);
  if v_count <> 3 then raise exception 'FAIL transaction graph audit: expected 3 rows, got %', v_count; end if;

  raise notice 'PASS transaction RPCs: record/update/delete + idempotency + audit';
end;
$test$;
rollback;

-- ═══ TEST 2: settlement + allocation + reversal ═════════════════════════════
begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.settlement_allocations where true;
delete from public.settlements where true;
delete from public.obligations where true;

insert into auth.users (id, email)
values ('22222222-2222-4222-8222-222222222222', 'p1b-settlements@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid(10),
  '22222222-2222-4222-8222-222222222222',
  'real-estate', 'مشروع تسوية', 'Settlement Project', 'active', '2026-01-01', 'EGP'
);

insert into public.partners (id, owner_id, name_ar, category, counterparty_role)
values (
  public.terranex_test_uuid(11),
  '22222222-2222-4222-8222-222222222222',
  'طرف تسوية', 'counterparty', 'client'
);

insert into public.obligations (
  id, owner_id, project_id, partner_id, direction, amount, currency,
  amount_egp, amount_settled_egp, due_date, status
) values (
  public.terranex_test_uuid(12),
  '22222222-2222-4222-8222-222222222222',
  public.terranex_test_uuid(10),
  public.terranex_test_uuid(11),
  'receivable', 1000, 'EGP', 1000, 0, '2026-08-01', 'open'
);

do $test$
declare
  v_record_request uuid := public.terranex_test_uuid(300);
  v_reverse_request uuid := public.terranex_test_uuid(310);
  v_settlement_id uuid := public.terranex_test_uuid(301);
  v_allocation_id uuid := public.terranex_test_uuid(302);
  v_obligation_id uuid := public.terranex_test_uuid(12);
  v_result jsonb;
  v_retry jsonb;
  v_status text;
  v_settled numeric;
  v_reversed_at timestamptz;
  v_reason text;
  v_count int;
begin
  select public.record_settlement_atomic(
    v_record_request,
    jsonb_build_object(
      'id', v_settlement_id,
      'obligation_id', v_obligation_id,
      'amount', 600,
      'currency', 'EGP',
      'fx_rate', 1,
      'amount_egp', 600,
      'payment_method', 'cash',
      'settlement_date', '2026-07-29'
    ),
    jsonb_build_array(
      jsonb_build_object(
        'id', v_allocation_id,
        'obligation_id', v_obligation_id,
        'allocated_amount_egp', 600
      )
    )
  ) into v_result;

  select amount_settled_egp, status into v_settled, v_status
  from public.obligations where id = v_obligation_id;
  if v_settled <> 600 or v_status is distinct from 'partial' then
    raise exception 'FAIL record_settlement_atomic: obligation state %, %', v_settled, v_status;
  end if;

  select public.record_settlement_atomic(
    v_record_request,
    jsonb_build_object(
      'id', public.terranex_test_uuid(399),
      'obligation_id', v_obligation_id,
      'amount_egp', 9999
    ),
    '[]'::jsonb
  ) into v_retry;
  if v_retry is distinct from v_result then
    raise exception 'FAIL record_settlement_atomic idempotency: cached result mismatch';
  end if;

  select public.reverse_settlement_atomic(
    v_reverse_request,
    v_settlement_id,
    'تصحيح تسوية خاطئة'
  ) into v_result;

  select status, reversed_at, reversal_reason
  into v_status, v_reversed_at, v_reason
  from public.settlements where id = v_settlement_id;
  if v_status is distinct from 'reversed' or v_reversed_at is null
     or v_reason is distinct from 'تصحيح تسوية خاطئة' then
    raise exception 'FAIL reverse_settlement_atomic: invalid reversal state';
  end if;

  select amount_settled_egp, status into v_settled, v_status
  from public.obligations where id = v_obligation_id;
  if v_settled <> 0 or v_status is distinct from 'open' then
    raise exception 'FAIL reverse_settlement_atomic: obligation not restored';
  end if;

  select count(*) into v_count
  from public.financial_audit_logs
  where request_id in (v_record_request, v_reverse_request);
  if v_count <> 2 then raise exception 'FAIL settlement audit: expected 2 rows, got %', v_count; end if;

  raise notice 'PASS settlement RPCs: record/reverse + balances + idempotency';
end;
$test$;
rollback;

-- ═══ TEST 3: stock adjustment + asset state ═════════════════════════════════
begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.stock_adjustments where true;

insert into auth.users (id, email)
values ('33333333-3333-4333-8333-333333333333', 'p1b-stock@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid(20),
  '33333333-3333-4333-8333-333333333333',
  'agriculture', 'مشروع مخزون', 'Stock Project', 'active', '2026-01-01', 'EGP'
);

insert into public.assets (
  id, owner_id, project_id, sector_id, type, name_ar, name_en,
  acquisition_date, acquisition_cost, acquisition_currency,
  acquisition_cost_egp, current_value_egp, status, quantity
) values (
  public.terranex_test_uuid(21),
  '33333333-3333-4333-8333-333333333333',
  public.terranex_test_uuid(20),
  'agriculture', 'equipment', 'أصل مخزون', 'Stock Asset',
  '2026-01-01', 10000, 'EGP', 10000, 10000, 'owned', 10
);

do $test$
declare
  v_request_id uuid := public.terranex_test_uuid(500);
  v_asset_id uuid := public.terranex_test_uuid(21);
  v_result jsonb;
  v_retry jsonb;
  v_quantity numeric;
  v_value numeric;
  v_count int;
begin
  select public.record_stock_adjustment_atomic(
    v_request_id,
    jsonb_build_object(
      'id', public.terranex_test_uuid(501),
      'asset_id', v_asset_id,
      'project_id', public.terranex_test_uuid(20),
      'adjustment_date', '2026-07-29',
      'reason', 'data_correction',
      'quantity_delta', 5,
      'value_egp_delta', 500
    )
  ) into v_result;

  select quantity, current_value_egp into v_quantity, v_value
  from public.assets where id = v_asset_id;
  if v_quantity <> 15 or v_value <> 10500 then
    raise exception 'FAIL record_stock_adjustment_atomic: asset state %, %', v_quantity, v_value;
  end if;

  select public.record_stock_adjustment_atomic(
    v_request_id,
    jsonb_build_object(
      'id', public.terranex_test_uuid(599),
      'asset_id', v_asset_id,
      'project_id', public.terranex_test_uuid(20),
      'adjustment_date', '2026-12-31',
      'reason', 'data_correction',
      'quantity_delta', 99,
      'value_egp_delta', 99
    )
  ) into v_retry;
  if v_retry is distinct from v_result then
    raise exception 'FAIL stock idempotency: cached result mismatch';
  end if;

  select quantity, current_value_egp into v_quantity, v_value
  from public.assets where id = v_asset_id;
  if v_quantity <> 15 or v_value <> 10500 then
    raise exception 'FAIL stock idempotency: asset was adjusted twice';
  end if;

  select count(*) into v_count
  from public.financial_audit_logs where request_id = v_request_id;
  if v_count <> 1 then raise exception 'FAIL stock audit: expected 1 row, got %', v_count; end if;

  raise notice 'PASS stock RPC: before/after state + idempotency + audit';
end;
$test$;
rollback;

-- ═══ TEST 4: partial failure rolls back the whole function call ══════════════
begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.obligations where true;
delete from public.transactions where true;

insert into auth.users (id, email)
values ('44444444-4444-4444-8444-444444444444', 'p1b-rollback@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid(30),
  '44444444-4444-4444-8444-444444444444',
  'agriculture', 'مشروع تراجع', 'Rollback Project', 'active', '2026-01-01', 'EGP'
);

insert into public.partners (id, owner_id, name_ar, category, counterparty_role)
values (
  public.terranex_test_uuid(31),
  '44444444-4444-4444-8444-444444444444',
  'مورد تراجع', 'counterparty', 'supplier'
);

do $test$
declare
  v_request_id uuid := public.terranex_test_uuid(800);
  v_transaction_id uuid := public.terranex_test_uuid(801);
  v_payable_id uuid := public.terranex_test_uuid(802);
  v_count int;
begin
  begin
    perform public.record_transaction_atomic(
      v_request_id,
      jsonb_build_object(
        'id', v_transaction_id,
        'project_id', public.terranex_test_uuid(30),
        'partner_id', public.terranex_test_uuid(31),
        'direction', 'expense',
        'category', 'maintenance',
        'amount', 500,
        'currency', 'EGP',
        'fx_rate', 1,
        'amount_egp', 500,
        'transaction_date', '2026-07-29'
      ),
      jsonb_build_object(
        'id', v_payable_id,
        'project_id', public.terranex_test_uuid(30),
        'partner_id', public.terranex_test_uuid(31),
        'amount', 500,
        'currency', 'EGP',
        'amount_egp', 500,
        'due_date', 'not-a-date'
      )
    );
    raise exception 'FAIL rollback: invalid payable unexpectedly succeeded';
  exception
    when invalid_datetime_format then
      null;
  end;

  select count(*) into v_count from public.transactions where id = v_transaction_id;
  if v_count <> 0 then raise exception 'FAIL rollback: transaction survived failed payable'; end if;
  select count(*) into v_count from public.obligations where id = v_payable_id;
  if v_count <> 0 then raise exception 'FAIL rollback: payable survived failed call'; end if;
  select count(*) into v_count from public.financial_audit_logs where request_id = v_request_id;
  if v_count <> 0 then raise exception 'FAIL rollback: audit row survived failed call'; end if;

  raise notice 'PASS atomic rollback: no partial transaction/payable/audit state';
end;
$test$;
rollback;

-- ═══ TEST 5: RPC owner isolation ═════════════════════════════════════════════
begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.transactions where true;

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'p1b-owner-a@terranex.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'p1b-owner-b@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid(40),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'agriculture', 'مشروع المالك ب', 'Owner B Project', 'active', '2026-01-01', 'EGP'
);

insert into public.partners (id, owner_id, name_ar, category, counterparty_role)
values (
  public.terranex_test_uuid(41),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'طرف المالك ب', 'counterparty', 'supplier'
);

do $test$
declare
  v_count int;
begin
  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);

  begin
    perform public.record_transaction_atomic(
      public.terranex_test_uuid(900),
      jsonb_build_object(
        'id', public.terranex_test_uuid(901),
        'project_id', public.terranex_test_uuid(40),
        'partner_id', public.terranex_test_uuid(41),
        'direction', 'expense',
        'category', 'isolation-test',
        'amount', 1,
        'currency', 'EGP',
        'fx_rate', 1,
        'amount_egp', 1,
        'transaction_date', '2026-07-29'
      )
    );
    raise exception 'FAIL owner isolation: cross-owner RPC unexpectedly succeeded';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*) into v_count
  from public.transactions where id = public.terranex_test_uuid(901);
  if v_count <> 0 then raise exception 'FAIL owner isolation: cross-owner row was created'; end if;
  select count(*) into v_count
  from public.financial_audit_logs where request_id = public.terranex_test_uuid(900);
  if v_count <> 0 then raise exception 'FAIL owner isolation: cross-owner audit was created'; end if;

  raise notice 'PASS owner isolation: authenticated owner cannot write another owner graph';
end;
$test$;
rollback;

-- ═══ TEST 6: schema/security contract ════════════════════════════════════════
do $test$
declare
  v_fn text;
  v_count int := 0;
begin
  foreach v_fn in array array[
    'record_transaction_atomic',
    'update_transaction_atomic',
    'delete_transaction_atomic',
    'record_settlement_atomic',
    'reverse_settlement_atomic',
    'record_stock_adjustment_atomic'
  ] loop
    if not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = v_fn
        and array_to_string(coalesce(p.proconfig, array[]::text[]), ',') like '%search_path=%'
    ) then
      raise exception 'FAIL search_path: public.% is not pinned', v_fn;
    end if;
    v_count := v_count + 1;
  end loop;

  if has_table_privilege('authenticated', 'public.financial_audit_logs', 'INSERT')
     or has_table_privilege('authenticated', 'public.financial_audit_logs', 'UPDATE')
     or has_table_privilege('authenticated', 'public.financial_audit_logs', 'DELETE') then
    raise exception 'FAIL append-only audit: authenticated has mutation privileges';
  end if;

  if not has_table_privilege('authenticated', 'public.financial_audit_logs', 'SELECT') then
    raise exception 'FAIL audit read: authenticated lacks SELECT';
  end if;

  if has_function_privilege('anon', 'public.record_transaction_atomic(uuid,jsonb,jsonb)', 'EXECUTE') then
    raise exception 'FAIL RPC grants: anon can execute financial RPC';
  end if;

  if not has_function_privilege('authenticated', 'public.record_transaction_atomic(uuid,jsonb,jsonb)', 'EXECUTE') then
    raise exception 'FAIL RPC grants: authenticated cannot execute financial RPC';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.financial_audit_logs'::regclass
      and conname = 'financial_audit_logs_owner_request_unique'
  ) then
    raise exception 'FAIL idempotency schema: owner/request unique constraint missing';
  end if;

  raise notice 'PASS P1B contract: % RPCs pinned; audit append-only; grants and owner-scoped idempotency correct', v_count;
end;
$test$;

drop function public.terranex_test_uuid(int);

\echo '=== P1B FINANCIAL RPC SUITE: ALL CHECKS PASSED ==='
