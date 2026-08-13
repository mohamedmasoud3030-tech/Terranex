-- Regression coverage for 20260813000300_pilot_security_advisor_hardening.sql.
do $$
declare
  v_rel record;
  v_anon_can_execute boolean;
  v_authenticated_can_execute boolean;
  v_search_path text;
begin
  select c.relrowsecurity, c.relforcerowsecurity
    into v_rel
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 's7_opening_mapping_codes'
    and c.relkind in ('r','p');

  if not found or not v_rel.relrowsecurity or not v_rel.relforcerowsecurity then
    raise exception 'S7 opening mapping registry must have ENABLE + FORCE RLS';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 's7_opening_mapping_codes'
      and policyname = 's7_opening_mapping_codes_authenticated_read'
      and 'authenticated' = any(roles)
      and cmd = 'SELECT'
  ) then
    raise exception 'S7 opening mapping registry authenticated read policy missing';
  end if;

  select has_function_privilege(
      'anon',
      'public.s5_configure_allocation_rules(uuid,uuid,uuid,text,uuid[],bigint[],bigint,text,text)',
      'EXECUTE'
    ),
    has_function_privilege(
      'authenticated',
      'public.s5_configure_allocation_rules(uuid,uuid,uuid,text,uuid[],bigint[],bigint,text,text)',
      'EXECUTE'
    )
    into v_anon_can_execute, v_authenticated_can_execute;

  if v_anon_can_execute then
    raise exception 'S5 evidence-backed allocation command must not be executable by anon';
  end if;
  if not v_authenticated_can_execute then
    raise exception 'S5 evidence-backed allocation command must remain executable by authenticated';
  end if;

  foreach v_search_path in array array[
    (select p.proconfig::text from pg_proc p where p.oid = 'public.s1_guard_agreement_version_immutable()'::regprocedure),
    (select p.proconfig::text from pg_proc p where p.oid = 'public.s1_guard_append_only()'::regprocedure),
    (select p.proconfig::text from pg_proc p where p.oid = 'public.s1_guard_commitment_terms_immutable()'::regprocedure)
  ] loop
    if v_search_path is null or v_search_path not like '%search_path=pg_catalog, public%' then
      raise exception 'S1 trigger guard search_path must be pinned: %', v_search_path;
    end if;
  end loop;
end $$;
