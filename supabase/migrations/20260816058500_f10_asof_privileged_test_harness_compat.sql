-- F10 historical roll-up authorization compatibility.
--
-- The public SECURITY DEFINER wrapper must require an authenticated active
-- member for application/PostgREST callers. Direct invocation by the function
-- owner is also allowed so migration/replay verification can exercise the
-- read model without fabricating an application JWT. This is not an
-- application bypass: a DB owner already has unrestricted database authority,
-- while PostgREST connects as a different session role and must pass the JWT
-- membership checks below.

create or replace function public.portfolio_financial_rollup_asof(
  p_organization_id uuid,
  p_portfolio_id uuid,
  p_asof_date date
) returns table (
  portfolio_id uuid,
  organization_id uuid,
  portfolio_name text,
  currency text,
  org_reporting_currency text,
  project_count bigint,
  cash_balance_minor_units text,
  receivable_open_minor_units text,
  revenue_recognized_minor_units text,
  cost_of_sale_minor_units text,
  expense_posted_minor_units text,
  wip_posted_minor_units text,
  contributions_received_minor_units text,
  payable_open_minor_units text,
  paid_minor_units text,
  retention_held_minor_units text,
  disputed_obligations bigint,
  overdue_obligations bigint,
  open_commitment_minor_units text,
  realized_result_minor_units text,
  fac_minor_units text,
  open_exception_count bigint,
  fx_status text,
  converted_cash_balance_minor_units text,
  sector_exposure jsonb,
  cash_concentration_ratio text
)
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $$
declare
  v_actor uuid := auth.uid();
  v_direct_owner_call boolean := session_user = current_user;
begin
  if p_asof_date is null then
    raise exception 'as-of date required';
  end if;

  if not v_direct_owner_call then
    if v_actor is null then
      raise exception 'authentication required';
    end if;
    if not public.is_active_member(p_organization_id) then
      raise exception 'forbidden';
    end if;
  end if;

  if not exists (
    select 1
    from public.investment_portfolios p
    where p.id = p_portfolio_id
      and p.organization_id = p_organization_id
  ) then
    raise exception 'portfolio not found in organization';
  end if;

  return query
    select r.*
    from public.portfolio_financial_rollup_asof_impl(
      p_organization_id, p_portfolio_id, p_asof_date
    ) r;
end $$;

revoke all on function public.portfolio_financial_rollup_asof(uuid,uuid,date)
  from public, anon;
grant execute on function public.portfolio_financial_rollup_asof(uuid,uuid,date)
  to authenticated;
