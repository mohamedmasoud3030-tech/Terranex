-- =============================================================================
-- Terranex DB test — guard_*_deletion RPCs
-- =============================================================================
-- Verifies real blocking behaviour AND byte-exact Arabic messages. The expected
-- strings below are copied from tests/helpers/fakeSupabase.cjs (RPC_HANDLERS),
-- which is the behavioural spec inherited from the pre-Supabase localStorage
-- guards. If SQL and client fake ever diverge, this test fails.
-- =============================================================================
\set ON_ERROR_STOP on

begin;
set local role postgres;

delete from public.financial_audit_logs where true;
delete from public.settlement_allocations where true; delete from public.settlements where true;
delete from public.obligations where true; delete from public.operational_events where true;
delete from public.stock_adjustments where true; delete from public.transactions where true;
delete from public.documents where true; delete from public.project_partners where true;
delete from public.assets where true; delete from public.partners where true; delete from public.projects where true;
delete from auth.users where true;

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@terranex.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@terranex.test');

set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

-- ── 1. Clean entity: every guard allows deletion, with the exact message ─────
do $$
declare v_ok boolean; v_msg text;
begin
  insert into public.projects (id, sector_id, name_ar, name_en, status, start_date, base_currency)
  values ('11111111-1111-4111-8111-111111111111','real-estate','مشروع','P','active','2026-01-01','EGP');

  select can_delete, message_ar into v_ok, v_msg
  from public.guard_project_deletion('11111111-1111-4111-8111-111111111111');

  if not v_ok then raise exception 'FAIL: clean project should be deletable, got: %', v_msg; end if;
  if v_msg <> 'يمكن حذف المشروع بعد التأكيد. لا توجد روابط تشغيلية تمنع الحذف.' then
    raise exception 'FAIL message mismatch (allow). Got: %', v_msg;
  end if;
  raise notice 'PASS guard/project: clean project deletable, message exact';
end;
$$;

-- ── 2. Blocked by a single relation, count and label rendered correctly ──────
do $$
declare v_ok boolean; v_msg text;
begin
  insert into public.partners (id, name_ar, category)
  values ('22222222-2222-4222-8222-222222222222','شريك','equity_partner');
  insert into public.documents (id, project_id, type, title_ar)
  values ('55555555-5555-4555-8555-555555555555','11111111-1111-4111-8111-111111111111','contract','عقد');
  insert into public.transactions (id, project_id, partner_id, document_id, direction, category,
                                   amount, currency, fx_rate, amount_egp, transaction_date)
  values ('66666666-6666-4666-8666-666666666666','11111111-1111-4111-8111-111111111111',
          '22222222-2222-4222-8222-222222222222','55555555-5555-4555-8555-555555555555',
          'income','sale',100,'EGP',1,100,'2026-01-01');

  select can_delete, message_ar into v_ok, v_msg
  from public.guard_project_deletion('11111111-1111-4111-8111-111111111111');

  if v_ok then raise exception 'FAIL: project with linked records must be blocked'; end if;
  -- transactions(1), documents(1) both reference the project
  if v_msg <> 'لا يمكن حذف المشروع لأنه مرتبط بسجلات مالية أو تشغيلية. افصل أو عالج الروابط أولاً: معاملات: 1، مستندات: 1.' then
    raise exception 'FAIL message mismatch (block/project). Got: %', v_msg;
  end if;
  raise notice 'PASS guard/project: blocked with "معاملات: 1، مستندات: 1"';
end;
$$;

-- ── 3. transaction guard: obligations + operational events (the P0 case) ─────
do $$
declare v_ok boolean; v_msg text;
begin
  select can_delete, message_ar into v_ok, v_msg
  from public.guard_transaction_deletion('66666666-6666-4666-8666-666666666666');
  if not v_ok then raise exception 'FAIL: unlinked transaction should be deletable, got %', v_msg; end if;
  raise notice 'PASS guard/transaction: unlinked transaction deletable';

  insert into public.obligations (id, project_id, partner_id, direction, amount, currency,
                                  amount_egp, status, source_transaction_id)
  values ('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111',
          '22222222-2222-4222-8222-222222222222','payable',50,'EGP',50,'open',
          '66666666-6666-4666-8666-666666666666');

  select can_delete, message_ar into v_ok, v_msg
  from public.guard_transaction_deletion('66666666-6666-4666-8666-666666666666');
  if v_ok then raise exception 'FAIL: transaction with dependent obligation must be blocked'; end if;
  if v_msg not like '%التزامات: 1%' then
    raise exception 'FAIL: expected "التزامات: 1" in message. Got: %', v_msg;
  end if;
  raise notice 'PASS guard/transaction: blocked by "التزامات: 1"';

  insert into public.assets (id, project_id, sector_id, type, name_ar, name_en, acquisition_date,
                             acquisition_cost, acquisition_currency, acquisition_cost_egp, status)
  values ('77777777-7777-4777-8777-777777777777','11111111-1111-4111-8111-111111111111',
          'livestock','herd','قطيع','Herd','2026-01-01',1000,'EGP',1000,'owned');
  insert into public.operational_events (id, asset_id, project_id, type, event_date, linked_transaction_id)
  values ('aaaa1111-1111-4111-8111-111111111111','77777777-7777-4777-8777-777777777777',
          '11111111-1111-4111-8111-111111111111','birth','2026-01-02','66666666-6666-4666-8666-666666666666');

  select can_delete, message_ar into v_ok, v_msg
  from public.guard_transaction_deletion('66666666-6666-4666-8666-666666666666');
  if v_msg not like '%أحداث تشغيلية: 1%' then
    raise exception 'FAIL: expected "أحداث تشغيلية: 1". Got: %', v_msg;
  end if;
  raise notice 'PASS guard/transaction: blocked by "التزامات: 1، أحداث تشغيلية: 1"';
end;
$$;

-- ── 4. document guard: settlements reference via receipt_document_id ─────────
do $$
declare v_ok boolean; v_msg text;
begin
  insert into public.documents (id, project_id, partner_id, type, title_ar)
  values ('99999999-9999-4999-8999-999999999999','11111111-1111-4111-8111-111111111111',
          '22222222-2222-4222-8222-222222222222','receipt','إيصال');

  select can_delete into v_ok from public.guard_document_deletion('99999999-9999-4999-8999-999999999999');
  if not v_ok then raise exception 'FAIL: unreferenced receipt should be deletable'; end if;

  insert into public.settlements (id, obligation_id, amount, currency, fx_rate, amount_egp,
                                  settlement_date, payment_method, receipt_document_id)
  values ('44444444-4444-4444-8444-444444444444','33333333-3333-4333-8333-333333333333',
          10,'EGP',1,10,'2026-06-01','cash','99999999-9999-4999-8999-999999999999');

  select can_delete, message_ar into v_ok, v_msg
  from public.guard_document_deletion('99999999-9999-4999-8999-999999999999');
  if v_ok then raise exception 'FAIL: receipt attached to a settlement must be blocked'; end if;
  if v_msg <> 'لا يمكن حذف المستند لأنه مرتبط بسجلات مالية أو تشغيلية. افصل أو عالج الروابط أولاً: تسويات: 1.' then
    raise exception 'FAIL message mismatch (block/document). Got: %', v_msg;
  end if;
  raise notice 'PASS guard/document: blocked with "تسويات: 1"';
end;
$$;

-- ── 5. partner + asset guards ────────────────────────────────────────────────
do $$
declare v_ok boolean; v_msg text;
begin
  select can_delete, message_ar into v_ok, v_msg
  from public.guard_partner_deletion('22222222-2222-4222-8222-222222222222');
  if v_ok then raise exception 'FAIL: partner with transactions must be blocked'; end if;
  if v_msg not like '%معاملات: 1%' or v_msg not like '%التزامات: 1%' or v_msg not like '%مستندات: 1%' then
    raise exception 'FAIL: partner blockers incomplete. Got: %', v_msg;
  end if;
  if v_msg not like 'لا يمكن حذف الشريك%' then
    raise exception 'FAIL: wrong entity noun for partner. Got: %', v_msg;
  end if;
  raise notice 'PASS guard/partner: blocked, entity noun + labels correct';

  select can_delete, message_ar into v_ok, v_msg
  from public.guard_asset_deletion('77777777-7777-4777-8777-777777777777');
  if v_ok then raise exception 'FAIL: asset with operational events must be blocked'; end if;
  if v_msg not like 'لا يمكن حذف الأصل%' or v_msg not like '%أحداث تشغيلية: 1%' then
    raise exception 'FAIL: asset guard message wrong. Got: %', v_msg;
  end if;
  raise notice 'PASS guard/asset: blocked with "أحداث تشغيلية: 1"';
end;
$$;

-- ── 6. Guards respect RLS: Bob must not learn about Alice's links ────────────
-- SECURITY INVOKER means Bob's counts run under his own RLS, so Alice's
-- children are invisible and the guard reports "deletable" for an id he does
-- not own. It must never leak Alice's blocker counts.
do $$
declare v_ok boolean; v_msg text;
begin
  set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  select can_delete, message_ar into v_ok, v_msg
  from public.guard_project_deletion('11111111-1111-4111-8111-111111111111');

  if v_msg like '%معاملات: 1%' or v_msg like '%مستندات: 1%' then
    raise exception 'FAIL leak: Bob saw Alice''s blocker counts: %', v_msg;
  end if;
  raise notice 'PASS guard/isolation: Bob learns nothing about Alice''s linked records';
end;
$$;

-- ── 7. Set-returning shape: exactly one row, two columns ─────────────────────
do $$
declare v_rows int;
begin
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  select count(*) into v_rows from public.guard_project_deletion('11111111-1111-4111-8111-111111111111');
  if v_rows <> 1 then
    raise exception 'FAIL shape: guard returned % rows, client expects data[0] of a 1-element array', v_rows;
  end if;
  raise notice 'PASS shape: guard returns exactly 1 row (client reads data[0])';
end;
$$;

set local role postgres;
rollback;

\echo '=== DELETION GUARD RPC SUITE: ALL CHECKS PASSED ==='
