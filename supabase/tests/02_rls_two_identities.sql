-- =============================================================================
-- Terranex DB test — RLS isolation with TWO real identities
-- =============================================================================
-- Runs as the `authenticated` role with a JWT sub claim, exactly as PostgREST
-- would. Alice and Bob each own data; every assertion below proves Bob cannot
-- see, alter, delete, or link to Alice's rows — and cannot forge ownership.
--
-- This is a real Postgres with the real migrations applied. The FakeSupabase
-- client is NOT involved and cannot be: it has no RLS engine.
-- =============================================================================
\set ON_ERROR_STOP on

-- One transaction for the whole suite: SET LOCAL role / jwt claims only apply
-- inside a transaction block, and this also guarantees the test leaves no data
-- behind (final ROLLBACK).
begin;

-- Reset to a known state as superuser.
set local role postgres;
delete from public.settlement_allocations;
delete from public.settlements;
delete from public.obligations;
delete from public.operational_events;
delete from public.stock_adjustments;
delete from public.transactions;
delete from public.documents;
delete from public.project_partners;
delete from public.assets;
delete from public.partners;
delete from public.projects;
delete from auth.users;

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@terranex.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@terranex.test');

-- ─── Alice creates a full ownership chain ────────────────────────────────────
set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into public.projects (id, sector_id, name_ar, name_en, status, start_date, base_currency)
values ('11111111-1111-4111-8111-111111111111', 'real-estate', 'مشروع أليس', 'Alice project', 'active', '2026-01-01', 'EGP');

insert into public.partners (id, name_ar, category)
values ('22222222-2222-4222-8222-222222222222', 'شريك أليس', 'equity_partner');

insert into public.obligations (id, project_id, partner_id, direction, amount, currency, amount_egp, status)
values ('33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222', 'payable', 100, 'EGP', 100, 'open');

insert into public.settlements (id, obligation_id, amount, currency, fx_rate, amount_egp, settlement_date, payment_method)
values ('44444444-4444-4444-8444-444444444444', '33333333-3333-4333-8333-333333333333',
        40, 'EGP', 1, 40, '2026-06-01', 'cash');

do $$
begin
  if (select count(*) from public.projects)    <> 1 then raise exception 'FAIL setup: Alice project not visible'; end if;
  if (select count(*) from public.settlements) <> 1 then raise exception 'FAIL setup: Alice settlement not visible'; end if;
  if (select owner_id from public.projects limit 1) <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid
    then raise exception 'FAIL setup: owner_id default did not resolve to auth.uid()'; end if;
  raise notice 'PASS setup: Alice owns 1 project / 1 partner / 1 obligation / 1 settlement (owner_id auto-filled)';
end;
$$;

-- ─── Bob logs in ─────────────────────────────────────────────────────────────
set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

do $$
declare
  v_n     bigint;
  v_tbl   text;
begin
  -- 1. READ ISOLATION — Bob sees nothing of Alice's, in every table.
  foreach v_tbl in array array[
    'projects','partners','assets','documents','project_partners','transactions',
    'obligations','settlements','settlement_allocations','operational_events','stock_adjustments'
  ] loop
    execute format('select count(*) from public.%I', v_tbl) into v_n;
    if v_n <> 0 then
      raise exception 'FAIL read isolation: Bob sees % row(s) in %', v_n, v_tbl;
    end if;
  end loop;
  raise notice 'PASS read isolation: Bob sees 0 rows across all 11 tables';

  -- 2. UPDATE ISOLATION — Bob cannot modify Alice's row (USING hides it).
  update public.projects set name_ar = 'اختراق' where id = '11111111-1111-4111-8111-111111111111';
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'FAIL update isolation: Bob updated % of Alice''s rows', v_n; end if;
  raise notice 'PASS update isolation: Bob''s UPDATE affected 0 of Alice''s rows';

  -- 3. DELETE ISOLATION — same.
  delete from public.settlements where id = '44444444-4444-4444-8444-444444444444';
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'FAIL delete isolation: Bob deleted % of Alice''s rows', v_n; end if;
  raise notice 'PASS delete isolation: Bob''s DELETE affected 0 of Alice''s rows';
end;
$$;

-- 4. OWNER_ID SPOOFING ON INSERT — WITH CHECK must reject a forged owner.
do $$
begin
  insert into public.projects (id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency)
  values ('99999999-9999-4999-8999-999999999999', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'agriculture', 'مزروع', 'Planted', 'active', '2026-01-01', 'EGP');
  raise exception 'FAIL spoofing: Bob inserted a row owned by Alice';
exception
  when insufficient_privilege then
    raise notice 'PASS spoofing/insert: forged owner_id rejected by WITH CHECK';
end;
$$;

-- 5. OWNER_ID SPOOFING ON UPDATE — Bob cannot hand his own row to Alice.
do $$
declare v_n bigint;
begin
  insert into public.projects (id, sector_id, name_ar, name_en, status, start_date, base_currency)
  values ('88888888-8888-4888-8888-888888888888', 'livestock', 'مشروع بوب', 'Bob project', 'active', '2026-02-01', 'EGP');

  begin
    update public.projects
       set owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     where id = '88888888-8888-4888-8888-888888888888';
    raise exception 'FAIL spoofing: Bob reassigned his row to Alice';
  exception
    when insufficient_privilege then
      raise notice 'PASS spoofing/update: reassigning owner_id to another user rejected';
  end;

  select count(*) into v_n from public.projects where id = '88888888-8888-4888-8888-888888888888';
  if v_n <> 1 then raise exception 'FAIL: Bob lost his own row'; end if;
  raise notice 'PASS ownership: Bob still owns his own project';
end;
$$;

-- 6. CROSS-TENANT COMPOSITE FK — the schema-level defence, independent of RLS.
--    Bob tries to attach a settlement to Alice's obligation. Even if RLS were
--    misconfigured, (obligation_id, owner_id) cannot resolve across tenants.
do $$
begin
  insert into public.settlements (obligation_id, amount, currency, fx_rate, amount_egp, settlement_date, payment_method)
  values ('33333333-3333-4333-8333-333333333333', 10, 'EGP', 1, 10, '2026-06-02', 'cash');
  raise exception 'FAIL composite FK: Bob attached a settlement to Alice''s obligation';
exception
  when foreign_key_violation then
    raise notice 'PASS composite FK: settlement -> another tenant''s obligation rejected';
end;
$$;

-- 7. CROSS-TENANT ALLOCATION — same for settlement_allocations, both parents.
do $$
begin
  insert into public.settlement_allocations (settlement_id, obligation_id, allocated_amount_egp)
  values ('44444444-4444-4444-8444-444444444444', '33333333-3333-4333-8333-333333333333', 10);
  raise exception 'FAIL composite FK: Bob allocated against Alice''s settlement';
exception
  when foreign_key_violation then
    raise notice 'PASS composite FK: allocation -> another tenant''s settlement/obligation rejected';
end;
$$;

-- 8. Alice is untouched by everything Bob attempted.
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
do $$
begin
  if (select count(*) from public.projects) <> 1 then
    raise exception 'FAIL: Alice project count changed (Bob''s row leaked in?)';
  end if;
  if (select name_ar from public.projects where id='11111111-1111-4111-8111-111111111111') <> 'مشروع أليس' then
    raise exception 'FAIL: Alice project name was modified by Bob';
  end if;
  if (select count(*) from public.settlements) <> 1 then
    raise exception 'FAIL: Alice settlement was deleted by Bob';
  end if;
  raise notice 'PASS integrity: Alice''s data unchanged after all of Bob''s attempts';
end;
$$;

-- 9. anon has no access at all.
set local role anon;
do $$
begin
  perform 1 from public.projects;
  raise exception 'FAIL anon: anonymous role could query projects';
exception
  when insufficient_privilege then
    raise notice 'PASS anon: anonymous role has no table access';
end;
$$;

set local role postgres;

-- Nothing from this suite is persisted.
rollback;

\echo '=== RLS TWO-IDENTITY SUITE: ALL CHECKS PASSED ==='
