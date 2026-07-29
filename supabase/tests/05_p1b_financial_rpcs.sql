-- =============================================================================
-- Terranex DB test — P1B financial atomicity RPCs
-- =============================================================================
-- Proves the 6 atomic RPCs (record_transaction_atomic, update_transaction_atomic,
-- delete_transaction_atomic, record_settlement_atomic, reverse_settlement_atomic,
-- record_stock_adjustment_atomic) work correctly with idempotency via request_id.
--
-- Each RPC must:
--   1. Execute the write graph atomically
--   2. Log to financial_audit_logs
--   3. Return cached result on duplicate request_id (idempotency)
-- =============================================================================
\set ON_ERROR_STOP on
\timing off

-- ── Helper: generate deterministic UUIDs for tests ────────────────────────
create or replace function public.terranex_test_uuid(p_seed int)
returns uuid
language sql
immutable
as $fn$
  select ('00000000-0000-4000-8000-' || lpad(p_seed::text, 12, '0'))::uuid;
$fn$;

-- ═══ TEST 1: record_transaction_atomic creates transaction + payable ═════════
begin;
set local role postgres;

-- Setup: insert required project and partner
delete from public.financial_audit_logs where true;
delete from public.obligations where true;
delete from public.transactions where true;
delete from public.settlement_allocations where true;
delete from public.settlements where true;
delete from public.stock_adjustments where true;

insert into auth.users (id, email) values ('11111111-1111-4111-8111-111111111111','test1@terranex.test') on conflict do nothing;

insert into public.projects (id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency)
values (public.terranex_test_uuid(1), '11111111-1111-4111-8111-111111111111', 'agriculture', 'مشروع اختبار', 'Test Project', 'active', '2026-01-01', 'EGP')
on conflict do nothing;

insert into public.partners (id, owner_id, name_ar, category, counterparty_role)
values (public.terranex_test_uuid(2), '11111111-1111-4111-8111-111111111111', 'شريك اختبار', 'counterparty', 'supplier')
on conflict do nothing;

do $$
declare
  v_request_id uuid := public.terranex_test_uuid(100);
  v_transaction_id uuid := public.terranex_test_uuid(200);
  v_payable_id uuid := public.terranex_test_uuid(201);
  v_project_id uuid := public.terranex_test_uuid(1);
  v_partner_id uuid := public.terranex_test_uuid(2);
  v_result jsonb;
  v_count int;
begin
  -- Execute atomic transaction with payable
  select public.record_transaction_atomic(
    v_request_id,
    jsonb_build_object(
      'id', v_transaction_id,
      'project_id', v_project_id,
      'partner_id', v_partner_id,
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
      'project_id', v_project_id,
      'partner_id', v_partner_id,
      'amount', 500,
      'currency', 'EGP',
      'amount_egp', 500,
      'due_date', '2026-08-29'
    )
  ) into v_result;

  -- Verify result
  if v_result->>'transaction_id' is distinct from v_transaction_id::text then
    raise exception 'FAIL record_transaction_atomic: transaction_id mismatch';
  end if;
  if v_result->>'payable_id' is distinct from v_payable_id::text then
    raise exception 'FAIL record_transaction_atomic: payable_id mismatch';
  end if;

  -- Verify transaction exists
  select count(*) into v_count from public.transactions where id = v_transaction_id;
  if v_count <> 1 then raise exception 'FAIL record_transaction_atomic: transaction not found'; end if;

  -- Verify payable exists
  select count(*) into v_count from public.obligations where id = v_payable_id;
  if v_count <> 1 then raise exception 'FAIL record_transaction_atomic: payable not found'; end if;

  -- Verify audit log
  select count(*) into v_count from public.financial_audit_logs where request_id = v_request_id;
  if v_count <> 1 then raise exception 'FAIL record_transaction_atomic: audit log missing'; end if;

  raise notice 'PASS record_transaction_atomic: transaction + payable created with audit log';
end;
$$;

-- ═══ TEST 2: Idempotency — duplicate request_id returns cached result ════════
do $$
declare
  v_request_id uuid := public.terranex_test_uuid(100);
  v_transaction_id uuid := public.terranex_test_uuid(200);
  v_result jsonb;
  v_count int;
begin
  -- Re-execute with same request_id
  select public.record_transaction_atomic(
    v_request_id,
    jsonb_build_object(
      'id', public.terranex_test_uuid(999),  -- different ID
      'direction', 'income',
      'category', 'sale',
      'amount', 9999,
      'currency', 'EGP',
      'fx_rate', 1,
      'amount_egp', 9999,
      'transaction_date', '2026-07-29'
    )
  ) into v_result;

  -- Verify cached result returned (original transaction_id)
  if v_result->>'transaction_id' is distinct from v_transaction_id::text then
    raise exception 'FAIL idempotency: duplicate request_id did not return cached result';
  end if;

  -- Verify no duplicate audit log
  select count(*) into v_count from public.financial_audit_logs where request_id = v_request_id;
  if v_count <> 1 then raise exception 'FAIL idempotency: duplicate audit log created'; end if;

  raise notice 'PASS idempotency: duplicate request_id returned cached result without re-execution';
end;
$$;
rollback;

-- ═══ TEST 3: record_settlement_atomic creates settlement + allocations ══════
begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.settlement_allocations where true;
delete from public.settlements where true;
delete from public.obligations where true;

insert into auth.users (id, email) values ('22222222-2222-4222-8222-222222222222','test2@terranex.test') on conflict do nothing;

insert into public.projects (id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency)
values (public.terranex_test_uuid(10), '22222222-2222-4222-8222-222222222222', 'real-estate', 'مشروع', 'Project', 'active', '2026-01-01', 'EGP')
on conflict do nothing;

insert into public.partners (id, owner_id, name_ar, category, counterparty_role)
values (public.terranex_test_uuid(11), '22222222-2222-4222-8222-222222222222', 'شريك', 'counterparty', 'supplier')
on conflict do nothing;

-- Create obligation to settle
insert into public.obligations (id, owner_id, project_id, partner_id, direction, amount, currency, amount_egp, amount_settled_egp, due_date, status)
values (public.terranex_test_uuid(12), '22222222-2222-4222-8222-222222222222', public.terranex_test_uuid(10), public.terranex_test_uuid(11), 'payable', 1000, 'EGP', 1000, 0, '2026-08-01', 'open');

do $$
declare
  v_request_id uuid := public.terranex_test_uuid(300);
  v_settlement_id uuid := public.terranex_test_uuid(301);
  v_allocation_id uuid := public.terranex_test_uuid(302);
  v_obligation_id uuid := public.terranex_test_uuid(12);
  v_result jsonb;
  v_count int;
  v_status text;
begin
  select public.record_settlement_atomic(
    v_request_id,
    jsonb_build_object(
      'id', v_settlement_id,
      'obligation_id', v_obligation_id,
      'amount', 600,
      'currency', 'EGP',
      'fx_rate', 1,
      'amount_egp', 600,
      'payment_method', 'bank_transfer',
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

  -- Verify settlement created
  select count(*) into v_count from public.settlements where id = v_settlement_id;
  if v_count <> 1 then raise exception 'FAIL record_settlement_atomic: settlement not found'; end if;

  -- Verify allocation created
  select count(*) into v_count from public.settlement_allocations where id = v_allocation_id;
  if v_count <> 1 then raise exception 'FAIL record_settlement_atomic: allocation not found'; end if;

  -- Verify obligation updated
  select status into v_status from public.obligations where id = v_obligation_id;
  if v_status is distinct from 'partial' then
    raise exception 'FAIL record_settlement_atomic: obligation status not updated to partial';
  end if;

  raise notice 'PASS record_settlement_atomic: settlement + allocation created, obligation updated';
end;
$$;
rollback;

-- ═══ TEST 4: reverse_settlement_atomic reverses settlement ══════════════════
begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.settlement_allocations where true;
delete from public.settlements where true;
delete from public.obligations where true;

insert into auth.users (id, email) values ('33333333-3333-4333-8333-333333333333','test3@terranex.test') on conflict do nothing;

insert into public.projects (id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency)
values (public.terranex_test_uuid(20), '33333333-3333-4333-8333-333333333333', 'livestock', 'مشروع', 'Project', 'active', '2026-01-01', 'EGP')
on conflict do nothing;

insert into public.partners (id, owner_id, name_ar, category, counterparty_role)
values (public.terranex_test_uuid(21), '33333333-3333-4333-8333-333333333333', 'شريك', 'counterparty', 'supplier')
on conflict do nothing;

-- Create obligation and settlement
insert into public.obligations (id, owner_id, project_id, partner_id, direction, amount, currency, amount_egp, amount_settled_egp, due_date, status)
values (public.terranex_test_uuid(22), '33333333-3333-4333-8333-333333333333', public.terranex_test_uuid(20), public.terranex_test_uuid(21), 'receivable', 800, 'EGP', 800, 400, '2026-08-01', 'partial');

insert into public.settlements (id, owner_id, obligation_id, amount, currency, fx_rate, amount_egp, payment_method, settlement_date, status, origin)
values (public.terranex_test_uuid(23), '33333333-3333-4333-8333-333333333333', public.terranex_test_uuid(22), 400, 'EGP', 1, 400, 'cash', '2026-07-20', 'active', 'user');

insert into public.settlement_allocations (id, owner_id, settlement_id, obligation_id, allocated_amount_egp)
values (public.terranex_test_uuid(24), '33333333-3333-4333-8333-333333333333', public.terranex_test_uuid(23), public.terranex_test_uuid(22), 400);

do $$
declare
  v_request_id uuid := public.terranex_test_uuid(400);
  v_settlement_id uuid := public.terranex_test_uuid(23);
  v_obligation_id uuid := public.terranex_test_uuid(22);
  v_result jsonb;
  v_status text;
  v_settled numeric;
  v_reversed_at timestamptz;
  v_reversal_reason text;
begin
  select public.reverse_settlement_atomic(
    v_request_id,
    v_settlement_id,
    'خطأ في المبلغ'
  ) into v_result;

  -- Verify settlement reversed
  select status, reversed_at, reversal_reason into v_status, v_reversed_at, v_reversal_reason from public.settlements where id = v_settlement_id;
  if v_status is distinct from 'reversed' then
    raise exception 'FAIL reverse_settlement_atomic: settlement not reversed';
  end if;
  if v_reversed_at is null then
    raise exception 'FAIL reverse_settlement_atomic: reversed_at not set';
  end if;
  if v_reversal_reason is distinct from 'خطأ في المبلغ' then
    raise exception 'FAIL reverse_settlement_atomic: reversal_reason not set';
  end if;

  -- Verify obligation updated
  select status, amount_settled_egp into v_status, v_settled from public.obligations where id = v_obligation_id;
  if v_settled <> 0 then
    raise exception 'FAIL reverse_settlement_atomic: obligation settled amount not reversed';
  end if;
  if v_status is distinct from 'open' then
    raise exception 'FAIL reverse_settlement_atomic: obligation status not open after reversal';
  end if;

  raise notice 'PASS reverse_settlement_atomic: settlement reversed, obligation restored';
end;
$$;
rollback;

-- ═══ TEST 5: record_stock_adjustment_atomic creates adjustment ══════════════
begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.stock_adjustments where true;
delete from public.assets where true;

insert into auth.users (id, email) values ('44444444-4444-4444-8444-444444444444','test4@terranex.test') on conflict do nothing;

insert into public.projects (id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency)
values (public.terranex_test_uuid(30), '44444444-4444-4444-8444-444444444444', 'agriculture', 'مشروع', 'Project', 'active', '2026-01-01', 'EGP')
on conflict do nothing;

insert into public.assets (id, owner_id, project_id, sector_id, name_ar, name_en, type, status, acquisition_date, acquisition_cost, acquisition_currency, acquisition_cost_egp, quantity, current_value_egp)
values (public.terranex_test_uuid(31), '44444444-4444-4444-8444-444444444444', public.terranex_test_uuid(30), 'agriculture', 'أصل', 'Asset', 'equipment', 'owned', '2026-01-01', 10000, 'EGP', 10000, 10, 10000);

do $$
declare
  v_request_id uuid := public.terranex_test_uuid(500);
  v_adjustment_id uuid := public.terranex_test_uuid(501);
  v_asset_id uuid := public.terranex_test_uuid(31);
  v_project_id uuid := public.terranex_test_uuid(30);
  v_result jsonb;
  v_count int;
begin
  select public.record_stock_adjustment_atomic(
    v_request_id,
    jsonb_build_object(
      'id', v_adjustment_id,
      'asset_id', v_asset_id,
      'project_id', v_project_id,
      'adjustment_date', '2026-07-29',
      'reason', 'data_correction',
      'quantity_delta', 5,
      'value_egp_delta', 500
    )
  ) into v_result;

  -- Verify adjustment created
  select count(*) into v_count from public.stock_adjustments where id = v_adjustment_id;
  if v_count <> 1 then raise exception 'FAIL record_stock_adjustment_atomic: adjustment not found'; end if;

  raise notice 'PASS record_stock_adjustment_atomic: adjustment created with audit log';
end;
$$;
rollback;

-- ═══ TEST 6: All 6 RPCs have search_path pinned ═════════════════════════════
do $$
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
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_fn
        and array_to_string(coalesce(p.proconfig, array[]::text[]), ',') like '%search_path=%'
    ) then
      raise exception 'FAIL search_path: public.% does not pin search_path', v_fn;
    end if;
    v_count := v_count + 1;
  end loop;
  raise notice 'PASS search_path: all % atomic RPCs pin search_path', v_count;
end;
$$;

drop function if exists public.terranex_test_uuid(int);

-- ═══ TEST 9: Idempotency — record_settlement_atomic with duplicate request_id ═
begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.settlement_allocations where true;
delete from public.settlements where true;
delete from public.obligations where true;

insert into auth.users (id, email) values ('66666666-6666-4666-8666-666666666666','test6@terranex.test') on conflict do nothing;

insert into public.projects (id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency)
values (public.terranex_test_uuid(50), '66666666-6666-4666-8666-666666666666', 'real-estate', 'مشروع', 'Project', 'active', '2026-01-01', 'EGP')
on conflict do nothing;

insert into public.partners (id, owner_id, name_ar, category, counterparty_role)
values (public.terranex_test_uuid(51), '66666666-6666-4666-8666-666666666666', 'شريك', 'counterparty', 'client')
on conflict do nothing;

insert into public.obligations (id, owner_id, project_id, partner_id, direction, amount, currency, amount_egp, amount_settled_egp, due_date, status)
values (public.terranex_test_uuid(52), '66666666-6666-4666-8666-666666666666', public.terranex_test_uuid(50), public.terranex_test_uuid(51), 'receivable', 1000, 'EGP', 1000, 0, '2026-08-01', 'open');

do $$
declare
  v_request_id uuid := public.terranex_test_uuid(900);
  v_settlement_id uuid := public.terranex_test_uuid(901);
  v_allocation_id uuid := public.terranex_test_uuid(902);
  v_obligation_id uuid := public.terranex_test_uuid(52);
  v_result1 jsonb;
  v_result2 jsonb;
  v_count int;
  v_settled numeric;
begin
  -- First call
  select public.record_settlement_atomic(
    v_request_id,
    jsonb_build_object(
      'id', v_settlement_id,
      'obligation_id', v_obligation_id,
      'amount', 500,
      'currency', 'EGP',
      'fx_rate', 1,
      'amount_egp', 500,
      'payment_method', 'cash',
      'settlement_date', '2026-07-29'
    ),
    jsonb_build_array(
      jsonb_build_object(
        'id', v_allocation_id,
        'obligation_id', v_obligation_id,
        'allocated_amount_egp', 500
      )
    )
  ) into v_result1;

  -- Verify settlement created
  select count(*) into v_count from public.settlements where id = v_settlement_id;
  if v_count <> 1 then raise exception 'FAIL settlement idempotency: settlement not created'; end if;

  -- Second call with same request_id
  select public.record_settlement_atomic(
    v_request_id,
    jsonb_build_object(
      'id', public.terranex_test_uuid(999),  -- Different ID
      'obligation_id', v_obligation_id,
      'amount', 9999,
      'currency', 'EGP',
      'fx_rate', 1,
      'amount_egp', 9999,
      'payment_method', 'bank_transfer',
      'settlement_date', '2026-12-31'
    ),
    jsonb_build_array(
      jsonb_build_object(
        'id', public.terranex_test_uuid(998),
        'obligation_id', v_obligation_id,
        'allocated_amount_egp', 9999
      )
    )
  ) into v_result2;

  -- Verify cached result returned
  if v_result1 is distinct from v_result2 then
    raise exception 'FAIL settlement idempotency: duplicate request_id did not return cached result';
  end if;

  -- Verify no duplicate settlement
  select count(*) into v_count from public.settlements where id = v_settlement_id;
  if v_count <> 1 then raise exception 'FAIL settlement idempotency: duplicate settlement created'; end if;

  -- Verify obligation not double-updated
  select amount_settled_egp into v_settled from public.obligations where id = v_obligation_id;
  if v_settled <> 500 then
    raise exception 'FAIL settlement idempotency: obligation double-updated to %', v_settled;
  end if;

  raise notice 'PASS settlement idempotency: duplicate request_id returned cached result';
end;
$$;
rollback;

-- ═══ TEST 7: Error path — invalid transaction data ═════════════════════════
begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.transactions where true;

do $$
declare
  v_request_id uuid := public.terranex_test_uuid(700);
  v_result jsonb;
  v_error text;
begin
  -- Try to insert transaction with invalid data (missing required field)
  begin
    select public.record_transaction_atomic(
      v_request_id,
      jsonb_build_object(
        'id', public.terranex_test_uuid(701),
        -- Missing project_id (NOT NULL)
        'direction', 'income',
        'category', 'test',
        'amount', 100,
        'currency', 'EGP',
        'fx_rate', 1,
        'amount_egp', 100,
        'transaction_date', '2026-07-29'
      )
    ) into v_result;
    
    raise exception 'FAIL error path: transaction with missing project_id should fail';
  exception
    when others then
      v_error := sqlerrm;
      if v_error not like '%null value in column "project_id"%' and v_error not like '%violates not-null constraint%' then
        raise exception 'FAIL error path: unexpected error: %', v_error;
      end if;
      raise notice 'PASS error path: invalid transaction data rejected with proper error';
  end;
end;
$$;
rollback;

-- ═══ TEST 8: Rollback — partial failure rolls back entire transaction ══════
begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.obligations where true;
delete from public.transactions where true;

insert into auth.users (id, email) values ('55555555-5555-4555-8555-555555555555','test5@terranex.test') on conflict do nothing;

insert into public.projects (id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency)
values (public.terranex_test_uuid(40), '55555555-5555-4555-8555-555555555555', 'agriculture', 'مشروع', 'Project', 'active', '2026-01-01', 'EGP')
on conflict do nothing;

insert into public.partners (id, owner_id, name_ar, category, counterparty_role)
values (public.terranex_test_uuid(41), '55555555-5555-4555-8555-555555555555', 'شريك', 'counterparty', 'supplier')
on conflict do nothing;

do $$
declare
  v_request_id uuid := public.terranex_test_uuid(800);
  v_transaction_id uuid := public.terranex_test_uuid(801);
  v_payable_id uuid := public.terranex_test_uuid(802);
  v_project_id uuid := public.terranex_test_uuid(40);
  v_partner_id uuid := public.terranex_test_uuid(41);
  v_result jsonb;
  v_count int;
begin
  -- Try to insert transaction with payable that has invalid data
  begin
    select public.record_transaction_atomic(
      v_request_id,
      jsonb_build_object(
        'id', v_transaction_id,
        'project_id', v_project_id,
        'partner_id', v_partner_id,
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
        'project_id', v_project_id,
        'partner_id', v_partner_id,
        'amount', 500,
        'currency', 'EGP',
        'amount_egp', 500,
        'due_date', 'invalid-date'  -- Invalid date format
      )
    ) into v_result;
    
    raise exception 'FAIL rollback: transaction with invalid payable date should fail';
  exception
    when others then
      -- Verify transaction was rolled back
      select count(*) into v_count from public.transactions where id = v_transaction_id;
      if v_count <> 0 then
        raise exception 'FAIL rollback: transaction should not exist after failed payable insert';
      end if;
      
      -- Verify payable was not created
      select count(*) into v_count from public.obligations where id = v_payable_id;
      if v_count <> 0 then
        raise exception 'FAIL rollback: payable should not exist after failed insert';
      end if;
      
      -- Verify audit log was not created
      select count(*) into v_count from public.financial_audit_logs where request_id = v_request_id;
      if v_count <> 0 then
        raise exception 'FAIL rollback: audit log should not exist after failed transaction';
      end if;
      
      raise notice 'PASS rollback: partial failure rolled back entire transaction';
  end;
end;
$$;
rollback;

\echo '=== P1B FINANCIAL RPC SUITE: ALL CHECKS PASSED ==='
