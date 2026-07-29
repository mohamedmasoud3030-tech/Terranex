-- =============================================================================
-- Terranex — Phase 1A — 0007 — owner_id backfill + preflight
-- =============================================================================
-- Migration 0002 creates the 11 tables with `owner_id NOT NULL`. That is correct
-- for a fresh environment. This migration exists for the OTHER case: an
-- environment where the tables were already created ad-hoc (the current
-- production project was built by hand, with no migration history) and rows
-- exist WITHOUT owner_id.
--
-- It is written to be safe in all four situations:
--
--   A. Tables already have owner_id NOT NULL (fresh install) -> no-op.
--   B. owner_id missing/nullable, and NO operational rows    -> add column,
--      set default, enforce NOT NULL. Nothing to backfill.
--   C. owner_id missing/nullable, rows exist, exactly ONE auth user
--      -> assign every row to that user, in FK dependency order, inside the
--         migration's transaction.
--   D. owner_id missing/nullable, rows exist, and ZERO or MORE THAN ONE user
--      -> RAISE EXCEPTION and abort. Picking an owner would silently hand one
--         tenant's financial records to another. That is never acceptable, so
--         the migration refuses and an operator must decide.
--
-- The whole file runs in one transaction (psql --single-transaction / supabase
-- CLI), so an abort in case D leaves the database untouched.
--
-- Non-destructive: adds a column and populates it. No row is deleted, no
-- column dropped, no value overwritten once set.
-- =============================================================================

do $$
declare
  -- FK dependency order: parents first, so a composite FK is never briefly
  -- violated while children are still unowned.
  v_tables constant text[] := array[
    'projects',
    'partners',
    'assets',
    'documents',
    'project_partners',
    'transactions',
    'obligations',
    'settlements',
    'settlement_allocations',
    'operational_events',
    'stock_adjustments'
  ];
  v_table          text;
  v_needs_backfill boolean := false;
  v_total_rows     bigint  := 0;
  v_table_rows     bigint;
  v_user_count     bigint;
  v_owner          uuid;
  v_unowned        bigint;
begin
  -- ── step 1: ensure the column exists and is nullable while we work ────────
  foreach v_table in array v_tables loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = v_table and column_name = 'owner_id'
    ) then
      execute format('alter table public.%I add column owner_id uuid', v_table);
      raise notice 'owner_id added to %', v_table;
      v_needs_backfill := true;
    end if;

    -- Count rows that still need an owner.
    execute format('select count(*) from public.%I where owner_id is null', v_table)
      into v_table_rows;
    v_total_rows := v_total_rows + v_table_rows;
  end loop;

  -- ── step 2: decide, based on data + identities ────────────────────────────
  if v_total_rows = 0 then
    raise notice 'Backfill preflight: no unowned rows. Nothing to assign.';
  else
    select count(*) into v_user_count from auth.users;

    if v_user_count = 1 then
      select id into v_owner from auth.users limit 1;
      raise notice 'Backfill preflight: % unowned row(s), exactly 1 auth user (%). Assigning.',
        v_total_rows, v_owner;

      foreach v_table in array v_tables loop
        execute format('update public.%I set owner_id = %L where owner_id is null', v_table, v_owner);
      end loop;

    else
      -- Case D. Refuse rather than guess.
      raise exception using
        errcode = 'data_exception',
        message = format(
          'Terranex owner_id backfill aborted: % unowned row(s) found but auth.users contains % user(s).',
          v_total_rows, v_user_count
        ),
        detail = 'A single unambiguous owner is required to backfill existing operational data.',
        hint   = case
          when v_user_count = 0
            then 'No auth user exists. Create the owning account first, then re-run this migration.'
          else 'More than one auth user exists. Assign owner_id manually per tenant, verify with the preflight query, then re-run.'
        end;
    end if;
  end if;

  -- ── step 3: PREFLIGHT — prove every row is owned BEFORE enforcing NOT NULL ─
  -- This is the gate. If a single row is still unowned, adding NOT NULL would
  -- fail with an opaque constraint error; we fail first with a precise one.
  foreach v_table in array v_tables loop
    execute format('select count(*) from public.%I where owner_id is null', v_table)
      into v_unowned;
    if v_unowned > 0 then
      raise exception using
        errcode = 'data_exception',
        message = format('Terranex backfill preflight FAILED: %s row(s) in public.%s still have owner_id IS NULL.', v_unowned, v_table),
        hint    = 'Every operational row must be owned before owner_id can be made NOT NULL.';
    end if;
  end loop;

  raise notice 'Backfill preflight PASSED: every row in all % tables is owned.', cardinality(v_tables);

  -- ── step 4: enforce the invariant ─────────────────────────────────────────
  foreach v_table in array v_tables loop
    execute format('alter table public.%I alter column owner_id set default auth.uid()', v_table);
    execute format('alter table public.%I alter column owner_id set not null', v_table);
  end loop;

  raise notice 'owner_id is now NOT NULL DEFAULT auth.uid() on all % tables.', cardinality(v_tables);
end;
$$;

-- ─── reusable preflight view ─────────────────────────────────────────────────
-- Lets an operator check ownership coverage at any time without running a
-- migration. Used by the CI backfill test.
create or replace view public.terranex_ownership_preflight as
  select 'projects'::text as table_name,
         count(*) as total_rows,
         count(*) filter (where owner_id is null) as unowned_rows
    from public.projects
  union all select 'partners',               count(*), count(*) filter (where owner_id is null) from public.partners
  union all select 'assets',                 count(*), count(*) filter (where owner_id is null) from public.assets
  union all select 'documents',              count(*), count(*) filter (where owner_id is null) from public.documents
  union all select 'project_partners',       count(*), count(*) filter (where owner_id is null) from public.project_partners
  union all select 'transactions',           count(*), count(*) filter (where owner_id is null) from public.transactions
  union all select 'obligations',            count(*), count(*) filter (where owner_id is null) from public.obligations
  union all select 'settlements',            count(*), count(*) filter (where owner_id is null) from public.settlements
  union all select 'settlement_allocations', count(*), count(*) filter (where owner_id is null) from public.settlement_allocations
  union all select 'operational_events',     count(*), count(*) filter (where owner_id is null) from public.operational_events
  union all select 'stock_adjustments',      count(*), count(*) filter (where owner_id is null) from public.stock_adjustments;

comment on view public.terranex_ownership_preflight is
  'Ownership coverage per operational table. unowned_rows must be 0 on every row before owner_id can be NOT NULL.';

-- The view runs with the querying user's RLS in force (security_invoker), so it
-- cannot be used to count another tenant's rows.
alter view public.terranex_ownership_preflight set (security_invoker = true);

revoke all on public.terranex_ownership_preflight from public, anon;
grant select on public.terranex_ownership_preflight to authenticated;
