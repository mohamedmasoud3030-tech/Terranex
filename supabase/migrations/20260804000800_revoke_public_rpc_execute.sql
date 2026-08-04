-- Terranex — revoke inherited PUBLIC execution from RPC and trigger helpers
--
-- PostgreSQL grants EXECUTE on new functions to PUBLIC by default. Explicitly
-- granting authenticated does not remove that inherited permission, so anon can
-- otherwise still reach SECURITY DEFINER routines through PostgREST.

revoke all on function public.create_sales_invoice_atomic(
  text, uuid, uuid, uuid, date, date, text, numeric, numeric, text, jsonb
) from public, anon;
grant execute on function public.create_sales_invoice_atomic(
  text, uuid, uuid, uuid, date, date, text, numeric, numeric, text, jsonb
) to authenticated, service_role;

revoke all on function public.pay_sales_invoice(
  text, uuid, numeric, uuid, date, text
) from public, anon;
grant execute on function public.pay_sales_invoice(
  text, uuid, numeric, uuid, date, text
) to authenticated, service_role;

-- terranex_assert_owner is a fail-closed ownership assertion used by both
-- SECURITY DEFINER and SECURITY INVOKER RPCs. Keep it hidden from PUBLIC/anon,
-- while allowing authenticated invoker RPCs to call it.
revoke all on function public.terranex_assert_owner(uuid)
  from public, anon;
grant execute on function public.terranex_assert_owner(uuid)
  to authenticated, service_role;

-- Locking and audit helpers are internal implementation details. SECURITY
-- DEFINER callers execute as the function owner and do not require an external
-- authenticated-role grant for these nested calls.
revoke all on function public.terranex_lock_financial_request(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.terranex_audit_check_idempotent(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.terranex_audit_log(
  uuid, text, text, uuid[], jsonb, jsonb, uuid
) from public, anon, authenticated;

grant execute on function public.terranex_lock_financial_request(uuid, uuid) to service_role;
grant execute on function public.terranex_audit_check_idempotent(uuid, uuid) to service_role;
grant execute on function public.terranex_audit_log(
  uuid, text, text, uuid[], jsonb, jsonb, uuid
) to service_role;

-- Trigger functions are invoked by PostgreSQL triggers and must never be direct
-- PostgREST RPC endpoints. Revoke every current public trigger function rather
-- than maintaining a fragile hand-written list.
do $revoke_trigger_execution$
declare
  r record;
begin
  for r in
    select
      n.nspname,
      p.proname,
      pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prorettype = 'pg_catalog.trigger'::regtype
  loop
    execute format(
      'revoke all on function %I.%I(%s) from public, anon, authenticated',
      r.nspname,
      r.proname,
      r.args
    );
  end loop;
end
$revoke_trigger_execution$;
