-- F4 FAC + F10 scope completion.
--
-- F4 (canonical): Actual / Open Commitments / Approved Forecast Remainder
-- are three separated facts, and FAC = Actual + Open Commitments +
-- Approved Forecast Remainder. The previous single max() "forecast" was not
-- FAC and is removed.
--
-- F10 (canonical): the roll-up must carry commitments, actual, realized
-- result, forecast (FAC), concentration, sector exposure and
-- risks/exceptions, and historical Project->Portfolio attribution must be
-- driven by the append-only assignment history, not by current membership.

-- ===========================================================================
-- 1. F4 — treatment-level actual in the consumption read model; the
--    honest FAC (budget level, commitments included) in a new read model
-- ===========================================================================
create or replace view public.project_budget_consumption_read with (security_invoker=on) as
select
  b.id as budget_id,
  b.organization_id,
  b.project_id,
  b.period_start,
  b.period_end,
  b.budget_type,
  b.version,
  b.status,
  b.currency,
  b.description,
  bl.id as budget_line_id,
  bl.cost_treatment,
  bl.amount_minor_units::text as budget_minor_units,
  coalesce(ob.obligations_minor_units, 0)::text as committed_obligations_minor_units,
  coalesce(pd.paid_minor_units, 0)::text as paid_minor_units,
  coalesce(exc.exception_minor_units, 0)::text as approved_exception_minor_units,
  (bl.amount_minor_units - coalesce(ob.obligations_minor_units, 0))::text
    as authorization_remaining_minor_units,
  (bl.amount_minor_units + coalesce(exc.exception_minor_units, 0)
    - coalesce(ob.obligations_minor_units, 0))::text as effective_remaining_minor_units,
  -- Corrected semantics: forecast_final is now the treatment-level FAC
  -- (actual + approved forecast remainder). The budget-level FAC that also
  -- includes open purchase commitments lives in project_budget_fac_read.
  (coalesce(act.actual_minor_units, 0)
    + greatest(0, bl.amount_minor_units + coalesce(exc.exception_minor_units, 0)
        - coalesce(act.actual_minor_units, 0)))::text as forecast_final_minor_units,
  coalesce(act.actual_minor_units, 0)::text as actual_minor_units,
  greatest(0, bl.amount_minor_units + coalesce(exc.exception_minor_units, 0)
    - coalesce(act.actual_minor_units, 0))::text as approved_forecast_remainder_minor_units,
  (coalesce(act.actual_minor_units, 0)
    + greatest(0, bl.amount_minor_units + coalesce(exc.exception_minor_units, 0)
        - coalesce(act.actual_minor_units, 0)))::text as fac_minor_units
from public.project_budgets b
join public.project_budget_lines bl on bl.budget_id = b.id
left join (
  select o.cost_treatment, sum(o.amount_minor_units) as obligations_minor_units,
         b2.id as budget_id
  from public.cost_obligations o
  join public.project_budgets b2
    on b2.project_id = o.project_id
   and o.transaction_date between b2.period_start and b2.period_end
  where b2.status = 'APPROVED'
    and o.status = 'AUTHORIZED'
    and o.currency = b2.currency
    and exists (
      select 1 from public.journal_batches jb
      where jb.source_type = 'COST_OBLIGATION' and jb.source_id = o.id
        and jb.reversal_of_batch_id is null
        and not exists (
          select 1 from public.journal_batches rb
          where rb.reversal_of_batch_id = jb.id
        )
    )
  group by o.cost_treatment, b2.id
) ob on ob.budget_id = b.id and ob.cost_treatment = bl.cost_treatment
left join (
  select o.cost_treatment, b2.id as budget_id,
         sum(jl.debit_minor_units) as paid_minor_units
  from public.journal_batches jb
  join public.project_payments pp on pp.id = jb.source_id
  join public.cost_obligations o on o.id = pp.obligation_id
  join public.project_budgets b2
    on b2.project_id = o.project_id
   and b2.status = 'APPROVED'
   and jb.transaction_date between b2.period_start and b2.period_end
  join public.journal_lines jl on jl.batch_id = jb.id
  join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'SUPPLIER_PAYABLE'
  where jb.source_type = 'PAYMENT'
    and jb.reversal_of_batch_id is null
    and jl.debit_minor_units > 0
    and not exists (
      select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
    )
  group by o.cost_treatment, b2.id
) pd on pd.budget_id = b.id and pd.cost_treatment = bl.cost_treatment
left join (
  select b2.id as budget_id, sa.role, jl.currency,
         sum(jl.debit_minor_units) - sum(jl.credit_minor_units) as actual_minor_units
  from public.journal_batches jb
  join public.journal_lines jl on jl.batch_id = jb.id
  join public.project_budgets b2
    on b2.project_id = jl.project_id
   and jl.transaction_date between b2.period_start and b2.period_end
  join public.semantic_accounts sa
    on sa.id = jl.account_id and sa.role in ('PROJECT_EXPENSE','DEVELOPMENT_WIP')
  where b2.status = 'APPROVED'
    and jb.reversal_of_batch_id is null
    and not exists (
      select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
    )
  group by b2.id, sa.role, jl.currency
) act_roles on act_roles.budget_id = b.id and act_roles.currency = b.currency
left join lateral (
  select act_roles.actual_minor_units as actual_minor_units
  where act_roles.role = case when bl.cost_treatment = 'EXPENSE'
    then 'PROJECT_EXPENSE' else 'DEVELOPMENT_WIP' end
) act on true
left join (
  select subject_id as budget_line_id, sum(amount_minor_units) as exception_minor_units
  from public.approval_exceptions
  where exception_domain = 'BUDGET_CEILING'
    and subject_type = 'project_budget_line'
    and status = 'APPROVED'
  group by subject_id
) exc on exc.budget_line_id = bl.id
where b.status = 'APPROVED';

-- FAC at budget level: Actual + Open Commitments + Approved Forecast
-- Remainder, each exposed as its own separated fact.
create or replace view public.project_budget_fac_read with (security_invoker=on) as
select
  b.id as budget_id,
  b.organization_id,
  b.project_id,
  b.period_start,
  b.period_end,
  b.budget_type,
  b.version,
  b.currency,
  b.description,
  coalesce(sum(c.budget_minor_units::bigint), 0)::text as budget_total_minor_units,
  coalesce(sum(c.approved_exception_minor_units::bigint), 0)::text
    as approved_exception_total_minor_units,
  coalesce(sum(c.actual_minor_units::bigint), 0)::text as actual_total_minor_units,
  coalesce(pc.open_commitment_minor_units, 0)::text as open_commitment_minor_units,
  greatest(0,
    coalesce(sum(c.budget_minor_units::bigint), 0)
    + coalesce(sum(c.approved_exception_minor_units::bigint), 0)
    - coalesce(sum(c.actual_minor_units::bigint), 0)
    - coalesce(pc.open_commitment_minor_units, 0))::text
    as approved_forecast_remainder_minor_units,
  (coalesce(sum(c.actual_minor_units::bigint), 0)
    + coalesce(pc.open_commitment_minor_units, 0)
    + greatest(0,
        coalesce(sum(c.budget_minor_units::bigint), 0)
        + coalesce(sum(c.approved_exception_minor_units::bigint), 0)
        - coalesce(sum(c.actual_minor_units::bigint), 0)
        - coalesce(pc.open_commitment_minor_units, 0)))::text
    as fac_minor_units
from public.project_budgets b
join public.project_budget_consumption_read c on c.budget_id = b.id
left join (
  select b2.id as budget_id,
         coalesce(sum(pco.remaining_commitment_minor_units::bigint), 0)
           as open_commitment_minor_units
  from public.project_budgets b2
  left join public.project_procurement_commitments_read pco
    on pco.project_id = b2.project_id
   and pco.currency = b2.currency
   and pco.committed_at::date between b2.period_start and b2.period_end
  where b2.status = 'APPROVED'
  group by b2.id
) pc on pc.budget_id = b.id
where b.status = 'APPROVED'
group by b.id, b.organization_id, b.project_id, b.period_start, b.period_end,
         b.budget_type, b.version, b.currency, b.description,
         pc.open_commitment_minor_units;

-- ===========================================================================
-- 2. F10 — current roll-up with commitments, realized result, FAC,
--    concentration, sector exposure and open exceptions
-- ===========================================================================
create or replace view public.portfolio_financial_rollup_read with (security_invoker=on) as
with project_converted as (
  select
    pp.*,
    pp.sector as project_sector,
    o.reporting_currency as org_reporting_currency,
    s.id as fx_rate_snapshot_id,
    s.rate_date as fx_rate_date,
    case
      when o.reporting_currency is null then 'NO_REPORTING_CURRENCY'
      when o.reporting_currency = pp.currency then 'SAME_CURRENCY'
      when s.id is null then 'NO_RATE_SNAPSHOT'
      else 'CONVERTED_AT_RATE'
    end as fx_status,
    coalesce(pc2.open_commitment_minor_units, 0) as open_commitment_minor_units,
    coalesce(fac.fac_minor_units, 0) as fac_minor_units,
    coalesce(exc.open_exception_count, 0) as open_exception_count,
    (pp.revenue_recognized_minor_units::bigint
      - pp.cost_of_sale_minor_units::bigint) as realized_result_minor_units,
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
  left join (
    select project_id, currency,
           sum(remaining_commitment_minor_units::bigint) as open_commitment_minor_units
    from public.project_procurement_commitments_read
    group by project_id, currency
  ) pc2 on pc2.project_id = pp.project_id and pc2.currency = pp.currency
  left join (
    select project_id, currency, sum(fac_minor_units::bigint) as fac_minor_units
    from public.project_budget_fac_read
    group by project_id, currency
  ) fac on fac.project_id = pp.project_id and fac.currency = pp.currency
  left join (
    select project_id, count(*) as open_exception_count
    from public.approval_exceptions
    where status = 'OPEN'
    group by project_id
  ) exc on exc.project_id = pp.project_id
),
sector_stats as (
  select pc.project_id, pc.currency, pc.project_sector,
         count(*) as sector_project_count,
         sum(pc.cash_balance_minor_units::bigint) as sector_cash_minor_units
  from project_converted pc
  group by pc.project_id, pc.currency, pc.project_sector
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
  sum(pc.converted_retention_minor)::text as converted_retention_held_minor_units,
  sum(pc.open_commitment_minor_units)::text as open_commitment_minor_units,
  sum(pc.realized_result_minor_units)::text as realized_result_minor_units,
  sum(pc.fac_minor_units)::text as fac_minor_units,
  sum(pc.open_exception_count) as open_exception_count,
  jsonb_object_agg(
    ss.project_sector,
    jsonb_build_object(
      'project_count', ss.sector_project_count,
      'cash_balance_minor_units', ss.sector_cash_minor_units::text
    )
  ) as sector_exposure,
  (case when sum(pc.cash_balance_minor_units::bigint) > 0 then
     round((max(pc.cash_balance_minor_units::bigint)::numeric
       / sum(pc.cash_balance_minor_units::bigint)::numeric) * 100, 2)::text || '%'
   else null end) as cash_concentration_ratio
from public.investment_portfolios pf
join public.portfolio_project_assignments a
  on a.portfolio_id = pf.id and a.removed_at is null
join project_converted pc on pc.project_id = a.investment_project_id
join sector_stats ss on ss.project_id = pc.project_id and ss.currency = pc.currency
group by pf.id, pf.organization_id, pf.name, pf.status,
         pc.currency, pc.org_reporting_currency;

-- ===========================================================================
-- 3. F10 — historical roll-up driven by the append-only assignment history.
--    Membership: assigned_at <= asof and (removed_at is null or
--    removed_at > asof). All financial facts are filtered to the as-of
--    date; reversals net to zero.
-- ===========================================================================
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
language sql
stable
security definer
set search_path=pg_catalog,public
as $$
with member_projects as (
  select a.investment_project_id as project_id
  from public.portfolio_project_assignments a
  where a.portfolio_id = p_portfolio_id
    and a.organization_id = p_organization_id
    and a.assigned_at::date <= p_asof_date
    and (a.removed_at is null or a.removed_at::date > p_asof_date)
),
asof_lines as (
  select jl.organization_id, jl.project_id, jl.account_id, sa.role,
         jl.debit_minor_units, jl.credit_minor_units, jl.currency
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa on sa.id = jl.account_id
  where jb.reversal_of_batch_id is null
    and jl.transaction_date <= p_asof_date
    and not exists (
      select 1 from public.journal_batches rb
      where rb.reversal_of_batch_id = jb.id
    )
),
by_role as (
  select organization_id, project_id, currency, role,
         sum(debit_minor_units) as debits,
         sum(credit_minor_units) as credits
  from asof_lines
  group by organization_id, project_id, currency, role
),
positions as (
  select organization_id, project_id, currency,
    coalesce(sum(case when role = 'BANK_CASH' then debits - credits else 0 end), 0)
      as cash_balance_minor_units,
    coalesce(sum(case when role = 'CUSTOMER_RECEIVABLE' then debits - credits else 0 end), 0)
      as receivable_open_minor_units,
    coalesce(sum(case when role in (
      'REAL_ESTATE_SALE_REVENUE','AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE'
    ) then credits - debits else 0 end), 0) as revenue_recognized_minor_units,
    coalesce(sum(case when role = 'REAL_ESTATE_COST_OF_SALE' then debits - credits else 0 end), 0)
      as cost_of_sale_minor_units,
    coalesce(sum(case when role = 'PROJECT_EXPENSE' then debits - credits else 0 end), 0)
      as expense_posted_minor_units,
    coalesce(sum(case when role = 'DEVELOPMENT_WIP' then debits - credits else 0 end), 0)
      as wip_posted_minor_units,
    coalesce(sum(case when role = 'CONTRIBUTED_CAPITAL' then credits - debits else 0 end), 0)
      as contributions_received_minor_units,
    coalesce(sum(case when role = 'SUPPLIER_PAYABLE' then credits - debits else 0 end), 0)
      as payable_open_minor_units,
    coalesce(sum(case when role = 'SUPPLIER_PAYABLE' then debits else 0 end), 0)
      as paid_minor_units
  from by_role
  group by organization_id, project_id, currency
),
projects_asof as (
  select
    p.id as project_id,
    p.organization_id,
    p.name as project_name,
    p.sector,
    p.reporting_currency as currency,
    coalesce(pos.cash_balance_minor_units, 0) as cash_balance_minor_units,
    coalesce(pos.receivable_open_minor_units, 0) as receivable_open_minor_units,
    coalesce(pos.revenue_recognized_minor_units, 0) as revenue_recognized_minor_units,
    coalesce(pos.cost_of_sale_minor_units, 0) as cost_of_sale_minor_units,
    coalesce(pos.expense_posted_minor_units, 0) as expense_posted_minor_units,
    coalesce(pos.wip_posted_minor_units, 0) as wip_posted_minor_units,
    coalesce(pos.contributions_received_minor_units, 0) as contributions_received_minor_units,
    coalesce(pos.payable_open_minor_units, 0) as payable_open_minor_units,
    coalesce(pos.paid_minor_units, 0) as paid_minor_units,
    coalesce(ret.retention_minor_units, 0) as retention_held_minor_units,
    coalesce(dis.disputed, 0) as disputed_obligations,
    coalesce(due.overdue, 0) as overdue_obligations,
    coalesce(pc.open_commitment_minor_units, 0) as open_commitment_minor_units,
    (pos.revenue_recognized_minor_units - pos.cost_of_sale_minor_units)
      as realized_result_minor_units,
    coalesce(fac.fac_minor_units, 0) as fac_minor_units,
    coalesce(exc.open_exception_count, 0) as open_exception_count,
    o.reporting_currency as org_reporting_currency,
    s.id as fx_rate_snapshot_id,
    case
      when o.reporting_currency is null then 'NO_REPORTING_CURRENCY'
      when o.reporting_currency = p.reporting_currency then 'SAME_CURRENCY'
      when s.id is null then 'NO_RATE_SNAPSHOT'
      else 'CONVERTED_AT_RATE'
    end as fx_status,
    case
      when o.reporting_currency = p.reporting_currency then pos.cash_balance_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pos.cash_balance_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_cash_minor
  from public.investment_projects p
  join member_projects mp on mp.project_id = p.id
  join public.organizations o on o.id = p.organization_id
  left join positions pos
    on pos.project_id = p.id and pos.currency = p.reporting_currency
  left join lateral (
    select s2.* from public.fx_rate_snapshots s2
    where s2.organization_id = p.organization_id
      and s2.base_currency = p.reporting_currency
      and s2.quote_currency = o.reporting_currency
      and s2.rate_date <= p_asof_date
    order by s2.rate_date desc
    limit 1
  ) s on true
  left join (
    select t.organization_id, o2.project_id,
           sum(t.retention_minor_units) as retention_minor_units
    from public.cost_obligation_terms t
    join public.cost_obligations o2 on o2.id = t.obligation_id
    where o2.status = 'AUTHORIZED'
      and o2.transaction_date <= p_asof_date
      and t.created_at::date <= p_asof_date
    group by t.organization_id, o2.project_id
  ) ret_decl on ret_decl.project_id = p.id
  left join (
    select r.organization_id, o2.project_id,
           sum(r.amount_minor_units) as released_minor_units
    from public.cost_obligation_retention_releases r
    join public.cost_obligations o2 on o2.id = r.obligation_id
    where r.release_date <= p_asof_date
    group by r.organization_id, o2.project_id
  ) ret_rel on ret_rel.project_id = p.id
  left join lateral (
    select greatest(0, ret_decl.retention_minor_units
      - coalesce(ret_rel.released_minor_units, 0)) as retention_minor_units,
      ret_rel.released_minor_units
  ) ret on true
  left join (
    select d.organization_id, o2.project_id, count(distinct o2.id) as disputed
    from public.cost_obligation_disputes d
    join public.cost_obligations o2 on o2.id = d.obligation_id
    where d.opened_at::date <= p_asof_date
      and (d.status = 'OPEN' or d.resolved_at::date > p_asof_date)
    group by d.organization_id, o2.project_id
  ) dis on dis.project_id = p.id
  left join (
    select o2.project_id, count(*) as overdue
    from public.cost_obligations o2
    join public.cost_obligation_terms t on t.obligation_id = o2.id
    where o2.status = 'AUTHORIZED'
      and o2.transaction_date <= p_asof_date
      and (
        (t.terms_type = 'FIXED_DATE' and t.due_date < p_asof_date)
        or (t.terms_type = 'NET_DAYS'
            and o2.transaction_date + t.net_days < p_asof_date)
        or (t.terms_type = 'MILESTONE_SCHEDULE'
            and exists (
              select 1 from public.cost_obligation_schedule_lines s3
              where s3.obligation_id = o2.id
                and s3.is_retention_line = false
                and s3.due_date < p_asof_date
            ))
      )
      and o2.amount_minor_units > coalesce((
        select sum(pp2.amount_minor_units)
        from public.project_payments pp2
        join public.journal_batches jb2
          on jb2.source_type = 'PAYMENT' and jb2.source_id = pp2.id
        where pp2.obligation_id = o2.id
          and jb2.transaction_date <= p_asof_date
          and jb2.reversal_of_batch_id is null
          and not exists (
            select 1 from public.journal_batches rb2
            where rb2.reversal_of_batch_id = jb2.id
          )
      ), 0)
    group by o2.project_id
  ) due on due.project_id = p.id
  left join (
    select po.project_id, po.currency,
           sum(po.committed_minor_units::bigint) as committed_minor_units
    from (
      select o3.id, o3.project_id, o3.currency,
             sum(ol.line_amount_minor_units) as committed_minor_units
      from public.purchase_orders o3
      join public.purchase_order_lines ol on ol.purchase_order_id = o3.id
      where o3.status = 'APPROVED'
        and o3.approved_at::date <= p_asof_date
      group by o3.id, o3.project_id, o3.currency
    ) po
    group by po.project_id, po.currency
  ) po_tot on po_tot.project_id = p.id and po_tot.currency = p.reporting_currency
  left join (
    select i.project_id, i.currency,
           sum(il.line_amount_minor_units) as invoiced_minor_units
    from public.supplier_invoices i
    join public.supplier_invoice_lines il on il.supplier_invoice_id = i.id
    where i.status = 'APPROVED'
      and i.invoice_date <= p_asof_date
    group by i.project_id, i.currency
  ) inv_tot on inv_tot.project_id = p.id and inv_tot.currency = p.reporting_currency
  left join lateral (
    select greatest(0, po_tot.committed_minor_units
      - coalesce(inv_tot.invoiced_minor_units, 0)) as open_commitment_minor_units
  ) pc on true
  left join (
    select f.project_id, f.currency, sum(f.fac_minor_units::bigint) as fac_minor_units
    from public.project_budget_fac_read f
    where f.period_start <= p_asof_date and f.period_end >= p_asof_date
    group by f.project_id, f.currency
  ) fac on fac.project_id = p.id and fac.currency = p.reporting_currency
  left join (
    select e.project_id, count(*) as open_exception_count
    from public.approval_exceptions e
    where e.opened_at::date <= p_asof_date
      and (e.status = 'OPEN' or e.decided_at::date > p_asof_date)
    group by e.project_id
  ) exc on exc.project_id = p.id
),
sector_stats2 as (
  select pa.currency, pa.sector,
         count(*) as sector_project_count,
         sum(pa.cash_balance_minor_units) as sector_cash_minor_units
  from projects_asof pa
  group by pa.currency, pa.sector
)
select
  p_portfolio_id as portfolio_id,
  pa.organization_id,
  pf2.name as portfolio_name,
  pa.currency,
  pa.org_reporting_currency,
  count(pa.project_id) as project_count,
  sum(pa.cash_balance_minor_units)::text as cash_balance_minor_units,
  sum(pa.receivable_open_minor_units)::text as receivable_open_minor_units,
  sum(pa.revenue_recognized_minor_units)::text as revenue_recognized_minor_units,
  sum(pa.cost_of_sale_minor_units)::text as cost_of_sale_minor_units,
  sum(pa.expense_posted_minor_units)::text as expense_posted_minor_units,
  sum(pa.wip_posted_minor_units)::text as wip_posted_minor_units,
  sum(pa.contributions_received_minor_units)::text as contributions_received_minor_units,
  sum(pa.payable_open_minor_units)::text as payable_open_minor_units,
  sum(pa.paid_minor_units)::text as paid_minor_units,
  sum(pa.retention_held_minor_units)::text as retention_held_minor_units,
  sum(pa.disputed_obligations) as disputed_obligations,
  sum(pa.overdue_obligations) as overdue_obligations,
  sum(pa.open_commitment_minor_units)::text as open_commitment_minor_units,
  sum(pa.realized_result_minor_units)::text as realized_result_minor_units,
  sum(pa.fac_minor_units)::text as fac_minor_units,
  sum(pa.open_exception_count) as open_exception_count,
  min(pa.fx_status) as fx_status,
  sum(pa.converted_cash_minor)::text as converted_cash_balance_minor_units,
  jsonb_object_agg(
    ss2.sector,
    jsonb_build_object(
      'project_count', ss2.sector_project_count,
      'cash_balance_minor_units', ss2.sector_cash_minor_units::text
    )
  ) filter (where ss2.sector is not null) as sector_exposure,
  (case when sum(pa.cash_balance_minor_units) > 0 then
     round((max(pa.cash_balance_minor_units)::numeric
       / sum(pa.cash_balance_minor_units)::numeric) * 100, 2)::text || '%'
   else null end) as cash_concentration_ratio
from public.investment_portfolios pf2
left join projects_asof pa
  on pa.organization_id = pf2.organization_id
left join sector_stats2 ss2
  on ss2.currency = pa.currency and ss2.sector = pa.sector
where pf2.id = p_portfolio_id and pf2.organization_id = p_organization_id
group by pa.organization_id, pf2.name, pa.currency, pa.org_reporting_currency;
$$;

grant select on public.project_budget_fac_read to authenticated;
revoke all on function public.portfolio_financial_rollup_asof(uuid,uuid,date) from public, anon;
grant execute on function public.portfolio_financial_rollup_asof(uuid,uuid,date) to authenticated;
