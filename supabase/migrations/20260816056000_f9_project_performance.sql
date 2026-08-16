-- F9 — Project Performance.
--
-- The authoritative per-project financial position, built only from posted
-- journal facts, plus the management performance view that joins position,
-- budget consumption (F4), contract finance state (F3) and aging.
--
-- Canonical separations are preserved:
--   * Cash / Receivable / Revenue / Expense / WIP / Payable / Paid /
--     Retention are separate columns; there is no ambiguous "profit".
--   * Every number is derived from the immutable journal (reversals
--     excluded) or from the F3/F4 authoritative registers.
--   * Budget vs Commitment vs Actual are three different facts.
--   * Money is text (bigint) so PostgREST/JavaScript cannot round it.

create or replace view public.project_financial_position_read with (security_invoker=on) as
with active_postings as (
  select jl.organization_id, jl.project_id, jl.account_id, sa.role,
         jl.debit_minor_units, jl.credit_minor_units, jl.currency
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa on sa.id = jl.account_id
  where not exists (
    select 1 from public.journal_batches rb
    where rb.reversal_of_batch_id = jb.id
  )
),
by_role as (
  select organization_id, project_id, currency, role,
         sum(debit_minor_units) as debits,
         sum(credit_minor_units) as credits
  from active_postings
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
      as contributions_received_minor_units
  from by_role
  group by organization_id, project_id, currency
),
payable as (
  select organization_id, project_id, currency,
    sum(outstanding_minor_units::bigint) as payable_open_minor_units,
    sum(paid_minor_units::bigint) as paid_minor_units,
    sum(retention_remaining_minor_units::bigint) as retention_held_minor_units,
    sum(retention_minor_units::bigint) as retention_declared_minor_units,
    count(*) filter (where is_disputed) as disputed_obligations,
    count(*) filter (where aging_bucket like 'OVERDUE%'
                          and outstanding_minor_units::bigint > 0)
      as overdue_obligations,
    sum(case when aging_bucket like 'OVERDUE%'
        then outstanding_minor_units::bigint else 0 end) as overdue_outstanding_minor_units
  from public.cost_obligation_due_read
  where status = 'AUTHORIZED' and is_reversed = false
  group by organization_id, project_id, currency
),
budget as (
  select organization_id, project_id, currency,
    sum(budget_minor_units::bigint) filter (where cost_treatment = 'EXPENSE')
      as budget_expense_minor_units,
    sum(budget_minor_units::bigint) filter (where cost_treatment = 'CAPITALIZABLE_WIP')
      as budget_wip_minor_units,
    sum(committed_obligations_minor_units::bigint) filter (where cost_treatment = 'EXPENSE')
      as committed_expense_minor_units,
    sum(committed_obligations_minor_units::bigint) filter (where cost_treatment = 'CAPITALIZABLE_WIP')
      as committed_wip_minor_units,
    sum(effective_remaining_minor_units::bigint) filter (where cost_treatment = 'EXPENSE')
      as available_expense_minor_units,
    sum(effective_remaining_minor_units::bigint) filter (where cost_treatment = 'CAPITALIZABLE_WIP')
      as available_wip_minor_units
  from public.project_budget_consumption_read
  group by organization_id, project_id, currency
)
select
  p.id as project_id,
  p.organization_id,
  p.name as project_name,
  p.sector,
  p.reporting_currency as currency,
  coalesce(pos.cash_balance_minor_units, 0)::text as cash_balance_minor_units,
  coalesce(pos.receivable_open_minor_units, 0)::text as receivable_open_minor_units,
  coalesce(pos.revenue_recognized_minor_units, 0)::text as revenue_recognized_minor_units,
  coalesce(pos.cost_of_sale_minor_units, 0)::text as cost_of_sale_minor_units,
  coalesce(pos.expense_posted_minor_units, 0)::text as expense_posted_minor_units,
  coalesce(pos.wip_posted_minor_units, 0)::text as wip_posted_minor_units,
  coalesce(pos.contributions_received_minor_units, 0)::text as contributions_received_minor_units,
  coalesce(py.payable_open_minor_units, 0)::text as payable_open_minor_units,
  coalesce(py.paid_minor_units, 0)::text as paid_minor_units,
  coalesce(py.retention_held_minor_units, 0)::text as retention_held_minor_units,
  coalesce(py.retention_declared_minor_units, 0)::text as retention_declared_minor_units,
  coalesce(py.disputed_obligations, 0) as disputed_obligations,
  coalesce(py.overdue_obligations, 0) as overdue_obligations,
  coalesce(py.overdue_outstanding_minor_units, 0)::text as overdue_outstanding_minor_units
from public.investment_projects p
left join positions pos
  on pos.project_id = p.id
 and pos.currency = p.reporting_currency
left join payable py
  on py.project_id = p.id
 and py.currency = p.reporting_currency
left join budget bg
  on bg.project_id = p.id
 and bg.currency = p.reporting_currency
where true
  and (pos.project_id is not null or py.project_id is not null
       or bg.project_id is not null
       or exists (select 1 from public.cost_obligations o where o.project_id = p.id)
       or exists (select 1 from public.project_budgets b
                  where b.project_id = p.id and b.status = 'APPROVED'));

-- Management performance view: position + budget vs commitment vs actual +
-- contract finance state, one row per project/currency.
create or replace view public.project_performance_read with (security_invoker=on) as
select
  f.*,
  coalesce(bg.budget_expense_minor_units, 0)::text as budget_expense_minor_units,
  coalesce(bg.budget_wip_minor_units, 0)::text as budget_wip_minor_units,
  coalesce(bg.committed_expense_minor_units, 0)::text as committed_expense_minor_units,
  coalesce(bg.committed_wip_minor_units, 0)::text as committed_wip_minor_units,
  coalesce(bg.available_expense_minor_units, 0)::text as available_expense_minor_units,
  coalesce(bg.available_wip_minor_units, 0)::text as available_wip_minor_units,
  coalesce(h.close_health, 'NO_PERIODS') as period_close_health
from public.project_financial_position_read f
left join (
  select organization_id, project_id, currency,
    sum(budget_minor_units::bigint) filter (where cost_treatment = 'EXPENSE')
      as budget_expense_minor_units,
    sum(budget_minor_units::bigint) filter (where cost_treatment = 'CAPITALIZABLE_WIP')
      as budget_wip_minor_units,
    sum(committed_obligations_minor_units::bigint) filter (where cost_treatment = 'EXPENSE')
      as committed_expense_minor_units,
    sum(committed_obligations_minor_units::bigint) filter (where cost_treatment = 'CAPITALIZABLE_WIP')
      as committed_wip_minor_units,
    sum(effective_remaining_minor_units::bigint) filter (where cost_treatment = 'EXPENSE')
      as available_expense_minor_units,
    sum(effective_remaining_minor_units::bigint) filter (where cost_treatment = 'CAPITALIZABLE_WIP')
      as available_wip_minor_units
  from public.project_budget_consumption_read
  group by organization_id, project_id, currency
) bg on bg.project_id = f.project_id and bg.currency = f.currency
left join (
  select distinct on (project_id, reporting_currency)
         project_id, reporting_currency, close_health
  from public.period_close_health_read
  order by project_id, reporting_currency, open_period_start desc nulls last
) h on h.project_id = f.project_id and h.reporting_currency = f.currency;

grant select on public.project_financial_position_read, public.project_performance_read
  to authenticated;
