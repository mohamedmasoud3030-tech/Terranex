-- S6 gate-evaluation authorization hardening.
--
-- The prior S6 migration already owns the complete gate-evaluation behavior,
-- including SECTOR_CUT_OFF and ASSET_SECTOR_ROLLFORWARDS. Preserve that proven
-- implementation verbatim by renaming it internal, then expose one thin public
-- wrapper that performs caller authorization and tenant/project/period scoping
-- before any gate evidence can be evaluated.

-- The lower-level evaluator used by the existing implementation is internal.
revoke all on function public.s6_evaluate_gate_core(uuid, uuid, uuid, text)
  from public, anon, authenticated;

-- Preserve the existing complete evaluator without copying its body into this
-- forward migration. Renaming retains its SECURITY DEFINER/search_path contract.
alter function public.s6_evaluate_gate(uuid, uuid, uuid, text)
  rename to s6_evaluate_gate_impl;
revoke all on function public.s6_evaluate_gate_impl(uuid, uuid, uuid, text)
  from public, anon, authenticated;

create or replace function public.s6_evaluate_gate(
  p_organization_id uuid,
  p_project_id uuid,
  p_period_id uuid,
  p_gate_code text
) returns table(result text, detail text, evidence jsonb)
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  -- Active OWNER authorization must happen before any tenant evidence read.
  perform public.s2_require_owner(p_organization_id);

  if not exists (
    select 1
    from public.investment_projects p
    where p.id = p_project_id
      and p.organization_id = p_organization_id
  ) then
    raise exception 'project not found in organization';
  end if;

  if not exists (
    select 1
    from public.accounting_periods p
    where p.id = p_period_id
      and p.organization_id = p_organization_id
      and p.project_id = p_project_id
  ) then
    raise exception 'period not found for this project';
  end if;

  return query
    select g.result, g.detail, g.evidence
    from public.s6_evaluate_gate_impl(
      p_organization_id,
      p_project_id,
      p_period_id,
      p_gate_code
    ) g;
end $$;

revoke all on function public.s6_evaluate_gate(uuid, uuid, uuid, text)
  from public, anon;
grant execute on function public.s6_evaluate_gate(uuid, uuid, uuid, text)
  to authenticated;
