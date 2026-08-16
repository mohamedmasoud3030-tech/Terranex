-- F3–F10 final audit hardening: internal approval authority, tenant-safe
-- historical portfolio roll-up, signed FX balances, and complete correction
-- in-flight visibility.
--
-- This is forward-only. It intentionally does not rewrite the earlier review
-- migrations so historical replay remains deterministic.

-- ===========================================================================
-- 1. F5 approval helpers are implementation details, never public RPCs.
--    The material command RPCs call them while running as the function owner.
-- ===========================================================================
revoke all on function public.f5_approval_required(uuid,text,bigint,text)
  from public, anon, authenticated;
revoke all on function public.f5_signoffs_count(uuid,text,uuid)
  from public, anon, authenticated;
revoke all on function public.f5_has_signed(uuid,text,uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.f5_record_signoff(uuid,text,bigint,text,text,uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.f5_approval_complete(uuid,text,bigint,text,text,uuid)
  from public, anon, authenticated;

-- ===========================================================================
-- 2. F10 historical roll-up: preserve the proven implementation, but make it
--    unreachable directly. The public wrapper authorizes the caller and
--    validates org/portfolio scope before any SECURITY DEFINER read occurs.
-- ===========================================================================
alter function public.portfolio_financial_rollup_asof(uuid,uuid,date)
  rename to portfolio_financial_rollup_asof_impl;
revoke all on function public.portfolio_financial_rollup_asof_impl(uuid,uuid,date)
  from public, anon, authenticated;

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
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if p_asof_date is null then
    raise exception 'as-of date required';
  end if;
  if not public.is_active_member(p_organization_id) then
    raise exception 'forbidden';
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

-- ===========================================================================
-- 3. F6/F10 exact FX conversion must support signed accounting balances.
--    Conversion-entry commands still enforce positive source amounts; this
--    primitive also serves read models whose legitimate balances can be < 0.
--    Numeric intermediates avoid bigint multiplication/ABS overflow.
-- ===========================================================================
create or replace function public.fx_convert_exact(
  p_amount_minor_units bigint,
  p_rate_numerator bigint,
  p_rate_denominator bigint
) returns bigint
language plpgsql
immutable
set search_path=pg_catalog,public
as $$
declare
  v_abs numeric;
  v_rounded numeric;
begin
  if p_amount_minor_units is null then
    raise exception 'conversion amount required';
  end if;
  if p_rate_numerator is null or p_rate_numerator <= 0
     or p_rate_denominator is null or p_rate_denominator <= 0 then
    raise exception 'conversion rate must be a positive rational';
  end if;
  if p_amount_minor_units = 0 then
    return 0;
  end if;

  v_abs := abs(p_amount_minor_units::numeric);
  v_rounded := trunc(
    (v_abs * p_rate_numerator::numeric
      + trunc(p_rate_denominator::numeric / 2))
    / p_rate_denominator::numeric
  );
  if p_amount_minor_units < 0 then
    v_rounded := -v_rounded;
  end if;

  if v_rounded < '-9223372036854775808'::numeric
     or v_rounded > '9223372036854775807'::numeric then
    raise exception 'converted amount out of bigint range';
  end if;
  return v_rounded::bigint;
end $$;

-- ===========================================================================
-- 4. F7 close health: APPROVED correction requests remain in-flight until
--    EXECUTED. A request stops being a close-health concern only after it is
--    REJECTED or EXECUTED.
-- ===========================================================================
create or replace view public.period_close_health_read with (security_invoker=on) as
with scope as (
  select distinct organization_id, project_id, reporting_currency
  from public.accounting_periods
),
open_period as (
  select organization_id, project_id, reporting_currency,
         id as open_period_id, start_date as open_period_start,
         end_date as open_period_end, version as open_period_version
  from public.accounting_periods
  where status = 'OPEN'
),
latest_closed as (
  select distinct on (organization_id, project_id, reporting_currency)
         organization_id, project_id, reporting_currency,
         id as last_closed_period_id, closed_at as last_closed_at,
         closed_by as last_closed_by, version as last_closed_version
  from public.accounting_periods
  where status = 'CLOSED'
  order by organization_id, project_id, reporting_currency, closed_at desc
),
in_flight as (
  select cr.organization_id, cr.project_id,
         count(*) filter (where cr.status = 'PREPARED') as open_close_runs,
         count(*) filter (where cr.status = 'APPROVED') as approved_close_runs
  from public.close_runs cr
  group by cr.organization_id, cr.project_id
),
open_exceptions as (
  select e.organization_id, cr.project_id, count(*) as open_close_exceptions
  from public.close_run_exceptions e
  join public.close_runs cr on cr.id = e.close_run_id
  where e.status = 'PENDING'
  group by e.organization_id, cr.project_id
),
open_corrections as (
  select organization_id, project_id, count(*) as open_correction_requests
  from public.correction_requests
  where status in ('REQUESTED','APPROVED')
  group by organization_id, project_id
),
contract_state as (
  select d.organization_id, d.project_id,
         count(distinct case when d.is_disputed then d.obligation_id end)
           as open_disputes,
         count(distinct case when d.payment_blocked then d.obligation_id end)
           as payment_blocked_obligations,
         count(distinct case when d.status = 'AUTHORIZED'
            and d.aging_bucket like 'OVERDUE%'
            and d.outstanding_minor_units::bigint > 0 then d.obligation_id end)
           as overdue_obligations
  from public.cost_obligation_due_read d
  group by d.organization_id, d.project_id
)
select
  s.organization_id,
  s.project_id,
  s.reporting_currency,
  op.open_period_id,
  op.open_period_start,
  op.open_period_end,
  op.open_period_version,
  lc.last_closed_period_id,
  lc.last_closed_at,
  lc.last_closed_by,
  lc.last_closed_version,
  coalesce(inf.open_close_runs, 0) as open_close_runs,
  coalesce(inf.approved_close_runs, 0) as approved_close_runs,
  coalesce(oe.open_close_exceptions, 0) as open_close_exceptions,
  coalesce(oc.open_correction_requests, 0) as open_correction_requests,
  coalesce(cs.open_disputes, 0) as open_disputes,
  coalesce(cs.payment_blocked_obligations, 0) as payment_blocked_obligations,
  coalesce(cs.overdue_obligations, 0) as overdue_obligations,
  case
    when op.open_period_id is null then 'NO_OPEN_PERIOD'
    when coalesce(inf.open_close_runs, 0) > 0 then 'CLOSE_RUN_IN_FLIGHT'
    when coalesce(oc.open_correction_requests, 0) > 0 then 'CORRECTION_IN_FLIGHT'
    when coalesce(cs.overdue_obligations, 0) > 0 then 'OVERDUE_OBLIGATIONS'
    when coalesce(cs.open_disputes, 0) > 0 then 'OPEN_DISPUTES'
    else 'CLEAN'
  end as close_health
from scope s
left join open_period op
  on op.organization_id = s.organization_id and op.project_id = s.project_id
 and op.reporting_currency = s.reporting_currency
left join latest_closed lc
  on lc.organization_id = s.organization_id and lc.project_id = s.project_id
 and lc.reporting_currency = s.reporting_currency
left join in_flight inf
  on inf.organization_id = s.organization_id and inf.project_id = s.project_id
left join open_exceptions oe
  on oe.organization_id = s.organization_id and oe.project_id = s.project_id
left join open_corrections oc
  on oc.organization_id = s.organization_id and oc.project_id = s.project_id
left join contract_state cs
  on cs.organization_id = s.organization_id and cs.project_id = s.project_id;

-- ===========================================================================
-- 5. F8 integrity center: an approved-but-not-executed correction is still
--    an open operational control item and must remain visible.
-- ===========================================================================
create or replace view public.financial_integrity_signals_read with (security_invoker=on) as
with unbalanced as (
  select jb.organization_id, jb.project_id,
         'UNBALANCED_BATCHES'::text as signal_code,
         'قيد غير متوازن (دين ≠ دائن)'::text as signal_label_ar,
         'CRITICAL'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(jb.id) as source_ids
  from public.journal_batches jb
  join public.journal_lines jl on jl.batch_id = jb.id
  group by jb.organization_id, jb.project_id, jb.id
  having sum(jl.debit_minor_units) <> sum(jl.credit_minor_units)
),
overdue as (
  select organization_id, project_id,
         'OVERDUE_OBLIGATIONS'::text as signal_code,
         'التزامات مستحقة متأخرة السداد'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         sum(outstanding_minor_units::bigint)::text as amount_minor_units,
         currency,
         array_agg(obligation_id) as source_ids
  from public.cost_obligation_due_read
  where status = 'AUTHORIZED'
    and is_reversed = false
    and aging_bucket like 'OVERDUE%'
    and outstanding_minor_units::bigint > 0
  group by organization_id, project_id, currency
),
disputes as (
  select d.organization_id, o.project_id,
         'OPEN_DISPUTES'::text as signal_code,
         'نزاعات مفتوحة على التزامات'::text as signal_label_ar,
         'CRITICAL'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(o.id) as source_ids
  from public.cost_obligation_disputes d
  join public.cost_obligations o on o.id = d.obligation_id
  where d.status = 'OPEN'
  group by d.organization_id, o.project_id
),
unreconciled_payments as (
  select organization_id, project_id,
         'UNRECONCILED_PAYMENTS'::text as signal_code,
         'مدفوعات غير مطابقة بكشف البنك'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         sum(amount_minor_units::bigint)::text as amount_minor_units,
         currency,
         array_agg(payment_id) as source_ids
  from public.payment_status_read
  where is_reversed = false and is_reconciled = false
  group by organization_id, project_id, currency
),
unmatched_statements as (
  select organization_id, project_id,
         'UNMATCHED_STATEMENT_LINES'::text as signal_code,
         'سطور كشف بنك غير مطابقة'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         sum(amount_minor_units::bigint)::text as amount_minor_units,
         currency,
         array_agg(line_id) as source_ids
  from public.bank_statement_line_status_read
  where is_reconciled = false
  group by organization_id, project_id, currency
),
open_budget_exceptions as (
  select organization_id, project_id,
         'OPEN_BUDGET_EXCEPTIONS'::text as signal_code,
         'استثناءات موازنة بانتظار القرار'::text as signal_label_ar,
         'CRITICAL'::text as severity,
         count(*) as subject_count,
         sum(amount_minor_units)::text as amount_minor_units,
         currency,
         array_agg(id) as source_ids
  from public.approval_exceptions
  where status = 'OPEN' and exception_domain = 'BUDGET_CEILING'
  group by organization_id, project_id, currency
),
open_invoice_exceptions as (
  select organization_id, project_id,
         'OPEN_INVOICE_EXCEPTIONS'::text as signal_code,
         'استثناءات فواتير موردين بانتظار القرار'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(id) as source_ids
  from public.procurement_invoice_exceptions
  where status = 'OPEN'
  group by organization_id, project_id
),
open_close_exceptions as (
  select e.organization_id, cr.project_id,
         'OPEN_CLOSE_EXCEPTIONS'::text as signal_code,
         'استثناءات إقفال فترة بانتظار القرار'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(e.id) as source_ids
  from public.close_run_exceptions e
  join public.close_runs cr on cr.id = e.close_run_id
  where e.status = 'PENDING'
  group by e.organization_id, cr.project_id
),
open_corrections as (
  select organization_id, project_id,
         'OPEN_CORRECTION_REQUESTS'::text as signal_code,
         'طلبات تصحيح مفتوحة أو معتمدة بانتظار التنفيذ'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(id) as source_ids
  from public.correction_requests
  where status in ('REQUESTED','APPROVED')
  group by organization_id, project_id
),
stale_drafts as (
  select organization_id, project_id,
         'STALE_DRAFT_OBLIGATIONS'::text as signal_code,
         'التزامات مسودة قديمة بلا قرار'::text as signal_label_ar,
         'INFO'::text as severity,
         count(*) as subject_count,
         sum(amount_minor_units)::text as amount_minor_units,
         currency,
         array_agg(id) as source_ids
  from public.cost_obligations
  where status = 'DRAFT' and created_at < now() - interval '30 days'
  group by organization_id, project_id, currency
),
no_budget as (
  select o.organization_id, o.project_id,
         'NO_APPROVED_BUDGET'::text as signal_code,
         'نشاط مالي بدون موازنة معتمدة'::text as signal_label_ar,
         'INFO'::text as severity,
         count(distinct o.id) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(distinct o.id) as source_ids
  from public.cost_obligations o
  where o.status = 'AUTHORIZED'
    and not exists (
      select 1 from public.project_budgets b
      where b.project_id = o.project_id
        and b.organization_id = o.organization_id
        and b.status = 'APPROVED'
    )
  group by o.organization_id, o.project_id
),
near_ceiling as (
  select organization_id, project_id,
         'BUDGET_NEAR_CEILING'::text as signal_code,
         'استهلاك الموازنة قرب السقف (٩٠٪+)'::text as signal_label_ar,
         'INFO'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, currency,
         array_agg(budget_line_id) as source_ids
  from public.project_budget_consumption_read
  where budget_minor_units::bigint > 0
    and (committed_obligations_minor_units::bigint * 100)
        >= (budget_minor_units::bigint * 90)
  group by organization_id, project_id, currency
),
fx_gap as (
  select o.id as organization_id, null::uuid as project_id,
         'ORG_FX_GAP'::text as signal_code,
         'عملة تقارير معلنة بدون سعر صرف مسجل'::text as signal_label_ar,
         'INFO'::text as severity,
         count(distinct p.id) as subject_count,
         null::text as amount_minor_units,
         o.reporting_currency as currency,
         array_agg(distinct p.id) as source_ids
  from public.organizations o
  join public.investment_projects p
    on p.organization_id = o.id
   and p.reporting_currency is distinct from o.reporting_currency
  where o.reporting_currency is not null
    and not exists (
      select 1 from public.fx_rate_snapshots s
      where s.organization_id = o.id
        and s.base_currency = p.reporting_currency
        and s.quote_currency = o.reporting_currency
        and s.rate_date <= current_date
    )
  group by o.id, o.reporting_currency
)
select * from unbalanced
union all select * from overdue
union all select * from disputes
union all select * from unreconciled_payments
union all select * from unmatched_statements
union all select * from open_budget_exceptions
union all select * from open_invoice_exceptions
union all select * from open_close_exceptions
union all select * from open_corrections
union all select * from stale_drafts
union all select * from no_budget
union all select * from near_ceiling
union all select * from fx_gap;
