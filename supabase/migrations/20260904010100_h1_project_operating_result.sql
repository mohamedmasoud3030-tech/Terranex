-- H1 — Project operating result: the qualified result contract (ADR 0034 §2, §4).
--
-- CONTRACT (ADR 0034 §2.1)
--   A surfaced result is inseparable from:
--     amount + currency + basis + cost_classification_status + evidence_status
--     + policy_availability + as_of
--
--   Therefore this view exposes NO bare result scalar. The amount exists only
--   inside the `management_result` jsonb object. Selecting the result necessarily
--   selects its qualification, because there is no column that carries the amount
--   alone. Sector and organization roll-ups aggregate by extracting the amount from
--   the object; they never select a scalar column either.
--
--   Component columns (revenue by source, attributed cost, overhead, unclassified)
--   ARE exposed, so any consumer may recompute the arithmetic. What is deliberately
--   withheld is the headline stripped of its basis.
--
-- BASIS IS SECTOR-OWNED (ADR 0034 §3.6, §1)
--   REAL_ESTATE   realized disposal result (sector-owned) + rental revenue
--                 - attributed property operating expense EXCLUDING category 'SELLING'
--                 - declared project overhead
--   AGRICULTURE   sale revenue - cost attributed to crop cycles - declared project overhead
--   LIVESTOCK     sale revenue - cost attributed to cohorts     - declared project overhead
--
--   The 'SELLING' exclusion is not cosmetic: property_realized_result_read already
--   nets selling costs inside the realized disposal result, so subtracting them again
--   would double count. This is gated by supabase/tests/100_h1_project_result_truth.sql.
--
-- TERMINOLOGY (ADR 0034 §2.2)
--   This measure is MANAGEMENT_OPERATING_RESULT / نتيجة التشغيل الإدارية.
--   'profit', 'return', 'investor return', 'realized investment return', IRR, MOIC,
--   TVPI, equity multiple, cash-on-cash and distributable cash are RESERVED and appear
--   nowhere in this migration.
--
-- Currency discipline: components are restricted to the project's reporting currency,
-- following the existing precedent of project_financial_position_read (F9). Money is
-- transported as text. Nothing here converts currency.

create or replace view public.project_operating_result_read with (security_invoker=on) as
with active_postings as (
  select jl.id, jl.obligation_id, jl.organization_id, jl.project_id, jl.account_id, sa.role,
         jl.debit_minor_units, jl.credit_minor_units, jl.currency
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa on sa.id = jl.account_id
  where jb.reversal_of_batch_id is null
    and not exists (
      select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
    )
),
by_role as (
  select organization_id, project_id, currency, role,
         sum(debit_minor_units) as debits,
         sum(credit_minor_units) as credits
  from active_postings
  group by organization_id, project_id, currency, role
),
revenue as (
  select organization_id, project_id, currency,
    coalesce(sum(credits - debits) filter (where role in (
      'REAL_ESTATE_SALE_REVENUE','AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE'
    )), 0) as sale_revenue_minor,
    coalesce(sum(credits - debits) filter (where role = 'REAL_ESTATE_RENTAL_REVENUE'), 0)
      as rental_revenue_minor,
    coalesce(sum(debits - credits) filter (where role = 'REAL_ESTATE_COST_OF_SALE'), 0)
      as cogs_derecognized_minor
  from by_role
  group by organization_id, project_id, currency
),
re_disposal as (
  -- Sector-owned: the recognized disposal result of Real Estate assets.
  select r.organization_id, r.project_id, r.currency,
         sum(r.realized_result_minor_units::bigint) as realized_disposal_minor,
         sum(r.selling_costs_minor_units::bigint) as selling_costs_minor
  from public.property_realized_result_read r
  join public.journal_batches jb on jb.id = r.recognition_batch_id
  where jb.reversal_of_batch_id is null
    and not exists (
      select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
    )
  group by r.organization_id, r.project_id, r.currency
),
classification as (
  select organization_id, project_id, currency,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'ATTRIBUTED_TO_OPERATING_UNIT'), 0) as attributed_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'PROJECT_OVERHEAD'), 0) as overhead_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'EXCLUDED_FROM_MANAGEMENT_RESULT'), 0) as excluded_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'UNCLASSIFIED'), 0) as unclassified_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'EXPENSE_OUTSIDE_CLASSIFICATION_SCOPE'), 0)
      as outside_scope_minor
  from public.project_cost_classification_read
  group by organization_id, project_id, currency
),
re_selling_attributed as (
  -- RE only: expense already netted inside the realized disposal result.
  select el.organization_id, el.project_id, el.currency,
         sum(el.expense_minor_units) as selling_attributed_minor
  from (
    select jl.organization_id, jl.project_id, jl.currency, jl.obligation_id,
           (jl.debit_minor_units - jl.credit_minor_units) as expense_minor_units
    from active_postings jl
    where jl.role = 'PROJECT_EXPENSE'
  ) el
  join public.property_cost_items pci
    on pci.cost_obligation_id = el.obligation_id and pci.cost_category = 'SELLING'
  group by el.organization_id, el.project_id, el.currency
),
evidence_facts as (
  -- Optional-evidence facts only. Facts with a mandatory evidence reference always
  -- score 100% and would dilute the measure, so they are deliberately out of scope.
  select organization_id, project_id, evidence_reference from public.unapplied_payments
  union all select organization_id, project_id, evidence_reference from public.supplier_advances
  union all select organization_id, project_id, evidence_reference from public.supplier_credit_notes
  union all select organization_id, project_id, evidence_reference from public.cost_payment_proposals
  union all select organization_id, project_id, evidence_reference from public.real_estate_events
  union all select organization_id, project_id, evidence_reference
    from public.property_asset_state_history
  union all select organization_id, project_id, evidence_reference from public.field_activities
  union all select organization_id, project_id, evidence_reference from public.input_applications
  union all select organization_id, project_id, evidence_reference from public.harvest_events
  union all select organization_id, project_id, evidence_reference
    from public.harvest_inventory_movements
  union all select organization_id, project_id, evidence_reference from public.livestock_health_events
  union all select organization_id, project_id, evidence_reference from public.livestock_feed_issues
  union all select organization_id, project_id, evidence_reference from public.livestock_weight_events
  union all select organization_id, project_id, evidence_reference
    from public.livestock_cohort_movements
  union all select organization_id, project_id, evidence_reference
    from public.livestock_quantity_events
),
evidence as (
  select organization_id, project_id,
         count(*) as subject_count,
         count(*) filter (
           where evidence_reference is not null and char_length(trim(evidence_reference)) > 0
         ) as evidenced_count
  from evidence_facts
  group by organization_id, project_id
),
-- NOTE: there is deliberately no global policy CTE here. ADR 0033's gate
-- (public.require_policy_activated) is scoped by ORGANIZATION and by SCOPE, and so
-- is this disclosure: one organization activating investor economics must never
-- change what another organization's result claims. The predicate is therefore
-- evaluated per row, in the jsonb object below.
components as (
  select
    p.id as project_id,
    p.organization_id,
    p.sector,
    p.reporting_currency as currency,
    coalesce(rev.sale_revenue_minor, 0) as sale_revenue_minor,
    coalesce(rev.rental_revenue_minor, 0) as rental_revenue_minor,
    coalesce(rev.cogs_derecognized_minor, 0) as cogs_derecognized_minor,
    coalesce(rd.realized_disposal_minor, 0) as realized_disposal_minor,
    coalesce(rd.selling_costs_minor, 0) as selling_costs_minor,
    coalesce(c.attributed_minor, 0) as attributed_minor,
    coalesce(rs.selling_attributed_minor, 0) as selling_attributed_minor,
    coalesce(c.overhead_minor, 0) as overhead_minor,
    coalesce(c.excluded_minor, 0) as excluded_minor,
    coalesce(c.unclassified_minor, 0) as unclassified_minor,
    coalesce(c.outside_scope_minor, 0) as outside_scope_minor,
    coalesce(e.subject_count, 0) as evidence_subject_count,
    coalesce(e.evidenced_count, 0) as evidence_evidenced_count
  from public.investment_projects p
  left join revenue rev
    on rev.project_id = p.id and rev.currency = p.reporting_currency
  left join re_disposal rd
    on rd.project_id = p.id and rd.currency = p.reporting_currency
  left join classification c
    on c.project_id = p.id and c.currency = p.reporting_currency
  left join re_selling_attributed rs
    on rs.project_id = p.id and rs.currency = p.reporting_currency
  left join evidence e on e.project_id = p.id
),
derived as (
  select
    c.*,
    (c.attributed_minor - case when c.sector = 'REAL_ESTATE' then c.selling_attributed_minor else 0 end)
      as deductible_attributed_minor,
    case c.sector
      when 'REAL_ESTATE' then
        c.realized_disposal_minor + c.rental_revenue_minor
        - (c.attributed_minor - c.selling_attributed_minor)
        - c.overhead_minor
      else
        c.sale_revenue_minor - c.attributed_minor - c.overhead_minor
    end as result_amount_minor,
    case c.sector
      when 'REAL_ESTATE' then 'REAL_ESTATE_DISPOSAL_AND_RENTAL'
      when 'AGRICULTURE' then 'AGRICULTURE_ENTERPRISE_OPERATING'
      when 'LIVESTOCK' then 'LIVESTOCK_ENTERPRISE_OPERATING'
      else 'UNKNOWN_SECTOR'
    end as result_basis,
    case
      when c.unclassified_minor > 0 and c.attributed_minor = 0 and c.overhead_minor = 0
        then 'NONE'
      when c.unclassified_minor > 0 then 'PARTIAL'
      when c.attributed_minor = 0 and c.overhead_minor = 0 and c.excluded_minor = 0
       and c.outside_scope_minor = 0 then 'NOT_APPLICABLE_NO_OPERATING_COST'
      else 'COMPLETE'
    end as cost_classification_status,
    case
      when c.evidence_subject_count = 0 then 'NOT_APPLICABLE_NO_EVIDENCE_CONTRACT'
      when c.evidence_evidenced_count = c.evidence_subject_count then 'COMPLETE'
      when c.evidence_evidenced_count > 0 then 'PARTIAL'
      else 'INCOMPLETE'
    end as evidence_status
  from components c
)
select
  d.project_id,
  d.organization_id,
  d.sector,
  d.currency,
  d.result_basis,
  d.cost_classification_status,
  d.evidence_status,

  -- The qualified result object. The amount exists only here.
  jsonb_build_object(
    'amount_minor_units', d.result_amount_minor::text,
    'currency', d.currency,
    'basis', d.result_basis,
    'cost_classification_status', d.cost_classification_status,
    'evidence_status', d.evidence_status,
    'policy_availability',
      case d.sector
        when 'REAL_ESTATE' then
          array['UNREALIZED_VALUATION_NOT_INCLUDED_IN_MANAGEMENT_RESULT']::text[]
        when 'AGRICULTURE' then
          array['COGS_NOT_RECOGNIZED','HARVEST_INVENTORY_VALUE_NOT_RECOGNIZED']::text[]
        when 'LIVESTOCK' then
          array['COGS_NOT_RECOGNIZED','BIOLOGICAL_ASSET_VALUE_NOT_RECOGNIZED']::text[]
        else array[]::text[]
      end
      || array['RETURN_MULTIPLES_UNAVAILABLE_PENDING_POLICY']::text[]
      || case when exists (
                select 1 from public.policy_authority pa
                where pa.organization_id = d.organization_id
                  and pa.scope = 'INVESTOR_ECONOMICS'
                  and pa.status = 'APPROVED'
              ) then array[]::text[]
              else array['INVESTOR_ENTITLEMENT_NOT_ACTIVATED']::text[] end,
    'as_of', current_date
  ) as management_result,

  -- Components: exposed so any consumer can recompute the arithmetic.
  d.sale_revenue_minor::text as sale_revenue_minor_units,
  d.rental_revenue_minor::text as rental_revenue_minor_units,
  d.cogs_derecognized_minor::text as cogs_derecognized_minor_units,
  d.realized_disposal_minor::text as realized_disposal_minor_units,
  d.selling_costs_minor::text as selling_costs_minor_units,
  d.attributed_minor::text as attributed_operating_cost_minor_units,
  d.selling_attributed_minor::text as selling_cost_attributed_minor_units,
  d.overhead_minor::text as project_overhead_minor_units,
  d.excluded_minor::text as excluded_from_result_minor_units,
  d.unclassified_minor::text as unclassified_eligible_minor_units,
  d.outside_scope_minor::text as expense_outside_classification_scope_minor_units,
  d.evidence_evidenced_count as evidence_evidenced_count,
  d.evidence_subject_count as evidence_subject_count,
  current_date as as_of
from derived d;

comment on view public.project_operating_result_read is
  'H1 qualified management operating result per project (ADR 0034). The result amount '
  'exists ONLY inside the management_result jsonb object; there is no bare result scalar '
  'column, so the amount cannot be selected without its basis, cost-classification status, '
  'evidence status, policy-availability list and as-of date. Basis and cost semantics are '
  'sector-owned: Real Estate uses the sector realized disposal result plus rental revenue '
  'less attributed property operating cost excluding SELLING (already netted inside the '
  'realized result) less declared overhead; Agriculture and Livestock use sale revenue less '
  'operating cost attributed to crop cycles or cohorts less declared overhead. Management '
  'basis only: this is not profit, return, or an investor entitlement.';

-- ===========================================================================
-- Integrity signals: UNCLASSIFIED_OPERATING_COST and UNVERIFIED_MANAGEMENT_RESULT.
--
-- Without these, a crop cycle or cohort carrying revenue and no classified cost
-- would present its result as if the cost were zero. The unclassified amount is
-- always carried with the signal, so incompleteness can never be mistaken for margin.
--
-- The existing F8 signal set is preserved byte-for-byte. This definition was
-- regenerated from the live view (which carries the source_ids column added by
-- 20260816058400) rather than from the superseded 20260816055000 text, so no
-- existing branch or column is dropped.
-- ===========================================================================

create or replace view public.financial_integrity_signals_read with (security_invoker=on) as
 WITH unbalanced AS (
         SELECT jb.organization_id,
            jb.project_id,
            'UNBALANCED_BATCHES'::text AS signal_code,
            'قيد غير متوازن (دين ≠ دائن)'::text AS signal_label_ar,
            'CRITICAL'::text AS severity,
            count(*) AS subject_count,
            NULL::text AS amount_minor_units,
            NULL::text AS currency,
            array_agg(jb.id) AS source_ids
           FROM journal_batches jb
             JOIN journal_lines jl ON jl.batch_id = jb.id
          GROUP BY jb.organization_id, jb.project_id, jb.id
         HAVING sum(jl.debit_minor_units) <> sum(jl.credit_minor_units)
        ), overdue AS (
         SELECT cost_obligation_due_read.organization_id,
            cost_obligation_due_read.project_id,
            'OVERDUE_OBLIGATIONS'::text AS signal_code,
            'التزامات مستحقة متأخرة السداد'::text AS signal_label_ar,
            'WARNING'::text AS severity,
            count(*) AS subject_count,
            sum(cost_obligation_due_read.outstanding_minor_units::bigint)::text AS amount_minor_units,
            cost_obligation_due_read.currency,
            array_agg(cost_obligation_due_read.obligation_id) AS source_ids
           FROM cost_obligation_due_read
          WHERE cost_obligation_due_read.status = 'AUTHORIZED'::text AND cost_obligation_due_read.is_reversed = false AND cost_obligation_due_read.aging_bucket ~~ 'OVERDUE%'::text AND cost_obligation_due_read.outstanding_minor_units::bigint > 0
          GROUP BY cost_obligation_due_read.organization_id, cost_obligation_due_read.project_id, cost_obligation_due_read.currency
        ), disputes AS (
         SELECT d.organization_id,
            o.project_id,
            'OPEN_DISPUTES'::text AS signal_code,
            'نزاعات مفتوحة على التزامات'::text AS signal_label_ar,
            'CRITICAL'::text AS severity,
            count(*) AS subject_count,
            NULL::text AS amount_minor_units,
            NULL::text AS currency,
            array_agg(o.id) AS source_ids
           FROM cost_obligation_disputes d
             JOIN cost_obligations o ON o.id = d.obligation_id
          WHERE d.status = 'OPEN'::text
          GROUP BY d.organization_id, o.project_id
        ), unreconciled_payments AS (
         SELECT payment_status_read.organization_id,
            payment_status_read.project_id,
            'UNRECONCILED_PAYMENTS'::text AS signal_code,
            'مدفوعات غير مطابقة بكشف البنك'::text AS signal_label_ar,
            'WARNING'::text AS severity,
            count(*) AS subject_count,
            sum(payment_status_read.amount_minor_units::bigint)::text AS amount_minor_units,
            payment_status_read.currency,
            array_agg(payment_status_read.payment_id) AS source_ids
           FROM payment_status_read
          WHERE payment_status_read.is_reversed = false AND payment_status_read.is_reconciled = false
          GROUP BY payment_status_read.organization_id, payment_status_read.project_id, payment_status_read.currency
        ), unmatched_statements AS (
         SELECT bank_statement_line_status_read.organization_id,
            bank_statement_line_status_read.project_id,
            'UNMATCHED_STATEMENT_LINES'::text AS signal_code,
            'سطور كشف بنك غير مطابقة'::text AS signal_label_ar,
            'WARNING'::text AS severity,
            count(*) AS subject_count,
            sum(bank_statement_line_status_read.amount_minor_units::bigint)::text AS amount_minor_units,
            bank_statement_line_status_read.currency,
            array_agg(bank_statement_line_status_read.line_id) AS source_ids
           FROM bank_statement_line_status_read
          WHERE bank_statement_line_status_read.is_reconciled = false
          GROUP BY bank_statement_line_status_read.organization_id, bank_statement_line_status_read.project_id, bank_statement_line_status_read.currency
        ), open_budget_exceptions AS (
         SELECT approval_exceptions.organization_id,
            approval_exceptions.project_id,
            'OPEN_BUDGET_EXCEPTIONS'::text AS signal_code,
            'استثناءات موازنة بانتظار القرار'::text AS signal_label_ar,
            'CRITICAL'::text AS severity,
            count(*) AS subject_count,
            sum(approval_exceptions.amount_minor_units)::text AS amount_minor_units,
            approval_exceptions.currency,
            array_agg(approval_exceptions.id) AS source_ids
           FROM approval_exceptions
          WHERE approval_exceptions.status = 'OPEN'::text AND approval_exceptions.exception_domain = 'BUDGET_CEILING'::text
          GROUP BY approval_exceptions.organization_id, approval_exceptions.project_id, approval_exceptions.currency
        ), open_invoice_exceptions AS (
         SELECT procurement_invoice_exceptions.organization_id,
            procurement_invoice_exceptions.project_id,
            'OPEN_INVOICE_EXCEPTIONS'::text AS signal_code,
            'استثناءات فواتير موردين بانتظار القرار'::text AS signal_label_ar,
            'WARNING'::text AS severity,
            count(*) AS subject_count,
            NULL::text AS amount_minor_units,
            NULL::text AS currency,
            array_agg(procurement_invoice_exceptions.id) AS source_ids
           FROM procurement_invoice_exceptions
          WHERE procurement_invoice_exceptions.status = 'OPEN'::text
          GROUP BY procurement_invoice_exceptions.organization_id, procurement_invoice_exceptions.project_id
        ), open_close_exceptions AS (
         SELECT e.organization_id,
            cr.project_id,
            'OPEN_CLOSE_EXCEPTIONS'::text AS signal_code,
            'استثناءات إقفال فترة بانتظار القرار'::text AS signal_label_ar,
            'WARNING'::text AS severity,
            count(*) AS subject_count,
            NULL::text AS amount_minor_units,
            NULL::text AS currency,
            array_agg(e.id) AS source_ids
           FROM close_run_exceptions e
             JOIN close_runs cr ON cr.id = e.close_run_id
          WHERE e.status = 'PENDING'::text
          GROUP BY e.organization_id, cr.project_id
        ), open_corrections AS (
         SELECT correction_requests.organization_id,
            correction_requests.project_id,
            'OPEN_CORRECTION_REQUESTS'::text AS signal_code,
            'طلبات تصحيح مفتوحة أو معتمدة بانتظار التنفيذ'::text AS signal_label_ar,
            'WARNING'::text AS severity,
            count(*) AS subject_count,
            NULL::text AS amount_minor_units,
            NULL::text AS currency,
            array_agg(correction_requests.id) AS source_ids
           FROM correction_requests
          WHERE correction_requests.status = ANY (ARRAY['REQUESTED'::text, 'APPROVED'::text])
          GROUP BY correction_requests.organization_id, correction_requests.project_id
        ), stale_drafts AS (
         SELECT cost_obligations.organization_id,
            cost_obligations.project_id,
            'STALE_DRAFT_OBLIGATIONS'::text AS signal_code,
            'التزامات مسودة قديمة بلا قرار'::text AS signal_label_ar,
            'INFO'::text AS severity,
            count(*) AS subject_count,
            sum(cost_obligations.amount_minor_units)::text AS amount_minor_units,
            cost_obligations.currency,
            array_agg(cost_obligations.id) AS source_ids
           FROM cost_obligations
          WHERE cost_obligations.status = 'DRAFT'::text AND cost_obligations.created_at < (now() - '30 days'::interval)
          GROUP BY cost_obligations.organization_id, cost_obligations.project_id, cost_obligations.currency
        ), no_budget AS (
         SELECT o.organization_id,
            o.project_id,
            'NO_APPROVED_BUDGET'::text AS signal_code,
            'نشاط مالي بدون موازنة معتمدة'::text AS signal_label_ar,
            'INFO'::text AS severity,
            count(DISTINCT o.id) AS subject_count,
            NULL::text AS amount_minor_units,
            NULL::text AS currency,
            array_agg(DISTINCT o.id) AS source_ids
           FROM cost_obligations o
          WHERE o.status = 'AUTHORIZED'::text AND NOT (EXISTS ( SELECT 1
                   FROM project_budgets b
                  WHERE b.project_id = o.project_id AND b.organization_id = o.organization_id AND b.status = 'APPROVED'::text))
          GROUP BY o.organization_id, o.project_id
        ), near_ceiling AS (
         SELECT project_budget_consumption_read.organization_id,
            project_budget_consumption_read.project_id,
            'BUDGET_NEAR_CEILING'::text AS signal_code,
            'استهلاك الموازنة قرب السقف (٩٠٪+)'::text AS signal_label_ar,
            'INFO'::text AS severity,
            count(*) AS subject_count,
            NULL::text AS amount_minor_units,
            project_budget_consumption_read.currency,
            array_agg(project_budget_consumption_read.budget_line_id) AS source_ids
           FROM project_budget_consumption_read
          WHERE project_budget_consumption_read.budget_minor_units::bigint > 0 AND (project_budget_consumption_read.committed_obligations_minor_units::bigint * 100) >= (project_budget_consumption_read.budget_minor_units::bigint * 90)
          GROUP BY project_budget_consumption_read.organization_id, project_budget_consumption_read.project_id, project_budget_consumption_read.currency
        ), fx_gap AS (
         SELECT o.id AS organization_id,
            NULL::uuid AS project_id,
            'ORG_FX_GAP'::text AS signal_code,
            'عملة تقارير معلنة بدون سعر صرف مسجل'::text AS signal_label_ar,
            'INFO'::text AS severity,
            count(DISTINCT p.id) AS subject_count,
            NULL::text AS amount_minor_units,
            o.reporting_currency AS currency,
            array_agg(DISTINCT p.id) AS source_ids
           FROM organizations o
             JOIN investment_projects p ON p.organization_id = o.id AND p.reporting_currency IS DISTINCT FROM o.reporting_currency
          WHERE o.reporting_currency IS NOT NULL AND NOT (EXISTS ( SELECT 1
                   FROM fx_rate_snapshots s
                  WHERE s.organization_id = o.id AND s.base_currency = p.reporting_currency AND s.quote_currency = o.reporting_currency AND s.rate_date <= CURRENT_DATE))
          GROUP BY o.id, o.reporting_currency
        )
 SELECT unbalanced.organization_id,
    unbalanced.project_id,
    unbalanced.signal_code,
    unbalanced.signal_label_ar,
    unbalanced.severity,
    unbalanced.subject_count,
    unbalanced.amount_minor_units,
    unbalanced.currency,
    unbalanced.source_ids
   FROM unbalanced
UNION ALL
 SELECT overdue.organization_id,
    overdue.project_id,
    overdue.signal_code,
    overdue.signal_label_ar,
    overdue.severity,
    overdue.subject_count,
    overdue.amount_minor_units,
    overdue.currency,
    overdue.source_ids
   FROM overdue
UNION ALL
 SELECT disputes.organization_id,
    disputes.project_id,
    disputes.signal_code,
    disputes.signal_label_ar,
    disputes.severity,
    disputes.subject_count,
    disputes.amount_minor_units,
    disputes.currency,
    disputes.source_ids
   FROM disputes
UNION ALL
 SELECT unreconciled_payments.organization_id,
    unreconciled_payments.project_id,
    unreconciled_payments.signal_code,
    unreconciled_payments.signal_label_ar,
    unreconciled_payments.severity,
    unreconciled_payments.subject_count,
    unreconciled_payments.amount_minor_units,
    unreconciled_payments.currency,
    unreconciled_payments.source_ids
   FROM unreconciled_payments
UNION ALL
 SELECT unmatched_statements.organization_id,
    unmatched_statements.project_id,
    unmatched_statements.signal_code,
    unmatched_statements.signal_label_ar,
    unmatched_statements.severity,
    unmatched_statements.subject_count,
    unmatched_statements.amount_minor_units,
    unmatched_statements.currency,
    unmatched_statements.source_ids
   FROM unmatched_statements
UNION ALL
 SELECT open_budget_exceptions.organization_id,
    open_budget_exceptions.project_id,
    open_budget_exceptions.signal_code,
    open_budget_exceptions.signal_label_ar,
    open_budget_exceptions.severity,
    open_budget_exceptions.subject_count,
    open_budget_exceptions.amount_minor_units,
    open_budget_exceptions.currency,
    open_budget_exceptions.source_ids
   FROM open_budget_exceptions
UNION ALL
 SELECT open_invoice_exceptions.organization_id,
    open_invoice_exceptions.project_id,
    open_invoice_exceptions.signal_code,
    open_invoice_exceptions.signal_label_ar,
    open_invoice_exceptions.severity,
    open_invoice_exceptions.subject_count,
    open_invoice_exceptions.amount_minor_units,
    open_invoice_exceptions.currency,
    open_invoice_exceptions.source_ids
   FROM open_invoice_exceptions
UNION ALL
 SELECT open_close_exceptions.organization_id,
    open_close_exceptions.project_id,
    open_close_exceptions.signal_code,
    open_close_exceptions.signal_label_ar,
    open_close_exceptions.severity,
    open_close_exceptions.subject_count,
    open_close_exceptions.amount_minor_units,
    open_close_exceptions.currency,
    open_close_exceptions.source_ids
   FROM open_close_exceptions
UNION ALL
 SELECT open_corrections.organization_id,
    open_corrections.project_id,
    open_corrections.signal_code,
    open_corrections.signal_label_ar,
    open_corrections.severity,
    open_corrections.subject_count,
    open_corrections.amount_minor_units,
    open_corrections.currency,
    open_corrections.source_ids
   FROM open_corrections
UNION ALL
 SELECT stale_drafts.organization_id,
    stale_drafts.project_id,
    stale_drafts.signal_code,
    stale_drafts.signal_label_ar,
    stale_drafts.severity,
    stale_drafts.subject_count,
    stale_drafts.amount_minor_units,
    stale_drafts.currency,
    stale_drafts.source_ids
   FROM stale_drafts
UNION ALL
 SELECT no_budget.organization_id,
    no_budget.project_id,
    no_budget.signal_code,
    no_budget.signal_label_ar,
    no_budget.severity,
    no_budget.subject_count,
    no_budget.amount_minor_units,
    no_budget.currency,
    no_budget.source_ids
   FROM no_budget
UNION ALL
 SELECT near_ceiling.organization_id,
    near_ceiling.project_id,
    near_ceiling.signal_code,
    near_ceiling.signal_label_ar,
    near_ceiling.severity,
    near_ceiling.subject_count,
    near_ceiling.amount_minor_units,
    near_ceiling.currency,
    near_ceiling.source_ids
   FROM near_ceiling
UNION ALL
 SELECT fx_gap.organization_id,
    fx_gap.project_id,
    fx_gap.signal_code,
    fx_gap.signal_label_ar,
    fx_gap.severity,
    fx_gap.subject_count,
    fx_gap.amount_minor_units,
    fx_gap.currency,
    fx_gap.source_ids
   FROM fx_gap
UNION ALL
 SELECT c.organization_id,
    c.project_id,
    'UNCLASSIFIED_OPERATING_COST'::text,
    'تكلفة تشغيل مؤهلة لم تُصنّف بعد'::text,
    'WARNING'::text,
    sum(c.line_count)::bigint,
    sum(c.expense_minor_units::bigint)::text,
    c.currency,
    null::uuid[]
   FROM ( SELECT organization_id, project_id, currency, line_count, expense_minor_units
           FROM public.project_cost_classification_read
          WHERE classification_state = 'UNCLASSIFIED' ) c
  GROUP BY c.organization_id, c.project_id, c.currency
 HAVING sum(c.expense_minor_units::bigint) > 0
UNION ALL
 SELECT r.organization_id,
    r.project_id,
    'UNVERIFIED_MANAGEMENT_RESULT'::text,
    'نتيجة تشغيل بلا تصنيف تكلفة — لا تُقرأ كهامش ربح'::text,
    'WARNING'::text,
    1::bigint,
    null::text,
    r.currency,
    null::uuid[]
   FROM public.project_operating_result_read r
  WHERE r.cost_classification_status = 'NONE'
    AND (r.sale_revenue_minor_units::bigint > 0 OR r.rental_revenue_minor_units::bigint > 0);

comment on view public.financial_integrity_signals_read is
  'F8 unified derived control-signal surface over the whole financial control stack, '
  'extended by H1 with UNCLASSIFIED_OPERATING_COST (eligible operating cost not yet '
  'classified; the amount is always carried with the signal) and '
  'UNVERIFIED_MANAGEMENT_RESULT (revenue present with no classified operating cost, so '
  'the management result must not be read as margin). Every signal is computed from '
  'authoritative facts; nothing is estimated and no score is invented.';

grant select on public.project_operating_result_read to authenticated;
grant select on public.financial_integrity_signals_read to authenticated;
