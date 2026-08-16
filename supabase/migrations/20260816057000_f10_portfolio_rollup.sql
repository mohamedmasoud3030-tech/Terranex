-- F10 — Portfolio & Organization Financial Roll-up.
--
-- Canonical rules honored here:
--   * The Portfolio is a management/reporting parent, never a ledger.
--     Every roll-up number is a sum over project-authoritative facts from
--     project_financial_position_read.
--   * Roll-ups never sum across currencies. Per-currency rows are always
--     present; a converted column exists only when the organization
--     declares a reporting currency AND an explicit rate snapshot (F6)
--     exists for that currency pair on or before today. Otherwise the
--     converted column is NULL and fx_status says exactly why.
--   * When project currency = org reporting currency, converted values are
--     the originals (1:1), never a synthetic rate.
--   * Membership is the current (removed_at is null) parent assignment;
--     historical memberships never rewrite old reports because roll-ups
--     are derived at read time from the same immutable facts.
--   * Organization consolidation covers every project of the organization,
--     whether or not it is currently inside a portfolio. The consolidated
--     row is NULL (never guessed) whenever any project currency lacks a
--     rate snapshot, or when the org has no reporting currency and more
--     than one project currency exists.

create or replace view public.portfolio_financial_rollup_read with (security_invoker=on) as
with project_converted as (
  select
    pp.*,
    o.reporting_currency as org_reporting_currency,
    s.id as fx_rate_snapshot_id,
    s.rate_date as fx_rate_date,
    case
      when o.reporting_currency is null then 'NO_REPORTING_CURRENCY'
      when o.reporting_currency = pp.currency then 'SAME_CURRENCY'
      when s.id is null then 'NO_RATE_SNAPSHOT'
      else 'CONVERTED_AT_RATE'
    end as fx_status,
    case
      when o.reporting_currency = pp.currency then pp.cash_balance_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.cash_balance_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_cash_minor,
    case
      when o.reporting_currency = pp.currency then pp.receivable_open_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.receivable_open_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_receivable_minor,
    case
      when o.reporting_currency = pp.currency then pp.revenue_recognized_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.revenue_recognized_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_revenue_minor,
    case
      when o.reporting_currency = pp.currency then pp.cost_of_sale_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.cost_of_sale_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_cost_of_sale_minor,
    case
      when o.reporting_currency = pp.currency then pp.expense_posted_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.expense_posted_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_expense_minor,
    case
      when o.reporting_currency = pp.currency then pp.wip_posted_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.wip_posted_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_wip_minor,
    case
      when o.reporting_currency = pp.currency then pp.contributions_received_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.contributions_received_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_contributions_minor,
    case
      when o.reporting_currency = pp.currency then pp.payable_open_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.payable_open_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_payable_minor,
    case
      when o.reporting_currency = pp.currency then pp.paid_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.paid_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_paid_minor,
    case
      when o.reporting_currency = pp.currency then pp.retention_held_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.retention_held_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_retention_minor
  from public.project_financial_position_read pp
  join public.organizations o on o.id = pp.organization_id
  left join lateral (
    select s2.* from public.fx_rate_snapshots s2
    where s2.organization_id = pp.organization_id
      and s2.base_currency = pp.currency
      and s2.quote_currency = o.reporting_currency
      and s2.rate_date <= current_date
    order by s2.rate_date desc
    limit 1
  ) s on true
)
select
  pf.id as portfolio_id,
  pf.organization_id,
  pf.name as portfolio_name,
  pf.status as portfolio_status,
  pc.currency,
  pc.org_reporting_currency,
  count(pc.project_id) as project_count,
  sum(pc.cash_balance_minor_units::bigint)::text as cash_balance_minor_units,
  sum(pc.receivable_open_minor_units::bigint)::text as receivable_open_minor_units,
  sum(pc.revenue_recognized_minor_units::bigint)::text as revenue_recognized_minor_units,
  sum(pc.cost_of_sale_minor_units::bigint)::text as cost_of_sale_minor_units,
  sum(pc.expense_posted_minor_units::bigint)::text as expense_posted_minor_units,
  sum(pc.wip_posted_minor_units::bigint)::text as wip_posted_minor_units,
  sum(pc.contributions_received_minor_units::bigint)::text as contributions_received_minor_units,
  sum(pc.payable_open_minor_units::bigint)::text as payable_open_minor_units,
  sum(pc.paid_minor_units::bigint)::text as paid_minor_units,
  sum(pc.retention_held_minor_units::bigint)::text as retention_held_minor_units,
  sum(pc.disputed_obligations) as disputed_obligations,
  sum(pc.overdue_obligations) as overdue_obligations,
  (array_agg(pc.fx_rate_snapshot_id))[1] as fx_rate_snapshot_id,
  min(pc.fx_rate_date) as fx_rate_date,
  min(pc.fx_status) as fx_status,
  sum(pc.converted_cash_minor)::text as converted_cash_balance_minor_units,
  sum(pc.converted_receivable_minor)::text as converted_receivable_open_minor_units,
  sum(pc.converted_revenue_minor)::text as converted_revenue_recognized_minor_units,
  sum(pc.converted_cost_of_sale_minor)::text as converted_cost_of_sale_minor_units,
  sum(pc.converted_expense_minor)::text as converted_expense_posted_minor_units,
  sum(pc.converted_wip_minor)::text as converted_wip_posted_minor_units,
  sum(pc.converted_contributions_minor)::text as converted_contributions_received_minor_units,
  sum(pc.converted_payable_minor)::text as converted_payable_open_minor_units,
  sum(pc.converted_paid_minor)::text as converted_paid_minor_units,
  sum(pc.converted_retention_minor)::text as converted_retention_held_minor_units
from public.investment_portfolios pf
join public.portfolio_project_assignments a
  on a.portfolio_id = pf.id and a.removed_at is null
join project_converted pc on pc.project_id = a.investment_project_id
group by pf.id, pf.organization_id, pf.name, pf.status,
         pc.currency, pc.org_reporting_currency;

-- Organization consolidated view: per-currency detail rows plus, when the
-- organization declares a reporting currency, an honest consolidated row.
create or replace view public.organization_financial_consolidation_read with (security_invoker=on) as
with project_converted as (
  select
    pp.*,
    o.reporting_currency as org_reporting_currency,
    s.id as fx_rate_snapshot_id,
    s.rate_date as fx_rate_date,
    case
      when o.reporting_currency is null then 'NO_REPORTING_CURRENCY'
      when o.reporting_currency = pp.currency then 'SAME_CURRENCY'
      when s.id is null then 'NO_RATE_SNAPSHOT'
      else 'CONVERTED_AT_RATE'
    end as fx_status,
    case
      when o.reporting_currency = pp.currency then pp.cash_balance_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.cash_balance_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_cash_minor,
    case
      when o.reporting_currency = pp.currency then pp.receivable_open_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.receivable_open_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_receivable_minor,
    case
      when o.reporting_currency = pp.currency then pp.revenue_recognized_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.revenue_recognized_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_revenue_minor,
    case
      when o.reporting_currency = pp.currency then pp.cost_of_sale_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.cost_of_sale_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_cost_of_sale_minor,
    case
      when o.reporting_currency = pp.currency then pp.expense_posted_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.expense_posted_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_expense_minor,
    case
      when o.reporting_currency = pp.currency then pp.wip_posted_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.wip_posted_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_wip_minor,
    case
      when o.reporting_currency = pp.currency then pp.contributions_received_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.contributions_received_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_contributions_minor,
    case
      when o.reporting_currency = pp.currency then pp.payable_open_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.payable_open_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_payable_minor,
    case
      when o.reporting_currency = pp.currency then pp.paid_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.paid_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_paid_minor,
    case
      when o.reporting_currency = pp.currency then pp.retention_held_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.retention_held_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_retention_minor
  from public.project_financial_position_read pp
  join public.organizations o on o.id = pp.organization_id
  left join lateral (
    select s2.* from public.fx_rate_snapshots s2
    where s2.organization_id = pp.organization_id
      and s2.base_currency = pp.currency
      and s2.quote_currency = o.reporting_currency
      and s2.rate_date <= current_date
    order by s2.rate_date desc
    limit 1
  ) s on true
),
per_currency as (
  select
    pc.organization_id,
    pc.currency,
    pc.org_reporting_currency,
    count(pc.project_id) as project_count,
    sum(pc.cash_balance_minor_units::bigint)::text as cash_balance_minor_units,
    sum(pc.receivable_open_minor_units::bigint)::text as receivable_open_minor_units,
    sum(pc.revenue_recognized_minor_units::bigint)::text as revenue_recognized_minor_units,
    sum(pc.cost_of_sale_minor_units::bigint)::text as cost_of_sale_minor_units,
    sum(pc.expense_posted_minor_units::bigint)::text as expense_posted_minor_units,
    sum(pc.wip_posted_minor_units::bigint)::text as wip_posted_minor_units,
    sum(pc.contributions_received_minor_units::bigint)::text as contributions_received_minor_units,
    sum(pc.payable_open_minor_units::bigint)::text as payable_open_minor_units,
    sum(pc.paid_minor_units::bigint)::text as paid_minor_units,
    sum(pc.retention_held_minor_units::bigint)::text as retention_held_minor_units,
    sum(pc.disputed_obligations) as disputed_obligations,
    sum(pc.overdue_obligations) as overdue_obligations,
    (array_agg(pc.fx_rate_snapshot_id))[1] as fx_rate_snapshot_id,
    min(pc.fx_rate_date) as fx_rate_date,
    min(pc.fx_status) as fx_status,
    sum(pc.converted_cash_minor)::text as converted_cash_balance_minor_units,
    sum(pc.converted_receivable_minor)::text as converted_receivable_open_minor_units,
    sum(pc.converted_revenue_minor)::text as converted_revenue_recognized_minor_units,
    sum(pc.converted_cost_of_sale_minor)::text as converted_cost_of_sale_minor_units,
    sum(pc.converted_expense_minor)::text as converted_expense_posted_minor_units,
    sum(pc.converted_wip_minor)::text as converted_wip_posted_minor_units,
    sum(pc.converted_contributions_minor)::text as converted_contributions_received_minor_units,
    sum(pc.converted_payable_minor)::text as converted_payable_open_minor_units,
    sum(pc.converted_paid_minor)::text as converted_paid_minor_units,
    sum(pc.converted_retention_minor)::text as converted_retention_held_minor_units
  from project_converted pc
  group by pc.organization_id, pc.currency, pc.org_reporting_currency
),
consolidated as (
  select
    pc.organization_id,
    min(pc.org_reporting_currency) as org_reporting_currency,
    count(pc.project_id) as project_count,
    case when min(pc.org_reporting_currency) is null
           and count(distinct pc.currency) = 1
         then sum(pc.cash_balance_minor_units::bigint)::text
         else null::text
    end as cash_balance_minor_units,
    case when min(pc.org_reporting_currency) is null
           and count(distinct pc.currency) = 1
         then sum(pc.receivable_open_minor_units::bigint)::text
         else null::text
    end as receivable_open_minor_units,
    case when min(pc.org_reporting_currency) is null
           and count(distinct pc.currency) = 1
         then sum(pc.revenue_recognized_minor_units::bigint)::text
         else null::text
    end as revenue_recognized_minor_units,
    case when min(pc.org_reporting_currency) is null
           and count(distinct pc.currency) = 1
         then sum(pc.cost_of_sale_minor_units::bigint)::text
         else null::text
    end as cost_of_sale_minor_units,
    case when min(pc.org_reporting_currency) is null
           and count(distinct pc.currency) = 1
         then sum(pc.expense_posted_minor_units::bigint)::text
         else null::text
    end as expense_posted_minor_units,
    case when min(pc.org_reporting_currency) is null
           and count(distinct pc.currency) = 1
         then sum(pc.wip_posted_minor_units::bigint)::text
         else null::text
    end as wip_posted_minor_units,
    case when min(pc.org_reporting_currency) is null
           and count(distinct pc.currency) = 1
         then sum(pc.contributions_received_minor_units::bigint)::text
         else null::text
    end as contributions_received_minor_units,
    case when min(pc.org_reporting_currency) is null
           and count(distinct pc.currency) = 1
         then sum(pc.payable_open_minor_units::bigint)::text
         else null::text
    end as payable_open_minor_units,
    case when min(pc.org_reporting_currency) is null
           and count(distinct pc.currency) = 1
         then sum(pc.paid_minor_units::bigint)::text
         else null::text
    end as paid_minor_units,
    case when min(pc.org_reporting_currency) is null
           and count(distinct pc.currency) = 1
         then sum(pc.retention_held_minor_units::bigint)::text
         else null::text
    end as retention_held_minor_units,
    sum(pc.disputed_obligations) as disputed_obligations,
    sum(pc.overdue_obligations) as overdue_obligations,
    null::uuid as fx_rate_snapshot_id,
    null::date as fx_rate_date,
    case
      when min(pc.org_reporting_currency) is null then 'NO_REPORTING_CURRENCY'
      when count(*) filter (where pc.fx_status = 'NO_RATE_SNAPSHOT') > 0
        then 'CONSOLIDATION_INCOMPLETE_NO_RATE_SNAPSHOT'
      else 'CONSOLIDATED_AT_RATE'
    end as fx_status,
    case
      when min(pc.org_reporting_currency) is not null
       and count(*) filter (where pc.fx_status = 'NO_RATE_SNAPSHOT') = 0
      then sum(pc.converted_cash_minor)::text else null::text
    end as converted_cash_balance_minor_units,
    case
      when min(pc.org_reporting_currency) is not null
       and count(*) filter (where pc.fx_status = 'NO_RATE_SNAPSHOT') = 0
      then sum(pc.converted_receivable_minor)::text else null::text
    end as converted_receivable_open_minor_units,
    case
      when min(pc.org_reporting_currency) is not null
       and count(*) filter (where pc.fx_status = 'NO_RATE_SNAPSHOT') = 0
      then sum(pc.converted_revenue_minor)::text else null::text
    end as converted_revenue_recognized_minor_units,
    case
      when min(pc.org_reporting_currency) is not null
       and count(*) filter (where pc.fx_status = 'NO_RATE_SNAPSHOT') = 0
      then sum(pc.converted_cost_of_sale_minor)::text else null::text
    end as converted_cost_of_sale_minor_units,
    case
      when min(pc.org_reporting_currency) is not null
       and count(*) filter (where pc.fx_status = 'NO_RATE_SNAPSHOT') = 0
      then sum(pc.converted_expense_minor)::text else null::text
    end as converted_expense_posted_minor_units,
    case
      when min(pc.org_reporting_currency) is not null
       and count(*) filter (where pc.fx_status = 'NO_RATE_SNAPSHOT') = 0
      then sum(pc.converted_wip_minor)::text else null::text
    end as converted_wip_posted_minor_units,
    case
      when min(pc.org_reporting_currency) is not null
       and count(*) filter (where pc.fx_status = 'NO_RATE_SNAPSHOT') = 0
      then sum(pc.converted_contributions_minor)::text else null::text
    end as converted_contributions_received_minor_units,
    case
      when min(pc.org_reporting_currency) is not null
       and count(*) filter (where pc.fx_status = 'NO_RATE_SNAPSHOT') = 0
      then sum(pc.converted_payable_minor)::text else null::text
    end as converted_payable_open_minor_units,
    case
      when min(pc.org_reporting_currency) is not null
       and count(*) filter (where pc.fx_status = 'NO_RATE_SNAPSHOT') = 0
      then sum(pc.converted_paid_minor)::text else null::text
    end as converted_paid_minor_units,
    case
      when min(pc.org_reporting_currency) is not null
       and count(*) filter (where pc.fx_status = 'NO_RATE_SNAPSHOT') = 0
      then sum(pc.converted_retention_minor)::text else null::text
    end as converted_retention_held_minor_units
  from project_converted pc
  group by pc.organization_id
)
select organization_id, 'BY_CURRENCY'::text as level, currency, org_reporting_currency,
       project_count, cash_balance_minor_units, receivable_open_minor_units,
       revenue_recognized_minor_units, cost_of_sale_minor_units,
       expense_posted_minor_units, wip_posted_minor_units,
       contributions_received_minor_units, payable_open_minor_units,
       paid_minor_units, retention_held_minor_units,
       disputed_obligations, overdue_obligations,
       fx_rate_snapshot_id, fx_rate_date, fx_status,
       converted_cash_balance_minor_units, converted_receivable_open_minor_units,
       converted_revenue_recognized_minor_units, converted_cost_of_sale_minor_units,
       converted_expense_posted_minor_units, converted_wip_posted_minor_units,
       converted_contributions_received_minor_units, converted_payable_open_minor_units,
       converted_paid_minor_units, converted_retention_held_minor_units
from per_currency
union all
select organization_id, 'CONSOLIDATED'::text as level,
       org_reporting_currency as currency,
       org_reporting_currency,
       project_count, cash_balance_minor_units, receivable_open_minor_units,
       revenue_recognized_minor_units, cost_of_sale_minor_units,
       expense_posted_minor_units, wip_posted_minor_units,
       contributions_received_minor_units, payable_open_minor_units,
       paid_minor_units, retention_held_minor_units,
       disputed_obligations, overdue_obligations,
       fx_rate_snapshot_id, fx_rate_date, fx_status,
       converted_cash_balance_minor_units, converted_receivable_open_minor_units,
       converted_revenue_recognized_minor_units, converted_cost_of_sale_minor_units,
       converted_expense_posted_minor_units, converted_wip_posted_minor_units,
       converted_contributions_received_minor_units, converted_payable_open_minor_units,
       converted_paid_minor_units, converted_retention_held_minor_units
from consolidated;

grant select on public.portfolio_financial_rollup_read,
  public.organization_financial_consolidation_read to authenticated;
