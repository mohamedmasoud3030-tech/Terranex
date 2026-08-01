-- =============================================================================
-- Terranex — Ownership vertical slice hardening
-- =============================================================================
-- 1. record_distribution_atomic now posts distribution_entitlement ledger rows
--    in the same database transaction as the distribution and frozen allocations.
-- 2. Audit/frozen ownership tables reject direct mutation of immutable history.
-- =============================================================================

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
  v_ledger_ids uuid[] := '{}'::uuid[];
  v_check_violation constant text := '23514';
  v_internal_allocation_config constant text := 'terranex.internal_distribution_allocation_adjustment';
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
    raise exception using errcode = v_check_violation, message = 'distribution amount must be positive';
  end if;
  if p_fx_rate <= 0 then
    raise exception using errcode = v_check_violation, message = 'distribution fx_rate must be positive';
  end if;
  if p_ownership_as_of_date > p_distribution_date then
    raise exception using errcode = v_check_violation,
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
      and pp.equity_pct > 0
      and pp.effective_from <= p_ownership_as_of_date
      and (pp.effective_to is null or pp.effective_to >= p_ownership_as_of_date)
    order by pp.partner_id
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

  if v_largest_partner_id is null then
    raise exception using errcode = v_check_violation, message = 'distribution requires at least one active ownership allocation';
  end if;

  declare
    v_rounding_diff numeric;
    v_rounding_diff_egp numeric;
  begin
    v_rounding_diff := p_total_amount - v_allocated_total;
    v_rounding_diff_egp := v_total_amount_egp - v_allocated_egp_total;

      if abs(v_rounding_diff) > 0.001 or abs(v_rounding_diff_egp) > 0.001 then
        perform set_config(v_internal_allocation_config, 'on', true);
        update public.distribution_allocations
        set allocated_amount = allocated_amount + v_rounding_diff,
            allocated_amount_egp = allocated_amount_egp + v_rounding_diff_egp
        where distribution_id = v_distribution_id
          and partner_id = v_largest_partner_id
          and owner_id = v_owner_id;
        perform set_config(v_internal_allocation_config, 'off', true);
      end if;
  end;

  for v_partner in
    select partner_id, allocated_amount, allocated_amount_egp
    from public.distribution_allocations
    where owner_id = v_owner_id
      and distribution_id = v_distribution_id
    order by partner_id
  loop
    declare
      v_ledger_id uuid;
    begin
      insert into public.partner_ledger_entries (
        owner_id, project_id, partner_id, entry_type,
        amount, currency, fx_rate, amount_egp, posting_date,
        related_distribution_id, notes, created_by
      ) values (
        v_owner_id, p_project_id, v_partner.partner_id, 'distribution_entitlement',
        v_partner.allocated_amount, p_currency, p_fx_rate, v_partner.allocated_amount_egp, p_distribution_date,
        v_distribution_id, p_notes, v_owner_id
      ) returning id into v_ledger_id;
      v_ledger_ids := array_append(v_ledger_ids, v_ledger_id);
    end;
  end loop;

  v_result := jsonb_build_object(
    'distribution_id', v_distribution_id,
    'total_amount', p_total_amount,
    'total_amount_egp', v_total_amount_egp,
    'status', 'draft',
    'ledger_entry_ids', to_jsonb(v_ledger_ids)
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
      'fx_rate', p_fx_rate,
      'ledger_entry_ids', to_jsonb(v_ledger_ids)
    ),
    v_result,
    v_owner_id
  );

  return v_result;
end;
$fn$;

create or replace function public.terranex_prevent_immutable_ownership_mutation()
returns trigger
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_feature_not_supported constant text := '0A000';
  v_immutable_message constant text := 'immutable ownership history cannot be updated or deleted';
begin
  raise exception using errcode = v_feature_not_supported, message = v_immutable_message;
end;
$fn$;

create or replace function public.terranex_prevent_frozen_allocation_change()
returns trigger
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_feature_not_supported constant text := '0A000';
  v_internal_allocation_config constant text := 'terranex.internal_distribution_allocation_adjustment';
  v_immutable_allocation_message constant text := 'distribution allocations are immutable';
begin
  if current_setting(v_internal_allocation_config, true) = 'on' then
    return new;
  end if;
  if tg_op = 'DELETE' then
    raise exception using errcode = v_feature_not_supported, message = v_immutable_allocation_message;
  end if;
  if new.distribution_id is distinct from old.distribution_id
     or new.partner_id is distinct from old.partner_id
     or new.equity_pct_snapshot is distinct from old.equity_pct_snapshot
     or new.allocated_amount is distinct from old.allocated_amount
     or new.allocated_amount_egp is distinct from old.allocated_amount_egp then
    raise exception using errcode = v_feature_not_supported, message = 'distribution allocation snapshot cannot be edited';
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_equity_change_events_immutable on public.equity_change_events;
create trigger trg_equity_change_events_immutable
  before update or delete on public.equity_change_events
  for each row execute function public.terranex_prevent_immutable_ownership_mutation();

drop trigger if exists trg_partner_ledger_entries_immutable on public.partner_ledger_entries;
create trigger trg_partner_ledger_entries_immutable
  before update or delete on public.partner_ledger_entries
  for each row execute function public.terranex_prevent_immutable_ownership_mutation();

drop trigger if exists trg_distribution_allocations_frozen on public.distribution_allocations;
create trigger trg_distribution_allocations_frozen
  before update or delete on public.distribution_allocations
  for each row execute function public.terranex_prevent_frozen_allocation_change();

\echo '=== OWNERSHIP VERTICAL SLICE HARDENING: MIGRATION COMPLETE ==='
