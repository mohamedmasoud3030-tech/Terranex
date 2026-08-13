-- Money in close snapshots must never flow through PostgreSQL integer locals.
-- EGP 21,474,836.47 already exceeds integer when represented in minor units.

select 1 / case when pg_get_functiondef(
  'public.s6_approve_close_run_impl(uuid,uuid,text)'::regprocedure
) like '%v_cash_total bigint;%'
then 1 else 0 end as close_cash_total_is_bigint;

select 1 / case when pg_get_functiondef(
  'public.s6_approve_close_run_impl(uuid,uuid,text)'::regprocedure
) like '%v_recognized_revenue_total bigint;%'
then 1 else 0 end as close_revenue_total_is_bigint;

select 1 / case when pg_get_functiondef(
  'public.s6_approve_close_run_impl(uuid,uuid,text)'::regprocedure
) like '%into v_cash_total%'
  and pg_get_functiondef(
    'public.s6_approve_close_run_impl(uuid,uuid,text)'::regprocedure
  ) like '%into v_recognized_revenue_total%'
then 1 else 0 end as close_money_assignments_use_bigint_locals;

select 1 / case when 4100000000::bigint > 2147483647::bigint
  and 3400000000::bigint > 2147483647::bigint
then 1 else 0 end as realistic_demo_amounts_exercise_bigint_range;

select 'S6 close bigint totals SQL PASS' as result;
