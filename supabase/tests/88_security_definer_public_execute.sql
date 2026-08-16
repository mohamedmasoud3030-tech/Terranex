-- Regression gate for 20260815040400_livestock_rpc_public_execute_hardening.
--
-- Invariant: no SECURITY DEFINER function in the exposed `public` schema may
-- be executable by PUBLIC or by the anon role. CREATE FUNCTION grants EXECUTE
-- to PUBLIC by default, so any new command added without an explicit
-- `revoke ... from public, anon` reintroduces the gap this suite guards.
--
-- The check is scoped to SECURITY DEFINER functions: every Terranex command
-- RPC is SECURITY DEFINER, while the plain invoker-rights helpers created by
-- earlier suites in this disposable test database are not privilege-bearing
-- and are irrelevant to the anon attack surface.

do $$
declare
  v_offender text;
begin
  select string_agg(sig, ', ')
    into v_offender
  from (
    select distinct p.oid::regprocedure::text as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace,
    lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where n.nspname = 'public'
      and p.prosecdef
      and (a.grantee = 0 or pg_get_userbyid(a.grantee) = 'anon')
  ) offenders;

  if v_offender is not null then
    raise exception
      'SECURITY DEFINER function(s) executable by PUBLIC or anon: %', v_offender;
  end if;
end $$;

-- The hardened overloads must remain callable by signed-in application users.
select 1/case when (
  select bool_and(has_function_privilege('authenticated', p.oid, 'execute'))
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('record_livestock_mortality', 'record_livestock_weight_event')
) then 1 else 0 end as livestock_commands_still_authenticated_executable;
