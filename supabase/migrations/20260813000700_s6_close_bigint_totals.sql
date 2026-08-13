-- Monetary minor-unit totals are bigint throughout Terranex. The original S6
-- close implementation reused the integer gate counter for cash and recognized
-- revenue totals. That overflows above 2,147,483,647 minor units (EGP
-- 21,474,836.47), which is a normal project size. Preserve the proven close
-- workflow and serialization wrapper; only give money its own bigint locals.

do $s6_bigint_close$
declare
  v_oid regprocedure := 'public.s6_approve_close_run_impl(uuid,uuid,text)'::regprocedure;
  v_definition text;
  v_rewritten text;
begin
  v_definition := pg_get_functiondef(v_oid);
  v_rewritten := v_definition;

  v_rewritten := replace(
    v_rewritten,
    '  v_fail_count int;' || chr(10) || '  v_fail_count_text text;',
    '  v_fail_count int;' || chr(10) ||
    '  v_cash_total bigint;' || chr(10) ||
    '  v_recognized_revenue_total bigint;' || chr(10) ||
    '  v_fail_count_text text;'
  );

  v_rewritten := replace(
    v_rewritten,
    '  into v_fail_count' || chr(10) ||
    '  from public.journal_lines jl' || chr(10) ||
    '  join public.semantic_accounts sa on sa.id = jl.account_id',
    '  into v_cash_total' || chr(10) ||
    '  from public.journal_lines jl' || chr(10) ||
    '  join public.semantic_accounts sa on sa.id = jl.account_id'
  );

  v_rewritten := replace(
    v_rewritten,
    '  v_fail_count_text := v_fail_count::text;',
    '  v_fail_count_text := v_cash_total::text;'
  );

  v_rewritten := replace(
    v_rewritten,
    '  select coalesce(sum(r.recognized_proceeds_minor_units), 0)' || chr(10) ||
    '    into v_fail_count' || chr(10) ||
    '  from public.property_sale_recognitions r',
    '  select coalesce(sum(r.recognized_proceeds_minor_units), 0)' || chr(10) ||
    '    into v_recognized_revenue_total' || chr(10) ||
    '  from public.property_sale_recognitions r'
  );

  v_rewritten := replace(
    v_rewritten,
    '''recognized_revenue_minor_units'', v_fail_count::text,',
    '''recognized_revenue_minor_units'', v_recognized_revenue_total::text,'
  );

  if v_rewritten = v_definition
     or v_rewritten not like '%v_cash_total bigint;%'
     or v_rewritten not like '%v_recognized_revenue_total bigint;%'
     or v_rewritten like '%into v_fail_count%from public.journal_lines%'
     or v_rewritten like '%into v_fail_count%from public.property_sale_recognitions%' then
    raise exception 'S6 close bigint rewrite did not match the expected implementation';
  end if;

  execute v_rewritten;
end
$s6_bigint_close$;
