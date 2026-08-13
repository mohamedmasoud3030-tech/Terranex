-- Monetary minor-unit totals are bigint throughout Terranex. The original S6
-- close implementation reused the integer gate counter for cash and recognized
-- revenue totals. That overflows above 2,147,483,647 minor units (EGP
-- 21,474,836.47), which is a normal project size. Preserve the proven close
-- workflow and serialization wrapper; only give money its own bigint locals.
--
-- pg_get_functiondef normalizes whitespace and aliases, so this migration uses
-- context-aware regular expressions instead of brittle source formatting.
do $s6_bigint_close$
declare
  v_oid regprocedure := 'public.s6_approve_close_run_impl(uuid,uuid,text)'::regprocedure;
  v_definition text;
  v_rewritten text;
begin
  v_definition := pg_get_functiondef(v_oid);
  v_rewritten := v_definition;

  v_rewritten := regexp_replace(
    v_rewritten,
    '(v_fail_count[[:space:]]+(int|integer);)',
    E'\\1\n  v_cash_total bigint;\n  v_recognized_revenue_total bigint;',
    'i'
  );

  v_rewritten := regexp_replace(
    v_rewritten,
    'into[[:space:]]+v_fail_count([[:space:]]+from[[:space:]]+public[.]journal_lines[[:space:]]+jl)',
    E'into v_cash_total\\1',
    'i'
  );

  v_rewritten := regexp_replace(
    v_rewritten,
    'v_fail_count_text[[:space:]]*:=[[:space:]]*v_fail_count::text;',
    'v_fail_count_text := v_cash_total::text;',
    'i'
  );

  v_rewritten := regexp_replace(
    v_rewritten,
    'into[[:space:]]+v_fail_count([[:space:]]+from[[:space:]]+public[.]property_sale_recognitions[[:space:]]+r)',
    E'into v_recognized_revenue_total\\1',
    'i'
  );

  v_rewritten := regexp_replace(
    v_rewritten,
    '(''recognized_revenue_minor_units''[[:space:]]*,[[:space:]]*)v_fail_count::text',
    E'\\1v_recognized_revenue_total::text',
    'i'
  );

  if v_rewritten = v_definition
     or v_rewritten !~ 'v_cash_total[[:space:]]+bigint;'
     or v_rewritten !~ 'v_recognized_revenue_total[[:space:]]+bigint;'
     or v_rewritten ~ 'into[[:space:]]+v_fail_count[[:space:]]+from[[:space:]]+public[.]journal_lines[[:space:]]+jl'
     or v_rewritten ~ 'into[[:space:]]+v_fail_count[[:space:]]+from[[:space:]]+public[.]property_sale_recognitions[[:space:]]+r'
     or v_rewritten !~ 'v_fail_count_text[[:space:]]*:=[[:space:]]*v_cash_total::text;'
     or v_rewritten !~ '''recognized_revenue_minor_units''[[:space:]]*,[[:space:]]*v_recognized_revenue_total::text' then
    raise exception 'S6 close bigint rewrite did not match the expected implementation';
  end if;

  execute v_rewritten;
end
$s6_bigint_close$;
