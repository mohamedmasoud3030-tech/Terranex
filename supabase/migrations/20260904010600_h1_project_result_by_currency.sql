-- H1 — Project Brief Result panel: management operating result by currency.
--
-- WHY THIS VIEW EXISTS
--
-- `project_operating_result_read` answers "what is this project's management
-- operating result" for the Home roll-up. It is not currency-safe, and fixing it
-- in place is NOT the smallest correct change:
--
--   * `components` joins every currency-aware CTE with
--     `and <cte>.currency = p.reporting_currency`. Facts posted in any other
--     currency are therefore not aggregated and not disclosed — they are
--     silently DROPPED, and the result is still stamped with
--     `p.reporting_currency`.
--   * Its grain is one row per project, and `sector_management_result_read`
--     (the Home cross-sector roll-up) sums those project rows. Adding a currency
--     grain would change what Home reports, which is a different decision with a
--     different blast radius.
--
-- So `project_operating_result_read` stays exactly as it is, and this view
-- provides the Project Brief's own contract. Nothing here is a new financial
-- fact: it is the same authoritative CTEs, regrouped by currency.
--
-- NOT SUPERSEDED: `project_operating_result_read` remains authoritative for the
-- Home roll-up and for the S6/H1 gates that consume its project grain. The
-- currency assumption inside it is a known defect recorded for a follow-up, in
-- the same way as the BANK_CASH line-currency mismatch.
--
-- CURRENCY SEMANTICS
--
-- There is no FX contract anywhere in this repository. Therefore:
--   * one row per (project_id, currency);
--   * the currency is the currency of the posted facts themselves, never
--     `investment_projects.reporting_currency`;
--   * no cross-currency total, no conversion, no synthetic project figure;
--   * a project whose facts live in two currencies yields two rows.
--
-- The currencies present come from the union of the currency-bearing facts, so
-- a currency that has revenue but no cost still gets its own row rather than
-- being folded into another currency's classification.

create view public.project_result_by_currency_read with (security_invoker=on) as
with active_postings as (
  -- Reversal-aware base population: a batch that is itself a reversal is
  -- excluded, and so is any batch that has been reversed. An original economic
  -- effect and its reversal therefore never both count.
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
  -- Sector-owned: the recognized disposal result of Real Estate assets, in the
  -- currency of the recognition itself.
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
  -- RE only: expense already netted inside the realized disposal result. It is
  -- reported as a CLASSIFICATION bucket but deducted ZERO times.
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
  -- Optional-evidence facts only. Facts with a mandatory evidence reference
  -- always score 100% and would dilute the measure.
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
  -- Project-level: evidence completeness has no currency dimension, so the same
  -- qualification is repeated on every currency row of the project.
  select organization_id, project_id,
         count(*) as subject_count,
         count(*) filter (
           where evidence_reference is not null and char_length(trim(evidence_reference)) > 0
         ) as evidenced_count
  from evidence_facts
  group by organization_id, project_id
),
currencies as (
  select organization_id, project_id, currency from revenue
  union
  select organization_id, project_id, currency from re_disposal
  union
  select organization_id, project_id, currency from classification
  union
  select organization_id, project_id, currency from re_selling_attributed
),
components as (
  select
    p.id as project_id,
    p.organization_id,
    p.sector,
    cur.currency,
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
  -- INNER join: a project with no result fact of any kind gets no row. That is
  -- the whole point — "no realized result" must not become "result is zero".
  join currencies cur
    on cur.project_id = p.id
   and cur.organization_id = p.organization_id
  left join revenue rev
    on rev.project_id = p.id and rev.organization_id = p.organization_id
   and rev.currency = cur.currency
  left join re_disposal rd
    on rd.project_id = p.id and rd.organization_id = p.organization_id
   and rd.currency = cur.currency
  left join classification c
    on c.project_id = p.id and c.organization_id = p.organization_id
   and c.currency = cur.currency
  left join re_selling_attributed rs
    on rs.project_id = p.id and rs.organization_id = p.organization_id
   and rs.currency = cur.currency
  left join evidence e on e.project_id = p.id
),
derived as (
  select
    c.*,
    -- DEDUCTION. A Real Estate SELLING cost is classified (attributed_minor)
    -- once and deducted ZERO times, because its economic effect already sits
    -- inside the sector-owned realized disposal result.
    ((c.attributed_minor - case when c.sector = 'REAL_ESTATE'
                                then c.selling_attributed_minor else 0 end)
     + c.overhead_minor) as deducted_minor,
    case c.sector
      when 'REAL_ESTATE' then c.realized_disposal_minor + c.rental_revenue_minor
      else c.sale_revenue_minor
    end as result_revenue_minor,
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

  -- The qualified result object. The amount exists only here, bound to its
  -- currency, basis, cost-classification status, evidence status, policy
  -- availability and as-of date. There is deliberately no bare result column.
  jsonb_build_object(
    'amount_minor_units',
      (d.result_revenue_minor - d.deducted_minor)::text,
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

  -- Components, exposed so the arithmetic can be recomputed and audited.
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
  d.result_revenue_minor::text as result_revenue_minor_units,
  d.deducted_minor::text as result_deducted_cost_minor_units,
  d.evidence_evidenced_count as evidence_evidenced_count,
  d.evidence_subject_count as evidence_subject_count,
  current_date as as_of
from derived d;

comment on view public.project_result_by_currency_read is
  'H1 management operating result per (project_id, currency) for the Project Brief '
  'Result panel (ADR 0034). Same authoritative facts and same sector-owned basis as '
  'project_operating_result_read, regrouped by the currency OF THE FACTS instead of '
  'filtered to investment_projects.reporting_currency. One row per (project, currency); '
  'no FX, no cross-currency total, no conversion. The amount exists only inside the '
  'management_result jsonb object, bound to currency, basis, cost-classification status, '
  'evidence status, policy availability and as-of. Cost appears as exactly two distinct '
  'concepts: attributed_operating_cost_minor_units (CLASSIFICATION / reconciliation) and '
  'result_deducted_cost_minor_units (DEDUCTION); a Real Estate SELLING cost is classified '
  'once and deducted zero times because its effect is already netted inside the realized '
  'disposal result. Reversal-aware: a reversed batch and its reversal never both count. '
  'A project with no result fact yields no row at all, which is not the same as a zero. '
  'DOES NOT SUPERSEDE project_operating_result_read, whose project grain is consumed by '
  'the Home roll-up (sector_management_result_read) and by H1/S6 gates.';

grant select on public.project_result_by_currency_read to authenticated;
