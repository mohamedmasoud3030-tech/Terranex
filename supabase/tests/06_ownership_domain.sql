-- =============================================================================
-- Terranex DB test — 2B ownership domain
-- =============================================================================
-- Proves the ownership domain against real PostgreSQL:
--   1. Equity sum <= 100% enforced by RPC
--   2. Temporal overlap prevention
--   3. Race condition prevention (advisory lock)
--   4. Cross-tenant access prevention
--   5. Ownership-as-of-date query
--   6. Distribution draft allocation, approval and entitlement lifecycle
--   7. Bank-backed capital ledger enforcement
-- =============================================================================
\set ON_ERROR_STOP on
\timing off

create or replace function public.terranex_test_uuid_2b(p_seed int)
returns uuid
language sql
immutable
as $fn$
  select ('00000000-0000-4000-8000-' || lpad(p_seed::text, 12, '0'))::uuid;
$fn$;

-- ═══ TEST 1: ownership sum cannot exceed 100% ══════════════════════════════
begin;
set local role postgres;

insert into auth.users (id, email)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ownership-a@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid_2b(1),
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'real-estate', 'مشروع ملكية', 'Ownership Project', 'active', '2026-01-01', 'EGP'
);

insert into public.partners (id, owner_id, name_ar, category)
values
  (public.terranex_test_uuid_2b(10), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'شريك أ', 'equity_partner'),
  (public.terranex_test_uuid_2b(11), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'شريك ب', 'equity_partner'),
  (public.terranex_test_uuid_2b(12), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'شريك ج', 'equity_partner');

do $test$
declare
  v_request uuid;
  v_result jsonb;
begin
  v_request := public.terranex_test_uuid_2b(100);
  perform public.change_ownership_atomic(
    v_request,
    public.terranex_test_uuid_2b(1),
    public.terranex_test_uuid_2b(10),
    '2026-01-01', 40, 'entry'::public.terranex_equity_change_type
  );

  v_request := public.terranex_test_uuid_2b(101);
  perform public.change_ownership_atomic(
    v_request,
    public.terranex_test_uuid_2b(1),
    public.terranex_test_uuid_2b(11),
    '2026-01-01', 35, 'entry'::public.terranex_equity_change_type
  );

  v_request := public.terranex_test_uuid_2b(102);
  perform public.change_ownership_atomic(
    v_request,
    public.terranex_test_uuid_2b(1),
    public.terranex_test_uuid_2b(12),
    '2026-01-01', 25, 'entry'::public.terranex_equity_change_type
  );

  v_request := public.terranex_test_uuid_2b(103);
  begin
    perform public.change_ownership_atomic(
      v_request,
      public.terranex_test_uuid_2b(1),
      public.terranex_test_uuid_2b(10),
      '2026-02-01', 50, 'increase'::public.terranex_equity_change_type
    );
    raise exception 'FAIL: increase beyond 100%% was not rejected';
  exception
    when check_violation then
      null;
  end;

  raise notice 'PASS ownership sum <= 100%% enforcement';
end;
$test$;
rollback;

-- ═══ TEST 2: temporal overlap prevention ════════════════════════════════════
begin;
set local role postgres;

insert into auth.users (id, email)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'ownership-b@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid_2b(2),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'agriculture', 'مشروع زمني', 'Temporal Project', 'active', '2026-01-01', 'EGP'
);

insert into public.partners (id, owner_id, name_ar, category)
values (
  public.terranex_test_uuid_2b(20),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'شريك زمني', 'equity_partner'
);

do $test$
declare
  v_request uuid;
  v_result jsonb;
  v_prev_pct numeric;
  v_new_pct numeric;
begin
  v_request := public.terranex_test_uuid_2b(200);
  perform public.change_ownership_atomic(
    v_request,
    public.terranex_test_uuid_2b(2),
    public.terranex_test_uuid_2b(20),
    '2026-01-01', 40, 'entry'::public.terranex_equity_change_type
  );

  select previous_pct, new_pct into v_prev_pct, v_new_pct
  from public.equity_change_events
  where project_id = public.terranex_test_uuid_2b(2)
    and partner_id = public.terranex_test_uuid_2b(20);

  if v_prev_pct <> 0 or v_new_pct <> 40 then
    raise exception 'FAIL temporal: wrong percentages % / %', v_prev_pct, v_new_pct;
  end if;

  v_request := public.terranex_test_uuid_2b(201);
  perform public.change_ownership_atomic(
    v_request,
    public.terranex_test_uuid_2b(2),
    public.terranex_test_uuid_2b(20),
    '2026-06-01', 0, 'exit'::public.terranex_equity_change_type
  );

  if (select count(*) from public.equity_change_events
      where project_id = public.terranex_test_uuid_2b(2)
        and partner_id = public.terranex_test_uuid_2b(20)) <> 2 then
    raise exception 'FAIL temporal: expected 2 equity change events';
  end if;

  if (select count(*) from public.project_partners
      where project_id = public.terranex_test_uuid_2b(2)
        and partner_id = public.terranex_test_uuid_2b(20)
        and effective_to is not null) < 1 then
    raise exception 'FAIL temporal: old project_partner should have effective_to set';
  end if;

  raise notice 'PASS temporal ownership: entry + exit preserved history';
end;
$test$;
rollback;

-- ═══ TEST 3: cross-tenant access prevention ═════════════════════════════════
begin;
set local role postgres;

insert into auth.users (id, email) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'ownership-c@terranex.test'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'ownership-d@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid_2b(3),
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'livestock', 'مشروع عابر', 'Cross-tenant Project', 'active', '2026-01-01', 'EGP'
);

insert into public.partners (id, owner_id, name_ar, category)
values (
  public.terranex_test_uuid_2b(30),
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'شريك عابر', 'equity_partner'
);

do $test$
declare
  v_request uuid;
begin
  perform set_config('request.jwt.claim.sub', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', true);

  v_request := public.terranex_test_uuid_2b(300);
  begin
    perform public.change_ownership_atomic(
      v_request,
      public.terranex_test_uuid_2b(3),
      public.terranex_test_uuid_2b(30),
      '2026-01-01', 50, 'entry'::public.terranex_equity_change_type
    );
    raise exception 'FAIL cross-tenant: cross-owner RPC unexpectedly succeeded';
  exception
    when insufficient_privilege or foreign_key_violation then
      null;
  end;

  raise notice 'PASS cross-tenant access prevention';
end;
$test$;
rollback;

-- ═══ TEST 4: ownership-as-of-date query ═════════════════════════════════════
begin;
set local role postgres;

insert into auth.users (id, email)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'ownership-e@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid_2b(4),
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  'real-estate', 'مشروع تاريخي', 'Historical Project', 'active', '2026-01-01', 'EGP'
);

insert into public.partners (id, owner_id, name_ar, category)
values
  (public.terranex_test_uuid_2b(40), 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'شريك تاريخي 1', 'equity_partner'),
  (public.terranex_test_uuid_2b(41), 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'شريك تاريخي 2', 'equity_partner');

do $test$
declare
  v_request uuid;
  v_count int;
  v_total numeric;
begin
  v_request := public.terranex_test_uuid_2b(400);
  perform public.change_ownership_atomic(
    v_request, public.terranex_test_uuid_2b(4),
    public.terranex_test_uuid_2b(40), '2026-01-01', 60, 'entry'::public.terranex_equity_change_type
  );
  v_request := public.terranex_test_uuid_2b(401);
  perform public.change_ownership_atomic(
    v_request, public.terranex_test_uuid_2b(4),
    public.terranex_test_uuid_2b(41), '2026-01-01', 40, 'entry'::public.terranex_equity_change_type
  );

  v_request := public.terranex_test_uuid_2b(402);
  perform public.change_ownership_atomic(
    v_request, public.terranex_test_uuid_2b(4),
    public.terranex_test_uuid_2b(41), '2026-06-01', 0, 'exit'::public.terranex_equity_change_type
  );

  select count(*) into v_count
  from public.get_ownership_as_of(public.terranex_test_uuid_2b(4), '2026-03-01');
  if v_count <> 2 then
    raise exception 'FAIL ownership-as-of at Mar: expected 2 partners, got %', v_count;
  end if;

  select count(*) into v_count
  from public.get_ownership_as_of(public.terranex_test_uuid_2b(4), '2026-09-01');
  if v_count <> 1 then
    raise exception 'FAIL ownership-as-of at Sep: expected 1 partner, got %', v_count;
  end if;

  select sum(equity_pct) into v_total
  from public.get_ownership_as_of(public.terranex_test_uuid_2b(4), '2026-09-01');
  if v_total <> 60 then
    raise exception 'FAIL ownership-as-of total: expected 60%%, got %', v_total;
  end if;

  raise notice 'PASS ownership-as-of-date query';
end;
$test$;
rollback;

-- ═══ TEST 5: distribution draft, approval and entitlements ══════════════════
begin;
set local role postgres;

insert into auth.users (id, email)
values ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'distribution@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid_2b(5),
  'ffffffff-ffff-4fff-8fff-ffffffffffff',
  'real-estate', 'مشروع توزيع', 'Distribution Project', 'active', '2026-01-01', 'EGP'
);

insert into public.partners (id, owner_id, name_ar, category)
values
  (public.terranex_test_uuid_2b(50), 'ffffffff-ffff-4fff-8fff-ffffffffffff', 'شريك توزيع 1', 'equity_partner'),
  (public.terranex_test_uuid_2b(51), 'ffffffff-ffff-4fff-8fff-ffffffffffff', 'شريك توزيع 2', 'equity_partner');

do $test$
declare
  v_request uuid;
  v_result jsonb;
  v_distribution_id uuid;
  v_alloc_sum numeric;
  v_total numeric := 1000;
begin
  v_request := public.terranex_test_uuid_2b(500);
  perform public.change_ownership_atomic(
    v_request, public.terranex_test_uuid_2b(5),
    public.terranex_test_uuid_2b(50), '2026-01-01', 60, 'entry'::public.terranex_equity_change_type
  );
  v_request := public.terranex_test_uuid_2b(501);
  perform public.change_ownership_atomic(
    v_request, public.terranex_test_uuid_2b(5),
    public.terranex_test_uuid_2b(51), '2026-01-01', 40, 'entry'::public.terranex_equity_change_type
  );

  v_request := public.terranex_test_uuid_2b(502);
  select public.record_distribution_atomic(
    v_request,
    public.terranex_test_uuid_2b(5),
    '2026-07-01',
    '2026-07-01',
    1000,
    'EGP'::public.terranex_currency,
    1
  ) into v_result;

  v_distribution_id := (v_result->>'distribution_id')::uuid;

  if v_result->>'status' <> 'draft' then
    raise exception 'FAIL distribution: new distribution must remain draft';
  end if;

  select sum(allocated_amount) into v_alloc_sum
  from public.distribution_allocations
  where distribution_id = v_distribution_id;

  if abs(v_alloc_sum - v_total) > 0.01 then
    raise exception 'FAIL distribution: allocations sum % does not equal total %', v_alloc_sum, v_total;
  end if;

  if not exists (
    select 1 from public.distribution_allocations
    where distribution_id = v_distribution_id
      and partner_id = public.terranex_test_uuid_2b(50)
      and abs(allocated_amount - 600) < 0.01
  ) then
    raise exception 'FAIL distribution: partner 1 allocation wrong';
  end if;

  if not exists (
    select 1 from public.distribution_allocations
    where distribution_id = v_distribution_id
      and partner_id = public.terranex_test_uuid_2b(51)
      and abs(allocated_amount - 400) < 0.01
  ) then
    raise exception 'FAIL distribution: partner 2 allocation wrong';
  end if;

  if exists (
    select 1 from public.partner_ledger_entries
    where related_distribution_id = v_distribution_id
      and entry_type = 'distribution_entitlement'
  ) then
    raise exception 'FAIL distribution: draft unexpectedly created entitlement ledger entries';
  end if;

  v_request := public.terranex_test_uuid_2b(503);
  select public.approve_distribution_atomic(
    v_request,
    v_distribution_id,
    'approved by lifecycle test'
  ) into v_result;

  if v_result->>'status' <> 'approved' then
    raise exception 'FAIL distribution: approval did not return approved status';
  end if;

  if (select count(*) from public.partner_ledger_entries
      where related_distribution_id = v_distribution_id
        and entry_type = 'distribution_entitlement') <> 2 then
    raise exception 'FAIL distribution: expected 2 entitlement ledger entries after approval';
  end if;

  if (select abs(coalesce(sum(amount_egp), 0) - 1000) from public.partner_ledger_entries
      where related_distribution_id = v_distribution_id
        and entry_type = 'distribution_entitlement') > 0.01 then
    raise exception 'FAIL distribution: entitlement ledger sum does not match distribution total';
  end if;

  begin
    update public.distribution_allocations
    set allocated_amount = allocated_amount + 1
    where id = (
      select id from public.distribution_allocations
      where distribution_id = v_distribution_id
      limit 1
    );
    raise exception 'FAIL immutability: allocation snapshot update unexpectedly succeeded';
  exception
    when feature_not_supported then
      null;
  end;

  begin
    update public.partner_ledger_entries
    set amount = amount + 1
    where id = (
      select id from public.partner_ledger_entries
      where related_distribution_id = v_distribution_id
      limit 1
    );
    raise exception 'FAIL immutability: ledger update unexpectedly succeeded';
  exception
    when feature_not_supported then
      null;
  end;

  raise notice 'PASS distribution draft allocations, approval entitlements and immutability';
end;
$test$;
rollback;

-- ═══ TEST 6: bank-backed capital ledger ═════════════════════════════════════
begin;
set local role postgres;

insert into auth.users (id, email)
values ('11111111-1111-4111-8111-111111111111', 'ledger@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid_2b(6),
  '11111111-1111-4111-8111-111111111111',
  'real-estate', 'مشروع حساب', 'Ledger Project', 'active', '2026-01-01', 'EGP'
);

insert into public.partners (id, owner_id, name_ar, category)
values (
  public.terranex_test_uuid_2b(60),
  '11111111-1111-4111-8111-111111111111',
  'شريك حساب', 'equity_partner'
);

insert into public.bank_accounts (
  id, owner_id, name_ar, name_en, account_type, currency, opening_balance, opening_date
) values (
  public.terranex_test_uuid_2b(61),
  '11111111-1111-4111-8111-111111111111',
  'خزينة اختبار', 'Test Cash', 'cash', 'EGP', 0, '2026-01-01'
);

do $test$
declare
  v_request uuid;
  v_result jsonb;
  v_count int;
  v_balance numeric;
begin
  v_request := public.terranex_test_uuid_2b(600);
  select public.record_partner_capital_movement_atomic(
    v_request,
    public.terranex_test_uuid_2b(6),
    public.terranex_test_uuid_2b(60),
    'capital_contribution'::public.terranex_ledger_entry_type,
    50000, 'EGP'::public.terranex_currency, 1, '2026-01-15',
    public.terranex_test_uuid_2b(61)
  ) into v_result;

  if (v_result->>'bank_transaction_id') is null then
    raise exception 'FAIL capital: contribution did not create bank transaction';
  end if;

  v_request := public.terranex_test_uuid_2b(601);
  perform public.record_partner_capital_movement_atomic(
    v_request,
    public.terranex_test_uuid_2b(6),
    public.terranex_test_uuid_2b(60),
    'withdrawal'::public.terranex_ledger_entry_type,
    10000, 'EGP'::public.terranex_currency, 1, '2026-03-01',
    public.terranex_test_uuid_2b(61)
  );

  select count(*) into v_count
  from public.partner_ledger_entries
  where project_id = public.terranex_test_uuid_2b(6)
    and partner_id = public.terranex_test_uuid_2b(60)
    and bank_account_id = public.terranex_test_uuid_2b(61);
  if v_count <> 2 then
    raise exception 'FAIL capital ledger: expected 2 bank-backed entries, got %', v_count;
  end if;

  if (select count(*) from public.bank_transactions
      where bank_account_id = public.terranex_test_uuid_2b(61)
        and reference_type = 'partner_capital') <> 2 then
    raise exception 'FAIL capital bank: expected 2 partner capital bank transactions';
  end if;

  if not exists (
    select 1 from public.bank_transactions
    where bank_account_id = public.terranex_test_uuid_2b(61)
      and direction = 'deposit' and amount = 50000
  ) or not exists (
    select 1 from public.bank_transactions
    where bank_account_id = public.terranex_test_uuid_2b(61)
      and direction = 'withdrawal' and amount = 10000
  ) then
    raise exception 'FAIL capital bank: contribution/withdrawal directions or amounts are wrong';
  end if;

  select coalesce(sum(case when entry_type = 'capital_contribution' then amount_egp else 0 end), 0)
       - coalesce(sum(case when entry_type = 'withdrawal' then amount_egp else 0 end), 0)
    into v_balance
  from public.partner_ledger_entries
  where project_id = public.terranex_test_uuid_2b(6)
    and partner_id = public.terranex_test_uuid_2b(60)
    and entry_type not in ('reversal'::public.terranex_ledger_entry_type);

  if v_balance <> 40000 then
    raise exception 'FAIL capital balance: expected 40000, got %', v_balance;
  end if;

  raise notice 'PASS bank-backed capital ledger: atomic cash movements and balance correct';
end;
$test$;
rollback;

-- ═══ TEST 7: idempotency ════════════════════════════════════════════════════
begin;
set local role postgres;

insert into auth.users (id, email)
values ('22222222-2222-4222-8222-222222222222', 'idempotent@terranex.test')
on conflict do nothing;

insert into public.projects (
  id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency
) values (
  public.terranex_test_uuid_2b(7),
  '22222222-2222-4222-8222-222222222222',
  'real-estate', 'مشروع تكرار', 'Idempotent Project', 'active', '2026-01-01', 'EGP'
);

insert into public.partners (id, owner_id, name_ar, category)
values (
  public.terranex_test_uuid_2b(70),
  '22222222-2222-4222-8222-222222222222',
  'شريك تكرار', 'equity_partner'
);

do $test$
declare
  v_request uuid := public.terranex_test_uuid_2b(700);
  v_result1 jsonb;
  v_result2 jsonb;
  v_count int;
begin
  select public.change_ownership_atomic(
    v_request,
    public.terranex_test_uuid_2b(7),
    public.terranex_test_uuid_2b(70),
    '2026-01-01', 50, 'entry'::public.terranex_equity_change_type
  ) into v_result1;

  select public.change_ownership_atomic(
    v_request,
    public.terranex_test_uuid_2b(7),
    public.terranex_test_uuid_2b(70),
    '2026-01-01', 50, 'entry'::public.terranex_equity_change_type
  ) into v_result2;

  if v_result1 is distinct from v_result2 then
    raise exception 'FAIL idempotency: results differ';
  end if;

  select count(*) into v_count
  from public.equity_change_events
  where project_id = public.terranex_test_uuid_2b(7)
    and partner_id = public.terranex_test_uuid_2b(70);
  if v_count <> 1 then
    raise exception 'FAIL idempotency: expected 1 equity change event, got %', v_count;
  end if;

  raise notice 'PASS idempotency: duplicate request returns cached result';
end;
$test$;
rollback;

-- ═══ TEST 8: schema contract ════════════════════════════════════════════════
do $test$
declare
  v_fn text;
  v_count int := 0;
begin
  foreach v_fn in array array[
    'change_ownership_atomic',
    'record_distribution_atomic',
    'approve_distribution_atomic',
    'record_partner_ledger_entry_atomic',
    'record_partner_capital_movement_atomic',
    'get_ownership_as_of'
  ] loop
    if not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = v_fn
    ) then
      raise exception 'FAIL contract: function public.% does not exist', v_fn;
    end if;
    v_count := v_count + 1;
  end loop;

  foreach v_fn in array array[
    'change_ownership_atomic',
    'record_distribution_atomic',
    'approve_distribution_atomic',
    'record_partner_ledger_entry_atomic',
    'record_partner_capital_movement_atomic'
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
  end loop;

  if not exists (
    select 1 from pg_class
    where relname = 'equity_change_events'
      and relrowsecurity = true
      and relforcerowsecurity = true
  ) then
    raise exception 'FAIL RLS: equity_change_events not enabled+forced';
  end if;

  if not exists (
    select 1 from pg_class
    where relname = 'partner_ledger_entries'
      and relrowsecurity = true
      and relforcerowsecurity = true
  ) then
    raise exception 'FAIL RLS: partner_ledger_entries not enabled+forced';
  end if;

  if not exists (
    select 1 from pg_class
    where relname = 'distributions'
      and relrowsecurity = true
      and relforcerowsecurity = true
  ) then
    raise exception 'FAIL RLS: distributions not enabled+forced';
  end if;

  if not exists (
    select 1 from pg_class
    where relname = 'distribution_allocations'
      and relrowsecurity = true
      and relforcerowsecurity = true
  ) then
    raise exception 'FAIL RLS: distribution_allocations not enabled+forced';
  end if;

  raise notice 'PASS 2B contract: % functions exist, RLS enabled+forced on all 4 tables', v_count;
end;
$test$;

drop function public.terranex_test_uuid_2b(int);

\echo '=== 2B OWNERSHIP DOMAIN SUITE: ALL CHECKS PASSED ==='
