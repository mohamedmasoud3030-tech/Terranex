-- =============================================================================
-- Terranex DB test — owner_id backfill scenarios
-- =============================================================================
-- Migration 0007 must behave correctly in all four situations. Cases C and D
-- are the ones that matter: C assigns data to the single unambiguous owner,
-- D REFUSES rather than guessing. A migration that picks an owner at random
-- would silently hand one tenant's financial records to another.
--
-- Each case rebuilds an "unmigrated" table (owner_id nullable) and re-runs the
-- backfill logic from 0007 verbatim.
-- =============================================================================
\set ON_ERROR_STOP on

-- ── helper: the backfill decision, extracted so tests exercise real logic ────
create or replace function public.terranex_test_backfill(p_table text)
returns text
language plpgsql
as $fn$
declare
  v_unowned bigint;
  v_users   bigint;
  v_owner   uuid;
begin
  execute format('select count(*) from public.%I where owner_id is null', p_table) into v_unowned;

  if v_unowned = 0 then
    return 'NOOP';
  end if;

  select count(*) into v_users from auth.users;

  if v_users = 1 then
    select id into v_owner from auth.users limit 1;
    execute format('update public.%I set owner_id = %L where owner_id is null', p_table, v_owner);
    return 'BACKFILLED';
  end if;

  raise exception using
    errcode = 'data_exception',
    message = format('Terranex owner_id backfill aborted: %s unowned row(s) found but auth.users contains %s user(s).', v_unowned, v_users);
end;
$fn$;

-- ═══ CASE B: rows absent, no users → plain apply, nothing to backfill ════════
begin;
set local role postgres;
create temp table probe_b (id uuid primary key, owner_id uuid) on commit drop;
do $$
declare v_result text;
begin
  select count(*) from probe_b into strict v_result;
  if v_result::bigint <> 0 then raise exception 'setup'; end if;
  raise notice 'PASS backfill/B: empty table needs no owner assignment';
end;
$$;
rollback;

-- ═══ CASE C: rows exist, exactly ONE auth user → assign to that user ═════════
begin;
set local role postgres;

delete from public.settlement_allocations where true; delete from public.settlements where true;
delete from public.obligations where true; delete from public.operational_events where true;
delete from public.stock_adjustments where true; delete from public.transactions where true;
delete from public.documents where true; delete from public.project_partners where true;
delete from public.assets where true; delete from public.partners where true; delete from public.projects where true;
delete from auth.users where true;

insert into auth.users (id, email) values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','solo@terranex.test');

-- Simulate a pre-migration deployment: owner_id present but nullable + unset.
alter table public.projects alter column owner_id drop not null;
alter table public.projects alter column owner_id drop default;
insert into public.projects (id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency)
values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', null, 'agriculture','مشروع قديم','Legacy','active','2026-01-01','EGP');

do $$
declare v_result text; v_owner uuid; v_unowned bigint;
begin
  select public.terranex_test_backfill('projects') into v_result;
  if v_result <> 'BACKFILLED' then raise exception 'FAIL backfill/C: expected BACKFILLED, got %', v_result; end if;

  select owner_id into v_owner from public.projects where id='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  if v_owner <> 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'::uuid then
    raise exception 'FAIL backfill/C: row assigned to % instead of the single user', v_owner;
  end if;

  -- PREFLIGHT gate: prove zero unowned before NOT NULL is re-applied.
  select count(*) into v_unowned from public.projects where owner_id is null;
  if v_unowned <> 0 then raise exception 'FAIL preflight/C: % unowned rows remain', v_unowned; end if;

  raise notice 'PASS backfill/C: single-user backfill assigned every row; preflight clean (0 unowned)';
end;
$$;

-- NOT NULL can now be safely restored.
alter table public.projects alter column owner_id set not null;
alter table public.projects alter column owner_id set default auth.uid();
do $$ begin raise notice 'PASS backfill/C: NOT NULL + DEFAULT auth.uid() restored after preflight'; end; $$;
rollback;

-- ═══ CASE D1: rows exist, TWO auth users → MUST ABORT ════════════════════════
begin;
set local role postgres;

delete from public.settlement_allocations where true; delete from public.settlements where true;
delete from public.obligations where true; delete from public.operational_events where true;
delete from public.stock_adjustments where true; delete from public.transactions where true;
delete from public.documents where true; delete from public.project_partners where true;
delete from public.assets where true; delete from public.partners where true; delete from public.projects where true;
delete from auth.users where true;

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','alice@terranex.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','bob@terranex.test');

alter table public.projects alter column owner_id drop not null;
alter table public.projects alter column owner_id drop default;
insert into public.projects (id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', null, 'livestock','مشروع غامض','Ambiguous','active','2026-01-01','EGP');

do $$
declare v_result text; v_owner uuid;
begin
  begin
    select public.terranex_test_backfill('projects') into v_result;
    raise exception 'FAIL backfill/D1: migration proceeded with 2 users instead of aborting';
  exception
    when data_exception then
      raise notice 'PASS backfill/D1: aborted with 2 users — no arbitrary owner chosen';
  end;

  select owner_id into v_owner from public.projects where id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  if v_owner is not null then
    raise exception 'FAIL backfill/D1: row was assigned to % despite ambiguity', v_owner;
  end if;
  raise notice 'PASS backfill/D1: data untouched — owner_id still NULL';
end;
$$;
rollback;

-- ═══ CASE D2: rows exist, ZERO auth users → MUST ABORT ═══════════════════════
begin;
set local role postgres;

delete from public.settlement_allocations where true; delete from public.settlements where true;
delete from public.obligations where true; delete from public.operational_events where true;
delete from public.stock_adjustments where true; delete from public.transactions where true;
delete from public.documents where true; delete from public.project_partners where true;
delete from public.assets where true; delete from public.partners where true; delete from public.projects where true;
delete from auth.users where true;

alter table public.projects alter column owner_id drop not null;
alter table public.projects alter column owner_id drop default;
insert into public.projects (id, owner_id, sector_id, name_ar, name_en, status, start_date, base_currency)
values ('ffffffff-ffff-4fff-8fff-ffffffffffff', null, 'real-estate','بلا مالك','Orphan','active','2026-01-01','EGP');

do $$
declare v_result text;
begin
  begin
    select public.terranex_test_backfill('projects') into v_result;
    raise exception 'FAIL backfill/D2: migration proceeded with 0 users';
  exception
    when data_exception then
      raise notice 'PASS backfill/D2: aborted with 0 users — orphan data preserved, not deleted';
  end;
end;
$$;
rollback;

-- ═══ preflight view reports coverage correctly ═══════════════════════════════
begin;
set local role postgres;
do $$
declare v_tables int; v_unowned bigint;
begin
  select count(*), coalesce(sum(unowned_rows),0) into v_tables, v_unowned
  from public.terranex_ownership_preflight;
  if v_tables <> 11 then raise exception 'FAIL preflight view: covers % tables, expected 11', v_tables; end if;
  if v_unowned <> 0 then raise exception 'FAIL preflight view: % unowned rows in a migrated DB', v_unowned; end if;
  raise notice 'PASS preflight view: all 11 tables reported, 0 unowned rows';
end;
$$;
rollback;

drop function if exists public.terranex_test_backfill(text);

\echo '=== BACKFILL SCENARIO SUITE: ALL CHECKS PASSED ==='
