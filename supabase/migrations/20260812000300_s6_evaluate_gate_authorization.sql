-- GF-007 / S6 — Gate Evaluation Authorization Hardening
--
-- 1. Isolate s6_evaluate_gate_core as an internal-only SECURITY DEFINER function.
--    Revoke execute privileges from public, anon, and authenticated.

revoke all on function public.s6_evaluate_gate_core(uuid, uuid, uuid, text)
  from public, anon, authenticated;

-- 2. Harden s6_evaluate_gate to enforce active OWNER authorization and
--    organization/project scope validation before executing or delegating gate evaluation.

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
declare
  v_period record;
  v_mismatched bigint;
  v_batches bigint;
  v_assets bigint;
  v_phases bigint;
  v_milestones bigint;
  v_missing_asset_history bigint;
  v_missing_phase_history bigint;
  v_missing_milestone_history bigint;
  v_missing_total bigint;
begin
  -- Authoritative owner check: caller must be an active OWNER of p_organization_id
  perform public.s2_require_owner(p_organization_id);

  -- Validate project scope
  if not exists (
    select 1 from public.investment_projects p
    where p.id = p_project_id
      and p.organization_id = p_organization_id
  ) then
    raise exception 'project not found in organization';
  end if;

  -- Validate period scope
  select * into v_period
  from public.accounting_periods p
  where p.id = p_period_id
    and p.organization_id = p_organization_id
    and p.project_id = p_project_id;

  if not found then
    raise exception 'period not found for this project';
  end if;

  if p_gate_code not in ('SECTOR_CUT_OFF', 'ASSET_SECTOR_ROLLFORWARDS') then
    return query
      select g.result, g.detail, g.evidence
      from public.s6_evaluate_gate_core(
        p_organization_id,
        p_project_id,
        p_period_id,
        p_gate_code
      ) g;
    return;
  end if;

  if p_gate_code = 'SECTOR_CUT_OFF' then
    -- A batch in another period is not a cut-off failure for this close.
    select count(*) into v_mismatched
    from public.journal_batches jb
    join public.journal_lines jl
      on jl.batch_id = jb.id
     and jl.organization_id = jb.organization_id
    where jb.organization_id = p_organization_id
      and jb.project_id = p_project_id
      and (
        jb.transaction_date between v_period.start_date and v_period.end_date
        or jl.transaction_date between v_period.start_date and v_period.end_date
      )
      and (
        jl.project_id <> jb.project_id
        or jl.transaction_date <> jb.transaction_date
      );

    select count(*) into v_batches
    from public.journal_batches jb
    where jb.organization_id = p_organization_id
      and jb.project_id = p_project_id
      and jb.transaction_date between v_period.start_date and v_period.end_date;

    if v_mismatched = 0 then
      return query select
        'PASS'::text,
        format('%s batch(es) belong to this period and none straddle the cut-off', v_batches),
        jsonb_build_object(
          'batches_in_cut_off', v_batches,
          'header_line_date_mismatches', 0,
          'scope', 'current_period_only'
        );
    else
      return query select
        'FAIL'::text,
        format('%s journal line(s) straddle the period cut-off because header and line dates disagree', v_mismatched),
        jsonb_build_object(
          'batches_in_cut_off', v_batches,
          'header_line_date_mismatches', v_mismatched,
          'scope', 'current_period_only'
        );
    end if;
    return;
  end if;

  -- ASSET_SECTOR_ROLLFORWARDS
  select count(*) into v_assets
  from public.property_assets a
  where a.organization_id = p_organization_id
    and a.project_id = p_project_id;

  select count(*) into v_missing_asset_history
  from public.property_assets a
  where a.organization_id = p_organization_id
    and a.project_id = p_project_id
    and not exists (
      select 1
      from public.property_asset_state_history h
      where h.organization_id = p_organization_id
        and h.project_id = p_project_id
        and h.property_asset_id = a.id
    );

  select count(*) into v_phases
  from public.development_phases p
  where p.organization_id = p_organization_id
    and p.project_id = p_project_id;

  select count(*) into v_missing_phase_history
  from public.development_phases p
  where p.organization_id = p_organization_id
    and p.project_id = p_project_id
    and not exists (
      select 1
      from public.development_phase_state_history h
      where h.organization_id = p_organization_id
        and h.project_id = p_project_id
        and h.phase_id = p.id
    );

  select count(*) into v_milestones
  from public.development_milestones m
  where m.organization_id = p_organization_id
    and m.project_id = p_project_id;

  select count(*) into v_missing_milestone_history
  from public.development_milestones m
  where m.organization_id = p_organization_id
    and m.project_id = p_project_id
    and not exists (
      select 1
      from public.development_milestone_state_history h
      where h.organization_id = p_organization_id
        and h.project_id = p_project_id
        and h.milestone_id = m.id
    );

  v_missing_total := v_missing_asset_history
    + v_missing_phase_history
    + v_missing_milestone_history;

  if v_missing_total = 0 then
    return query select
      'PASS'::text,
      format(
        'sector rollforward reconciles from append-only history: %s asset(s), %s phase(s), %s milestone(s)',
        v_assets, v_phases, v_milestones
      ),
      jsonb_build_object(
        'assets', v_assets,
        'phases', v_phases,
        'milestones', v_milestones,
        'missing_asset_history', 0,
        'missing_phase_history', 0,
        'missing_milestone_history', 0,
        'open_operational_states_allowed', true
      );
  else
    return query select
      'FAIL'::text,
      format('%s sector object(s) cannot be reproduced from authoritative state history', v_missing_total),
      jsonb_build_object(
        'assets', v_assets,
        'phases', v_phases,
        'milestones', v_milestones,
        'missing_asset_history', v_missing_asset_history,
        'missing_phase_history', v_missing_phase_history,
        'missing_milestone_history', v_missing_milestone_history
      );
  end if;
end $$;

revoke all on function public.s6_evaluate_gate(uuid, uuid, uuid, text)
  from public, anon;
grant execute on function public.s6_evaluate_gate(uuid, uuid, uuid, text)
  to authenticated;
