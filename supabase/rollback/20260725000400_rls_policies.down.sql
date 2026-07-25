-- =============================================================================
-- ROLLBACK 0004 — RLS
-- =============================================================================
-- FULLY REVERSIBLE at the schema level.
--
-- DANGER: dropping these policies and disabling RLS removes tenant isolation.
-- Any role holding table privileges then reads every tenant's rows. Only run
-- this against a scratch database, or in a maintenance window immediately
-- followed by rollback of 0006 (which removes the grants).
-- =============================================================================

do $$
declare
  v_table text;
  v_op    text;
begin
  foreach v_table in array array[
    'projects','partners','assets','documents','project_partners','transactions',
    'obligations','settlements','settlement_allocations','operational_events','stock_adjustments'
  ] loop
    foreach v_op in array array['select','insert','update','delete'] loop
      execute format('drop policy if exists %I on public.%I', v_table || '_' || v_op, v_table);
    end loop;
    execute format('alter table public.%I no force row level security', v_table);
    execute format('alter table public.%I disable row level security', v_table);
  end loop;
end;
$$;
