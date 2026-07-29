-- =============================================================================
-- ROLLBACK 0007 — owner_id backfill
-- =============================================================================
-- REVERSIBLE:   the NOT NULL constraint and the DEFAULT auth.uid().
-- IRREVERSIBLE: the owner_id VALUES written during backfill.
--
-- This script deliberately does NOT null out owner_id. Doing so would destroy
-- the tenant assignment — the one piece of information the backfill produced
-- and which cannot be recomputed. Relaxing the constraint is enough to let
-- 0002 be rolled back afterwards, and leaving the values in place means a
-- re-apply is a no-op instead of a re-guess.
--
-- To fully discard ownership (destructive, dev only) see the commented block
-- at the end.
-- =============================================================================

drop view if exists public.terranex_ownership_preflight;

do $$
declare
  v_tables constant text[] := array[
    'projects', 'partners', 'assets', 'documents', 'project_partners',
    'transactions', 'obligations', 'settlements', 'settlement_allocations',
    'operational_events', 'stock_adjustments'
  ];
  v_table text;
begin
  foreach v_table in array v_tables loop
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = v_table and column_name = 'owner_id'
    ) then
      execute format('alter table public.%I alter column owner_id drop not null', v_table);
      execute format('alter table public.%I alter column owner_id drop default', v_table);
    end if;
  end loop;
  raise notice 'owner_id NOT NULL + DEFAULT dropped. Values preserved (irreversible by design).';
end;
$$;

-- DESTRUCTIVE — never run against data you intend to keep.
-- Discards every tenant assignment. Only for resetting a scratch database.
--
-- do $$
-- declare
--   v_table text;
-- begin
--   foreach v_table in array array[
--     'projects','partners','assets','documents','project_partners','transactions',
--     'obligations','settlements','settlement_allocations','operational_events','stock_adjustments'
--   ] loop
--     execute format('update public.%I set owner_id = null', v_table);
--   end loop;
-- end;
-- $$;
