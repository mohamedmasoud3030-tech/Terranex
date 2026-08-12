-- GF-007 / S6 hardening — truthful sector cut-off evaluation.
--
-- The original SECTOR_CUT_OFF branch treated every batch outside the period
-- as a close failure. That makes a valid posting in a later period block the
-- close of the current period. A cut-off control must instead validate the
-- facts that belong to (or claim to belong to) the period being closed.
--
-- Preserve the existing evaluator as the core implementation for every other
-- gate and intercept only SECTOR_CUT_OFF with the corrected period-scoped
-- invariant.

alter function public.s6_evaluate_gate(uuid, uuid, uuid, text)
  rename to s6_evaluate_gate_core;

revoke all on function public.s6_evaluate_gate_core(uuid, uuid, uuid, text)
  from public, anon;
grant execute on function public.s6_evaluate_gate_core(uuid, uuid, uuid, text)
  to authenticated;

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
begin
  if p_gate_code <> 'SECTOR_CUT_OFF' then
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

  select * into v_period
  from public.accounting_periods p
  where p.id = p_period_id
    and p.organization_id = p_organization_id
    and p.project_id = p_project_id;

  if not found then
    raise exception 'period not found for this project';
  end if;

  -- A future or prior-period batch is not a cut-off failure for this period.
  -- The failure condition is a header/line date disagreement that causes a
  -- posting to straddle this period boundary. Either side touching the period
  -- makes the mismatch relevant to this close.
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
end $$;

revoke all on function public.s6_evaluate_gate(uuid, uuid, uuid, text)
  from public, anon;
grant execute on function public.s6_evaluate_gate(uuid, uuid, uuid, text)
  to authenticated;
