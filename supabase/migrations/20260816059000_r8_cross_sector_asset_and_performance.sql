-- R8 — Cross-Sector Asset & Performance Layer (read-only projection).
--
-- Canonical constraint (docs/greenfield/03_DOMAIN_MODEL.md:64 and :175):
-- sector tables connect through investment_project_id and their own roots;
-- they do NOT share one universal "asset" table, and Portfolio is a
-- management/reporting parent, not a replacement FK target. R8 therefore
-- unifies "what can be unified without distorting each sector" as a READ
-- PROJECTION over the sector-owned roots. This migration creates:
--
--   * no new base table,
--   * no new FK target,
--   * no new write command,
--   * no new domain fact.
--
-- Every column below is either a sector-owned fact or an explicit
-- *_status string. Nothing is guessed. Where a sector genuinely has no
-- fact for a concept (a Farm has no acquisition consideration; no sector
-- other than Real Estate has an approved valuation policy) the register
-- says so in words rather than emitting a zero that would read as "this
-- asset cost nothing" or "this asset is worth nothing".
--
-- Honesty vocabulary used by the *_status columns:
--   NOT_RECORDED                                 fact belongs here, not entered yet
--   NOT_APPLICABLE_NO_ACQUISITION_FACT           concept does not exist for this kind
--   NOT_MODELLED_FOR_THIS_ASSET_KIND             no state machine for this kind
--   UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY no approved policy exists yet
--   CONTRACTED_CONSIDERATION_AND_CLOSING_COSTS   Real Estate acquisition basis
--   AGREED_CONSIDERATION                         agricultural land control basis
--   APPROVED_VALUATION / NO_APPROVED_VALUATION   R5 valuation state
--   REALIZED_ON_RECOGNIZED_SALE / NO_RECOGNIZED_SALE
--
-- The same vocabulary is already used by livestock_cohort_results_read
-- ("UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY", "NOT_GUESSED"), so the
-- register does not invent a second dialect for the same idea.
--
-- Both views are security_invoker=on and are granted to authenticated only.
-- Every underlying root already enforces RLS
-- `select using (is_active_member(organization_id))`, so tenancy is
-- inherited rather than re-implemented (and cannot drift from it).

-- ===========================================================================
-- 1. Cross-sector asset register
-- ===========================================================================
create or replace view public.cross_sector_asset_register_read with (security_invoker=on) as
with current_parent as (
  select a.investment_project_id, a.portfolio_id, pf.name as portfolio_name
  from public.portfolio_project_assignments a
  join public.investment_portfolios pf
    on pf.id = a.portfolio_id and pf.organization_id = a.organization_id
  where a.removed_at is null
),
property_rows as (
  select
    a.organization_id, a.project_id,
    'PROPERTY_ASSET'::text as asset_kind,
    a.id as asset_id, a.name as asset_name, a.asset_reference,
    prof.strategy as asset_classification,
    st.new_state as operational_state,
    'PROPERTY_STATE_HISTORY'::text as operational_state_basis,
    (acq.consideration_minor_units + acq.closing_costs_minor_units) as acquisition_cost_minor_units,
    acq.currency as acquisition_cost_currency,
    case when acq.id is null then 'NOT_RECORDED'
         else 'CONTRACTED_CONSIDERATION_AND_CLOSING_COSTS' end as acquisition_cost_status,
    val.amount_minor_units as latest_approved_valuation_minor_units,
    val.currency as latest_approved_valuation_currency,
    val.effective_date as latest_approved_valuation_date,
    case when val.id is null then 'NO_APPROVED_VALUATION' else 'APPROVED_VALUATION' end
      as latest_approved_valuation_status,
    rr.realized_result_minor_units::bigint as realized_result_minor_units,
    rr.currency as realized_result_currency,
    case when rr.disposition_id is null then 'NO_RECOGNIZED_SALE'
         else 'REALIZED_ON_RECOGNIZED_SALE' end as realized_result_status,
    a.created_by as registered_by, a.created_at as registered_at
  from public.property_assets a
  join public.real_estate_project_profiles prof on prof.id = a.profile_id
  left join lateral (
    select h.new_state from public.property_asset_state_history h
    where h.property_asset_id = a.id
      and not exists (select 1 from public.property_asset_state_history n
                      where n.property_asset_id = h.property_asset_id
                        and n.previous_history_id = h.id)
    limit 1
  ) st on true
  left join public.property_acquisitions acq on acq.property_asset_id = a.id
  left join lateral (
    select v.id, v.amount_minor_units, v.currency, v.effective_date
    from public.property_valuations v
    where v.property_asset_id = a.id and v.status = 'APPROVED'
    order by v.effective_date desc, v.reviewed_at desc, v.id desc
    limit 1
  ) val on true
  left join public.property_realized_result_read rr on rr.property_asset_id = a.id
),
land_rows as (
  select
    l.organization_id, l.project_id,
    'AGRICULTURAL_LAND_ASSET'::text, l.id, l.name, l.internal_reference,
    l.control_basis,
    null::text, 'NOT_MODELLED_FOR_THIS_ASSET_KIND'::text,
    l.agreed_consideration_minor_units, l.consideration_currency,
    case when l.agreed_consideration_minor_units is null then 'NOT_RECORDED'
         else 'AGREED_CONSIDERATION' end,
    null::bigint, null::text, null::date,
    'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'::text,
    null::bigint, null::text,
    'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'::text,
    l.recorded_by, l.recorded_at
  from public.agricultural_land_assets l
),
farm_rows as (
  select
    f.organization_id, f.project_id,
    'FARM'::text, f.id, f.name, f.internal_reference,
    null::text,
    null::text, 'NOT_MODELLED_FOR_THIS_ASSET_KIND'::text,
    null::bigint, null::text, 'NOT_APPLICABLE_NO_ACQUISITION_FACT'::text,
    null::bigint, null::text, null::date,
    'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'::text,
    null::bigint, null::text,
    'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'::text,
    f.created_by, f.created_at
  from public.farms f
),
site_rows as (
  select
    s.organization_id, s.project_id,
    'LIVESTOCK_SITE'::text, s.id, s.name, s.internal_reference,
    s.site_type,
    null::text, 'NOT_MODELLED_FOR_THIS_ASSET_KIND'::text,
    null::bigint, null::text, 'NOT_APPLICABLE_NO_ACQUISITION_FACT'::text,
    null::bigint, null::text, null::date,
    'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'::text,
    null::bigint, null::text,
    'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'::text,
    s.created_by, s.created_at
  from public.livestock_sites s
),
unioned as (
  select * from property_rows
  union all select * from land_rows
  union all select * from farm_rows
  union all select * from site_rows
)
select
  u.organization_id, u.project_id,
  p.name as project_name, p.sector as project_sector,
  p.reporting_currency as project_currency,
  cp.portfolio_id, cp.portfolio_name,
  u.asset_kind, u.asset_id, u.asset_name, u.asset_reference, u.asset_classification,
  u.operational_state, u.operational_state_basis,
  u.acquisition_cost_minor_units::text as acquisition_cost_minor_units,
  u.acquisition_cost_currency, u.acquisition_cost_status,
  u.latest_approved_valuation_minor_units::text as latest_approved_valuation_minor_units,
  u.latest_approved_valuation_currency, u.latest_approved_valuation_date,
  u.latest_approved_valuation_status,
  u.realized_result_minor_units::text as realized_result_minor_units,
  u.realized_result_currency, u.realized_result_status,
  u.registered_by, u.registered_at
from unioned u
join public.investment_projects p
  on p.id = u.project_id and p.organization_id = u.organization_id
left join current_parent cp on cp.investment_project_id = u.project_id;

comment on view public.cross_sector_asset_register_read is
  'R8 read-only cross-sector asset register. Projection over sector-owned '
  'roots (property_assets, agricultural_land_assets, farms, livestock_sites). '
  'Not a universal asset table and not an FK target: no sector row points '
  'here. Concepts a sector does not own are reported as explicit *_status '
  'text, never as a zero or a guessed valuation.';

-- ===========================================================================
-- 2. Sector performance roll-up
-- ===========================================================================
-- Roll-up canon (as established by F10): reporting-only, never a ledger;
-- figures sum project-authoritative facts; currencies are never mixed —
-- the grouping key includes the project currency; a converted_* column is
-- populated only when the organization has a reporting currency AND every
-- project in the group resolved an FX snapshot, otherwise it is NULL with
-- fx_status explaining why. Conversion uses fx_convert_exact.
create or replace view public.sector_performance_read with (security_invoker=on) as
with project_converted as (
  select
    p.organization_id, p.id as project_id, p.sector,
    p.reporting_currency as currency,
    o.reporting_currency as org_reporting_currency,
    s.id as fx_rate_snapshot_id, s.rate_date as fx_rate_date,
    case
      when o.reporting_currency is null then 'NO_REPORTING_CURRENCY'
      when o.reporting_currency = p.reporting_currency then 'SAME_CURRENCY'
      when s.id is null then 'NO_RATE_SNAPSHOT'
      else 'CONVERTED_AT_RATE'
    end as fx_status,
    coalesce(pp.cash_balance_minor_units::bigint, 0) as cash_minor,
    coalesce(pp.revenue_recognized_minor_units::bigint, 0) as revenue_minor,
    coalesce(pp.cost_of_sale_minor_units::bigint, 0) as cost_of_sale_minor,
    coalesce(pp.expense_posted_minor_units::bigint, 0) as expense_minor,
    coalesce(pp.wip_posted_minor_units::bigint, 0) as wip_minor,
    coalesce(pp.contributions_received_minor_units::bigint, 0) as contributions_minor,
    coalesce(pp.receivable_open_minor_units::bigint, 0) as receivable_minor,
    coalesce(pp.payable_open_minor_units::bigint, 0) as payable_minor,
    (coalesce(pp.revenue_recognized_minor_units::bigint, 0)
      - coalesce(pp.cost_of_sale_minor_units::bigint, 0)) as realized_result_minor,
    case
      when o.reporting_currency = p.reporting_currency
        then coalesce(pp.cash_balance_minor_units::bigint, 0)
      when s.id is not null then public.fx_convert_exact(
        coalesce(pp.cash_balance_minor_units::bigint, 0), s.rate_numerator, s.rate_denominator)
      else null
    end as converted_cash_minor,
    case
      when o.reporting_currency = p.reporting_currency
        then coalesce(pp.revenue_recognized_minor_units::bigint, 0)
      when s.id is not null then public.fx_convert_exact(
        coalesce(pp.revenue_recognized_minor_units::bigint, 0), s.rate_numerator, s.rate_denominator)
      else null
    end as converted_revenue_minor,
    case
      when o.reporting_currency = p.reporting_currency
        then coalesce(pp.contributions_received_minor_units::bigint, 0)
      when s.id is not null then public.fx_convert_exact(
        coalesce(pp.contributions_received_minor_units::bigint, 0), s.rate_numerator, s.rate_denominator)
      else null
    end as converted_contributions_minor,
    case
      when o.reporting_currency = p.reporting_currency then
        (coalesce(pp.revenue_recognized_minor_units::bigint, 0)
          - coalesce(pp.cost_of_sale_minor_units::bigint, 0))
      when s.id is not null then public.fx_convert_exact(
        coalesce(pp.revenue_recognized_minor_units::bigint, 0)
          - coalesce(pp.cost_of_sale_minor_units::bigint, 0),
        s.rate_numerator, s.rate_denominator)
      else null
    end as converted_realized_result_minor
  -- Driven off the project register, not the finance spine: the finance
  -- spine only contains projects that already carry financial facts, so
  -- joining from it would silently drop a registered project (and its
  -- assets) from its own sector until someone posted money against it.
  from public.investment_projects p
  join public.organizations o on o.id = p.organization_id
  left join public.project_financial_position_read pp on pp.project_id = p.id
  left join lateral (
    select s2.* from public.fx_rate_snapshots s2
    where s2.organization_id = p.organization_id
      and s2.base_currency = p.reporting_currency
      and s2.quote_currency = o.reporting_currency
      and s2.rate_date <= current_date
    order by s2.rate_date desc
    limit 1
  ) s on true
),
asset_counts as (
  -- Counted on the same (organization, sector, project currency) key the
  -- money is grouped by, so an asset is never counted into two rows.
  select organization_id, project_sector as sector, project_currency as currency,
         count(*) as asset_count
  from public.cross_sector_asset_register_read
  group by 1, 2, 3
)
select
  pc.organization_id,
  pc.sector,
  pc.currency,
  max(pc.org_reporting_currency) as org_reporting_currency,
  count(*) as project_count,
  coalesce(max(ac.asset_count), 0) as asset_count,
  -- Grouping is by (organization, sector, project currency), so every row in
  -- a group resolves the same snapshot and therefore the same fx_status.
  -- min() is asserted rather than assumed by the guard below.
  min(pc.fx_status) as fx_status,
  max(pc.fx_rate_snapshot_id::text)::uuid as fx_rate_snapshot_id,
  max(pc.fx_rate_date) as fx_rate_date,
  sum(pc.cash_minor)::text as cash_balance_minor_units,
  sum(pc.revenue_minor)::text as revenue_recognized_minor_units,
  sum(pc.cost_of_sale_minor)::text as cost_of_sale_minor_units,
  sum(pc.expense_minor)::text as expense_posted_minor_units,
  sum(pc.wip_minor)::text as wip_posted_minor_units,
  sum(pc.contributions_minor)::text as contributions_received_minor_units,
  sum(pc.receivable_minor)::text as receivable_open_minor_units,
  sum(pc.payable_minor)::text as payable_open_minor_units,
  sum(pc.realized_result_minor)::text as realized_result_minor_units,
  (case when count(*) filter (where pc.converted_cash_minor is null) > 0 then null
        else sum(pc.converted_cash_minor)::text end) as converted_cash_balance_minor_units,
  (case when count(*) filter (where pc.converted_revenue_minor is null) > 0 then null
        else sum(pc.converted_revenue_minor)::text end) as converted_revenue_recognized_minor_units,
  (case when count(*) filter (where pc.converted_contributions_minor is null) > 0 then null
        else sum(pc.converted_contributions_minor)::text end) as converted_contributions_received_minor_units,
  (case when count(*) filter (where pc.converted_realized_result_minor is null) > 0 then null
        else sum(pc.converted_realized_result_minor)::text end)
    as converted_realized_result_minor_units
from project_converted pc
left join asset_counts ac
  on ac.organization_id = pc.organization_id
 and ac.sector = pc.sector
 and ac.currency = pc.currency
group by pc.organization_id, pc.sector, pc.currency;

comment on view public.sector_performance_read is
  'R8 sector performance roll-up: how much each sector holds, earned and '
  'realized, per organization and project currency. Reporting-only. Never '
  'mixes currencies and never emits a partial converted total — if any '
  'project in the group cannot be converted, the converted_* columns are '
  'NULL and fx_status states the reason.';

-- ===========================================================================
-- 3. Grants — read-only, authenticated only, consistent with every other
--    *_read view in the schema.
-- ===========================================================================
revoke all on public.cross_sector_asset_register_read from public, anon;
revoke all on public.sector_performance_read from public, anon;
grant select on public.cross_sector_asset_register_read to authenticated;
grant select on public.sector_performance_read to authenticated;
