-- Regression gate for the final F3–F10 audit hardening.
-- Proves internal approval helpers cannot be invoked as RPCs, the historical
-- portfolio roll-up authorizes tenant scope before its definer implementation,
-- signed FX conversion is exact/symmetric, and approved corrections remain
-- visible as in-flight controls.

do $$
declare
  v_offender text;
  v_viewdef text;
begin
  -- Internal F5 helpers and the F10 implementation must have no execute grant
  -- for PUBLIC, anon, or authenticated. The owning database role can still
  -- call them from the material SECURITY DEFINER command wrappers.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_offender
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace,
  lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where n.nspname = 'public'
    and p.proname in (
      'f5_approval_required',
      'f5_signoffs_count',
      'f5_has_signed',
      'f5_record_signoff',
      'f5_approval_complete',
      'portfolio_financial_rollup_asof_impl'
    )
    and (a.grantee = 0 or pg_get_userbyid(a.grantee) in ('anon','authenticated'));

  if v_offender is not null then
    raise exception 'internal finance helper(s) remain externally executable: %', v_offender;
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.portfolio_financial_rollup_asof(uuid,uuid,date)',
    'execute'
  ) then
    raise exception 'authenticated must retain execute on the authorized as-of wrapper';
  end if;

  if has_function_privilege(
    'anon',
    'public.portfolio_financial_rollup_asof(uuid,uuid,date)',
    'execute'
  ) then
    raise exception 'anon must not execute the as-of wrapper';
  end if;

  -- Signed half-up conversion is symmetric and preserves the full bigint min.
  if public.fx_convert_exact(5, 1, 2) <> 3 then
    raise exception 'positive half-up FX conversion regressed';
  end if;
  if public.fx_convert_exact(-5, 1, 2) <> -3 then
    raise exception 'negative half-up FX conversion must be symmetric';
  end if;
  if public.fx_convert_exact('-9223372036854775808'::bigint, 1, 1)
       <> '-9223372036854775808'::bigint then
    raise exception 'signed FX conversion must preserve INT64_MIN at 1:1';
  end if;

  v_viewdef := pg_get_viewdef('public.period_close_health_read'::regclass, true);
  if position('REQUESTED' in v_viewdef) = 0 or position('APPROVED' in v_viewdef) = 0 then
    raise exception 'period close health must treat REQUESTED and APPROVED corrections as in-flight';
  end if;

  v_viewdef := pg_get_viewdef('public.financial_integrity_signals_read'::regclass, true);
  if position('OPEN_CORRECTION_REQUESTS' in v_viewdef) = 0
     or position('APPROVED' in v_viewdef) = 0 then
    raise exception 'integrity center must retain approved-unexecuted corrections';
  end if;
end $$;

-- The public as-of wrapper must reject a caller that is not an active member
-- of the supplied organization before it can reach any portfolio data.
do $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    'f4000000-0000-4000-8000-0000000000ff',
    true
  );
  begin
    perform *
    from public.portfolio_financial_rollup_asof(
      'f3000000-0000-4000-8000-000000000001',
      'f4000000-0000-4000-8000-0000000000ee',
      current_date
    );
    raise exception 'expected cross-tenant as-of roll-up rejection';
  exception when others then
    if position('forbidden' in lower(sqlerrm)) = 0 then
      raise;
    end if;
  end;
end $$;
