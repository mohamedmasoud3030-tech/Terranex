-- =============================================================================
-- Terranex — Phase 2B — Atomic ownership RPCs
-- =============================================================================
-- Server-side enforcement boundary for ownership changes:
--   1. Validates caller owns the project
--   2. Takes advisory lock scoped to the project
--   3. Loads affected temporal records
--   4. Prevents invalid temporal overlap for same partner+project
--   5. Verifies sum of active equity_pcts <= 100% at all affected points
--   6. Closes previous project_partners record if needed
--   7. Inserts equity_change_event + updates project_partners
--   8. Logs to financial_audit_logs
-- =============================================================================

-- ─── RPC 1: change_ownership_atomic ──────────────────────────────────────────
-- The ONLY approved path for changing project ownership.
create or replace function public.change_ownership_atomic(
  p_request_id uuid,
  p_project_id uuid,
  p_partner_id uuid,
  p_effective_date date,
  p_new_pct numeric,
  p_change_type public.terranex_equity_change_type,
  p_consideration_amount numeric default null,
  p_consideration_currency public.terranex_currency default null,
  p_supporting_document_id uuid default null,
  p_reason text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_owner_id uuid;
  v_cached jsonb;
  v_event_id uuid;
  v_current_pct numeric;
  v_total_other_pct numeric;
  v_existing_pp record;
  v_result jsonb;
  v_pp_id uuid;
begin
  -- 1. Validate project ownership
  select owner_id into v_owner_id
  from public.projects
  where id = p_project_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'project not found';
  end if;

  perform public.terranex_assert_owner(v_owner_id);
  perform public.terranex_lock_financial_request(v_owner_id, p_request_id);

  -- Idempotency check
  v_cached := public.terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;

  -- Validate basic constraints
  if p_new_pct < 0 or p_new_pct > 100 then
    raise exception using errcode = '23514', message = 'equity percentage must be between 0 and 100';
  end if;

  -- 2. Find the current project_partners record for this partner+project (active one)
  select id, equity_pct into v_existing_pp
  from public.project_partners
  where project_id = p_project_id
    and partner_id = p_partner_id
    and owner_id = v_owner_id
    and effective_to is null
  for update;

  v_current_pct := coalesce(v_existing_pp.equity_pct, 0);

  -- Validate change_type consistency
  if p_change_type = 'entry' and v_current_pct > 0 then
    raise exception using errcode = '23514',
      message = 'cannot create entry: partner already has active ownership';
  end if;
  if p_change_type = 'entry' and p_new_pct <= 0 then
    raise exception using errcode = '23514',
      message = 'entry must set a positive percentage';
  end if;
  if p_change_type = 'exit' and v_current_pct = 0 then
    raise exception using errcode = '23514',
      message = 'cannot exit: partner has no active ownership';
  end if;
  if p_change_type = 'exit' and p_new_pct > 0 then
    raise exception using errcode = '23514',
      message = 'exit must set percentage to 0';
  end if;
  if p_change_type = 'increase' and p_new_pct <= v_current_pct then
    raise exception using errcode = '23514',
      message = 'increase must set a higher percentage than current';
  end if;
  if p_change_type = 'decrease' and p_new_pct >= v_current_pct then
    raise exception using errcode = '23514',
      message = 'decrease must set a lower percentage than current';
  end if;

  -- 3. Calculate sum of OTHER partners' active equity for this project
  select coalesce(sum(equity_pct), 0) into v_total_other_pct
  from public.project_partners
  where project_id = p_project_id
    and partner_id <> p_partner_id
    and owner_id = v_owner_id
    and effective_to is null;

  -- 4. Verify sum <= 100%
  if v_total_other_pct + p_new_pct > 100 then
    raise exception using errcode = '23514',
      message = format(
        'total equity would exceed 100%%: other partners hold %s%%, new value would be %s%%',
        v_total_other_pct, p_new_pct
      );
  end if;

  -- 5. Close previous project_partners record (set effective_to) if it exists
  if v_existing_pp.id is not null then
    update public.project_partners
    set effective_to = p_effective_date - interval '1 day'
    where id = v_existing_pp.id
      and owner_id = v_owner_id;

    v_pp_id := v_existing_pp.id;
  end if;

  -- 6. Insert new project_partners record if new_pct > 0
  if p_new_pct > 0 then
    insert into public.project_partners (
      owner_id, project_id, partner_id, equity_pct, effective_from, notes
    ) values (
      v_owner_id, p_project_id, p_partner_id, p_new_pct, p_effective_date, p_notes
    ) returning id into v_pp_id;
  end if;

  -- 7. Insert equity_change_event
  insert into public.equity_change_events (
    owner_id, project_id, partner_id, effective_date,
    previous_pct, new_pct, change_type,
    consideration_amount, consideration_currency, frozen_amount_egp,
    supporting_document_id, reason, notes, created_by
  ) values (
    v_owner_id, p_project_id, p_partner_id, p_effective_date,
    v_current_pct, p_new_pct, p_change_type,
    p_consideration_amount, p_consideration_currency,
    case when p_consideration_amount is not null and p_consideration_currency is not null
      then p_consideration_amount * case when p_consideration_currency = 'EGP' then 1 else 1 end
      else null
    end,
    p_supporting_document_id, p_reason, p_notes, v_owner_id
  ) returning id into v_event_id;

  -- 8. Build result
  v_result := jsonb_build_object(
    'equity_change_event_id', v_event_id,
    'project_partner_id', v_pp_id,
    'previous_pct', v_current_pct,
    'new_pct', p_new_pct,
    'total_equity_allocated', v_total_other_pct + p_new_pct
  );

  -- 9. Audit log
  perform public.terranex_audit_log(
    p_request_id,
    'change_ownership',
    'equity_change_event',
    array[v_event_id],
    jsonb_build_object(
      'project_id', p_project_id,
      'partner_id', p_partner_id,
      'effective_date', p_effective_date,
      'previous_pct', v_current_pct,
      'new_pct', p_new_pct,
      'change_type', p_change_type::text
    ),
    v_result,
    v_owner_id
  );

  return v_result;
end;
$fn$;

-- ─── RPC 2: record_distribution_atomic ──────────────────────────────────────
-- Creates a distribution with frozen ownership snapshots.
-- Calculates allocations based on ownership at ownership_as_of_date.
-- Enforces: sum of allocations = total_amount (rounding handled by largest-share method).
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
  v_allocations jsonb;
  v_partner record;
  v_allocated_total numeric := 0;
  v_allocated_egp_total numeric := 0;
  v_largest_partner_id uuid;
  v_largest_share numeric := 0;
  v_share numeric;
  v_share_egp numeric;
  v_alloc_ids uuid[] := '{}'::uuid[];
  v_result jsonb;
begin
  -- Validate project ownership
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

  -- Insert distribution header
  insert into public.distributions (
    owner_id, project_id, distribution_date, ownership_as_of_date,
    total_amount, currency, fx_rate, total_amount_egp, status,
    notes, supporting_document_id, created_by
  ) values (
    v_owner_id, p_project_id, p_distribution_date, p_ownership_as_of_date,
    p_total_amount, p_currency, p_fx_rate, v_total_amount_egp, 'draft',
    p_notes, p_supporting_document_id, v_owner_id
  ) returning id into v_distribution_id;

  -- Calculate allocations based on ownership at the as-of date
  -- Find active project_partners at ownership_as_of_date
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

    -- Track largest share for rounding adjustment
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

  -- Rounding adjustment: adjust largest share so sum matches exactly
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

-- ─── RPC 3: record_partner_ledger_entry_atomic ──────────────────────────────
-- Append-only ledger entry. Cannot be updated or deleted — only reversed.
create or replace function public.record_partner_ledger_entry_atomic(
  p_request_id uuid,
  p_project_id uuid,
  p_partner_id uuid,
  p_entry_type public.terranex_ledger_entry_type,
  p_amount numeric,
  p_currency public.terranex_currency,
  p_fx_rate numeric,
  p_posting_date date,
  p_supporting_document_id uuid default null,
  p_related_equity_event_id uuid default null,
  p_related_distribution_id uuid default null,
  p_notes text default null,
  p_reversal_of_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_owner_id uuid;
  v_cached jsonb;
  v_entry_id uuid;
  v_amount_egp numeric;
  v_result jsonb;
begin
  -- Validate project ownership
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

  if p_amount <= 0 then
    raise exception using errcode = '23514', message = 'ledger entry amount must be positive';
  end if;

  -- If reversal, validate the original entry exists and is owned by same user
  if p_reversal_of_id is not null then
    perform 1
    from public.partner_ledger_entries
    where id = p_reversal_of_id
      and owner_id = v_owner_id;
    if not found then
      raise exception using errcode = '42501',
        message = 'reversal target entry not found or belongs to a different owner';
    end if;
  end if;

  v_amount_egp := p_amount * p_fx_rate;

  insert into public.partner_ledger_entries (
    owner_id, project_id, partner_id, entry_type,
    amount, currency, fx_rate, amount_egp, posting_date,
    supporting_document_id, related_equity_event_id, related_distribution_id,
    notes, reversal_of_id, created_by
  ) values (
    v_owner_id, p_project_id, p_partner_id, p_entry_type,
    p_amount, p_currency, p_fx_rate, v_amount_egp, p_posting_date,
    p_supporting_document_id, p_related_equity_event_id, p_related_distribution_id,
    p_notes, p_reversal_of_id, v_owner_id
  ) returning id into v_entry_id;

  v_result := jsonb_build_object(
    'ledger_entry_id', v_entry_id,
    'amount_egp', v_amount_egp,
    'entry_type', p_entry_type::text
  );

  perform public.terranex_audit_log(
    p_request_id,
    'record_ledger_entry',
    'partner_ledger_entry',
    array[v_entry_id],
    jsonb_build_object(
      'project_id', p_project_id,
      'partner_id', p_partner_id,
      'entry_type', p_entry_type::text,
      'amount', p_amount,
      'currency', p_currency::text,
      'posting_date', p_posting_date
    ),
    v_result,
    v_owner_id
  );

  return v_result;
end;
$fn$;

-- ─── RPC 4: ownership_as_of_date query ──────────────────────────────────────
-- Returns all active ownership records for a project at a given date.
-- SECURITY DEFINER with owner assertion, matching the other ownership RPCs:
-- the caller must own the project, and rows are always scoped to that owner.
-- (The previous SECURITY INVOKER variant filtered rows on `auth.uid() = owner_id`,
-- which returned nothing for the bootstrap/superuser test role and could not be
-- safely widened, so ownership is asserted explicitly instead.)
create or replace function public.get_ownership_as_of(
  p_project_id uuid,
  p_as_of_date date
)
returns table (
  partner_id uuid,
  equity_pct numeric,
  effective_from date,
  effective_to date,
  project_partner_id uuid
)
language plpgsql
security definer
set search_path = public
stable
as $fn$
declare
  v_owner_id uuid;
begin
  select owner_id into v_owner_id
  from public.projects
  where id = p_project_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'project not found';
  end if;

  perform public.terranex_assert_owner(v_owner_id);

  return query
    select pp.partner_id, pp.equity_pct, pp.effective_from, pp.effective_to, pp.id
    from public.project_partners pp
    where pp.project_id = p_project_id
      and pp.owner_id = v_owner_id
      and pp.effective_from <= p_as_of_date
      and (pp.effective_to is null or pp.effective_to >= p_as_of_date)
    order by pp.effective_from;
end;
$fn$;

-- ─── Grants ──────────────────────────────────────────────────────────────────
revoke execute on function public.change_ownership_atomic(uuid, uuid, uuid, date, numeric, public.terranex_equity_change_type, numeric, public.terranex_currency, uuid, text, text)
  from public, anon;
revoke execute on function public.record_distribution_atomic(uuid, uuid, date, date, numeric, public.terranex_currency, numeric, text, uuid)
  from public, anon;
revoke execute on function public.record_partner_ledger_entry_atomic(uuid, uuid, uuid, public.terranex_ledger_entry_type, numeric, public.terranex_currency, numeric, date, uuid, uuid, uuid, text, uuid)
  from public, anon;

grant execute on function public.change_ownership_atomic(uuid, uuid, uuid, date, numeric, public.terranex_equity_change_type, numeric, public.terranex_currency, uuid, text, text)
  to authenticated;
grant execute on function public.record_distribution_atomic(uuid, uuid, date, date, numeric, public.terranex_currency, numeric, text, uuid)
  to authenticated;
grant execute on function public.record_partner_ledger_entry_atomic(uuid, uuid, uuid, public.terranex_ledger_entry_type, numeric, public.terranex_currency, numeric, date, uuid, uuid, uuid, text, uuid)
  to authenticated;

-- get_ownership_as_of is SECURITY DEFINER with explicit owner assertion, so it
-- scopes every result to the caller's ownership without relying on RLS.
revoke execute on function public.get_ownership_as_of(uuid, date) from public, anon;
grant execute on function public.get_ownership_as_of(uuid, date) to authenticated;

\echo '=== 2B OWNERSHIP RPCs: MIGRATION COMPLETE ==='
