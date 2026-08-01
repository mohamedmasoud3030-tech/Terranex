-- =============================================================================
-- Rollback — Ownership vertical slice hardening
-- =============================================================================
-- Restores record_distribution_atomic to the pre-hardening implementation and
-- removes immutable-history triggers introduced by 20260801000700.
-- =============================================================================

-- Remove triggers first so earlier table rollbacks can drop objects cleanly.
drop trigger if exists trg_distribution_allocations_frozen on public.distribution_allocations;
drop trigger if exists trg_partner_ledger_entries_immutable on public.partner_ledger_entries;
drop trigger if exists trg_equity_change_events_immutable on public.equity_change_events;
drop function if exists public.terranex_prevent_frozen_allocation_change();
drop function if exists public.terranex_prevent_immutable_ownership_mutation();

create or replace function public.record_distribution_atomic(
  p_request_id uuid,
  p_project_id uuid,
  p_distribution_date date,
  p_ownership_as_of_date date,
  p_total_amount numeric,
  p_currency public.terranex_currency,
  p_fx_rate numeric,
  p_notes text default null,
  p_supporting_document_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_owner_id uuid;
  v_cached jsonb;
  v_distribution_id uuid;
  v_total_amount_egp numeric;
  v_partner record;
  v_allocated_total numeric := 0;
  v_allocated_egp_total numeric := 0;
  v_largest_partner_id uuid;
  v_largest_share numeric := 0;
  v_share numeric;
  v_share_egp numeric;
  v_result jsonb;
begin
  select owner_id into v_owner_id
  from public.projects
  where id = p_project_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'project not found';
  end if;

  perform public.terranex_assert_owner(v_owner_id);
  perform public.terranex_lock_financial_request(v_owner_id, p_request_id);
  v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;

  if p_total_amount <= 0 then
    raise exception using errcode = '23514', message = 'distribution amount must be positive';
  end if;
  if p_ownership_as_of_date > p_distribution_date then
    raise exception using errcode = '23514',
      message = 'ownership_as_of_date cannot be after distribution_date';
  end if;

  v_total_amount_egp := p_total_amount * p_fx_rate;

  insert into public.distributions (
    owner_id, project_id, distribution_date, ownership_as_of_date,
    total_amount, currency, fx_rate, total_amount_egp, status,
    notes, supporting_document_id, created_by
  ) values (
    v_owner_id, p_project_id, p_distribution_date, p_ownership_as_of_date,
    p_total_amount, p_currency, p_fx_rate, v_total_amount_egp, 'draft',
    p_notes, p_supporting_document_id, v_owner_id
  ) returning id into v_distribution_id;

  for v_partner in
    select pp.partner_id, pp.equity_pct
    from public.project_partners pp
    where pp.project_id = p_project_id
      and pp.owner_id = v_owner_id
      and pp.effective_from <= p_ownership_as_of_date
      and (pp.effective_to is null or pp.effective_to >= p_ownership_as_of_date)
  loop
    v_share := round((p_total_amount * v_partner.equity_pct / 100)::numeric, 2);
    v_share_egp := round((v_total_amount_egp * v_partner.equity_pct / 100)::numeric, 2);
    v_allocated_total := v_allocated_total + v_share;
    v_allocated_egp_total := v_allocated_egp_total + v_share_egp;

    if v_share > v_largest_share then
      v_largest_share := v_share;
      v_largest_partner_id := v_partner.partner_id;
    end if;

    insert into public.distribution_allocations (
      owner_id, distribution_id, partner_id, equity_pct_snapshot,
      allocated_amount, allocated_amount_egp, status
    ) values (
      v_owner_id, v_distribution_id, v_partner.partner_id, v_partner.equity_pct,
      v_share, v_share_egp, 'due'
    );
  end loop;

  if v_largest_partner_id is not null then
    declare
      v_rounding_diff numeric;
      v_rounding_diff_egp numeric;
    begin
      v_rounding_diff := p_total_amount - v_allocated_total;
      v_rounding_diff_egp := v_total_amount_egp - v_allocated_egp_total;

      if abs(v_rounding_diff) > 0.001 or abs(v_rounding_diff_egp) > 0.001 then
        update public.distribution_allocations
        set allocated_amount = allocated_amount + v_rounding_diff,
            allocated_amount_egp = allocated_amount_egp + v_rounding_diff_egp
        where distribution_id = v_distribution_id
          and partner_id = v_largest_partner_id
          and owner_id = v_owner_id;
      end if;
    end;
  end if;

  v_result := jsonb_build_object(
    'distribution_id', v_distribution_id,
    'total_amount', p_total_amount,
    'total_amount_egp', v_total_amount_egp,
    'status', 'draft'
  );

  perform public.terranex_audit_log(
    p_request_id,
    'record_distribution',
    'distribution',
    array[v_distribution_id],
    jsonb_build_object(
      'project_id', p_project_id,
      'distribution_date', p_distribution_date,
      'ownership_as_of_date', p_ownership_as_of_date,
      'total_amount', p_total_amount,
      'currency', p_currency::text,
      'fx_rate', p_fx_rate
    ),
    v_result,
    v_owner_id
  );

  return v_result;
end;
$fn$;

\echo '=== ROLLBACK 20260801000700 COMPLETE ==='
