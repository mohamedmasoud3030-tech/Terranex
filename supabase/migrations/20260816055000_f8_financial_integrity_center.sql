-- F8 — Financial Integrity Center.
--
-- A single derived signal surface over the whole financial control stack.
-- Every signal is computed from authoritative facts; nothing is estimated
-- and there is no invented "score":
--   CRITICAL = a posted fact violates a hard invariant or money is blocked
--   WARNING  = controller attention required (overdue, unreconciled, ...)
--   INFO     = disclosure/management items (no budget, near ceiling, FX gap)
--
-- The signals cover the journal (balance), contract finance (disputes,
-- retention, overdue), budget (exceptions, near-ceiling, no budget),
-- payments/bank (unreconciled, unmatched), close (open exceptions,
-- corrections), procurement tolerance exceptions, and the F6 currency
-- disclosure gap (reporting currency set but no rate snapshot exists).

create or replace view public.financial_integrity_signals_read with (security_invoker=on) as
with unbalanced as (
  select jb.organization_id, jb.project_id,
         'UNBALANCED_BATCHES'::text as signal_code,
         'قيد غير متوازن (دين ≠ دائن)'::text as signal_label_ar,
         'CRITICAL'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency
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
         currency
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
         null::text as amount_minor_units, null::text as currency
  from public.cost_obligation_disputes d
  join public.cost_obligations o on o.id = d.obligation_id
  where d.status = 'OPEN'
  group by d.organization_id, o.project_id
),
retention_due as (
  select organization_id, project_id,
         'RETENTION_DUE_FOR_RELEASE'::text as signal_code,
         'محجوز ضمان مستحق للإفراج'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         sum(retention_remaining_minor_units::bigint)::text as amount_minor_units,
         currency
  from public.cost_obligation_due_read
  where status = 'AUTHORIZED'
    and is_reversed = false
    and retention_remaining_minor_units::bigint > 0
    and due_date is not null
    and due_date < current_date
  group by organization_id, project_id, currency
),
unreconciled_payments as (
  select organization_id, project_id,
         'UNRECONCILED_PAYMENTS'::text as signal_code,
         'مدفوعات غير مطابقة بكشف البنك'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         sum(amount_minor_units::bigint)::text as amount_minor_units,
         currency
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
         currency
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
         currency
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
         null::text as amount_minor_units, null::text as currency
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
         null::text as amount_minor_units, null::text as currency
  from public.close_run_exceptions e
  join public.close_runs cr on cr.id = e.close_run_id
  where e.status = 'PENDING'
  group by e.organization_id, cr.project_id
),
open_corrections as (
  select organization_id, project_id,
         'OPEN_CORRECTION_REQUESTS'::text as signal_code,
         'طلبات تصحيح بانتظار المراجعة'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency
  from public.correction_requests
  where status = 'REQUESTED'
  group by organization_id, project_id
),
stale_drafts as (
  select organization_id, project_id,
         'STALE_DRAFT_OBLIGATIONS'::text as signal_code,
         'التزامات مسودة قديمة بلا قرار'::text as signal_label_ar,
         'INFO'::text as severity,
         count(*) as subject_count,
         sum(amount_minor_units)::text as amount_minor_units,
         currency
  from public.cost_obligations
  where status = 'DRAFT' and created_at < now() - interval '30 days'
  group by organization_id, project_id, currency
),
no_budget as (
  select distinct o.organization_id, o.project_id,
         'NO_APPROVED_BUDGET'::text as signal_code,
         'نشاط مالي بدون موازنة معتمدة'::text as signal_label_ar,
         'INFO'::text as severity,
         1 as subject_count,
         null::text as amount_minor_units, null::text as currency
  from public.cost_obligations o
  where o.status = 'AUTHORIZED'
    and not exists (
      select 1 from public.project_budgets b
      where b.project_id = o.project_id
        and b.organization_id = o.organization_id
        and b.status = 'APPROVED'
    )
),
near_ceiling as (
  select organization_id, project_id,
         'BUDGET_NEAR_CEILING'::text as signal_code,
         'استهلاك الموازنة قرب السقف (٩٠٪+)'::text as signal_label_ar,
         'INFO'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, currency
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
         count(distinct p.reporting_currency) as subject_count,
         null::text as amount_minor_units,
         o.reporting_currency as currency
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
union all select * from retention_due
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

grant select on public.financial_integrity_signals_read to authenticated;
