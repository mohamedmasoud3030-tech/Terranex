-- =============================================================================
-- ROLLBACK 0002 — the 11 operational tables
-- =============================================================================
-- *** DESTRUCTIVE. THIS DELETES ALL OPERATIONAL DATA. ***
--
-- Dropping a table drops its rows. There is no non-destructive way to reverse
-- "create table" once rows exist. This script is provided for CI replay
-- (forward -> rollback -> reapply against an empty database) and for resetting
-- a scratch environment. It must never be run against an environment holding
-- real records without a verified external dump taken first.
--
-- Guard rail: refuses to run if any operational table contains rows, unless
-- terranex.allow_destructive_rollback is explicitly set:
--     set local terranex.allow_destructive_rollback = 'yes';
-- =============================================================================

do $$
declare
  v_tables constant text[] := array[
    'projects','partners','assets','documents','project_partners','transactions',
    'obligations','settlements','settlement_allocations','operational_events','stock_adjustments'
  ];
  v_table  text;
  v_rows   bigint;
  v_total  bigint := 0;
  v_allow  text;
begin
  foreach v_table in array v_tables loop
    if to_regclass('public.' || v_table) is not null then
      execute format('select count(*) from public.%I', v_table) into v_rows;
      v_total := v_total + v_rows;
    end if;
  end loop;

  v_allow := coalesce(current_setting('terranex.allow_destructive_rollback', true), 'no');

  if v_total > 0 and v_allow <> 'yes' then
    raise exception using
      errcode = 'data_exception',
      message = format('Refusing destructive rollback: %s operational row(s) present.', v_total),
      hint    = 'Take a verified dump, then: set local terranex.allow_destructive_rollback = ''yes'';';
  end if;
end;
$$;

-- Reverse dependency order (children before parents).
drop table if exists public.stock_adjustments      cascade;
drop table if exists public.operational_events     cascade;
drop table if exists public.settlement_allocations cascade;
drop table if exists public.settlements            cascade;
drop table if exists public.obligations            cascade;
drop table if exists public.transactions           cascade;
drop table if exists public.project_partners       cascade;
drop table if exists public.documents              cascade;
drop table if exists public.assets                 cascade;
drop table if exists public.partners               cascade;
drop table if exists public.projects               cascade;
