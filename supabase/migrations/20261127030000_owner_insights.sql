-- ===========================================================================
-- Owner insights (invention stream E). Org-level, read-only read views that
-- power the owner weekly summary, the plain-Arabic "ask your numbers" panel
-- and bank-statement line suggestions. Additive only: no table changes, no
-- writes, no changes to existing objects.
-- ===========================================================================

-- 1. Weekly cash movement per organization and currency.
--    Money in = debits to BANK_CASH lines; money out = credits (cash balance
--    is debit - credit, see project_cash_position_read). Reversal-aware: a
--    reversed batch and its reversal are both excluded so an economic effect
--    and its correction never both count.
create or replace view public.owner_weekly_cash_read with (security_invoker=on) as
select
  jl.organization_id,
  date_trunc('week', jl.transaction_date)::date as week_start,
  jl.currency,
  coalesce(sum(jl.debit_minor_units), 0)::text as in_minor_units,
  coalesce(sum(jl.credit_minor_units), 0)::text as out_minor_units
from public.journal_lines jl
join public.journal_batches jb on jb.id = jl.batch_id
join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'BANK_CASH'
where jb.reversal_of_batch_id is null
  and not exists (
    select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
  )
group by jl.organization_id, date_trunc('week', jl.transaction_date)::date, jl.currency;

-- 2. Overdue authorized obligations: outstanding balance past its due date.
--    Days overdue are computed against the current date at read time.
create or replace view public.owner_overdue_obligations_read with (security_invoker=on) as
select
  organization_id,
  project_id,
  obligation_id,
  description,
  currency,
  outstanding_minor_units,
  transaction_date as due_date,
  (current_date - transaction_date) as days_overdue
from public.cost_obligation_position_read
where status = 'AUTHORIZED'
  and not is_reversed
  and outstanding_minor_units::bigint > 0
  and transaction_date < current_date;

-- 3. Suggestions for unreconciled bank statement lines.
--    Money out (negative amount) is matched to the oldest open authorized
--    obligation with the exact same outstanding amount and currency; money
--    in is flagged for recording. Suggestions are advisory only: confirming
--    any of them still goes through the existing payment/collection flows.
create or replace view public.owner_bank_line_suggestions_read with (security_invoker=on) as
select
  l.line_id,
  l.organization_id,
  l.project_id,
  l.cash_account_id,
  l.transaction_date,
  l.amount_minor_units,
  l.currency,
  l.description,
  case
    when l.amount_minor_units::bigint < 0 and o.obligation_id is not null then 'PAY_OBLIGATION'
    when l.amount_minor_units::bigint < 0 then 'RECORD_OUTFLOW'
    else 'RECORD_INFLOW'
  end as suggestion_kind,
  o.obligation_id as suggested_obligation_id,
  o.description as suggested_obligation_description
from public.bank_statement_line_status_read l
left join lateral (
  select op.obligation_id, op.description
  from public.cost_obligation_position_read op
  where op.organization_id = l.organization_id
    and op.project_id = l.project_id
    and op.currency = l.currency
    and op.status = 'AUTHORIZED'
    and not op.is_reversed
    and op.outstanding_minor_units::bigint = -l.amount_minor_units::bigint
  order by op.transaction_date asc, op.obligation_id
  limit 1
) o on true
where not l.is_reconciled;

grant select on public.owner_weekly_cash_read,
  public.owner_overdue_obligations_read,
  public.owner_bank_line_suggestions_read to authenticated;
