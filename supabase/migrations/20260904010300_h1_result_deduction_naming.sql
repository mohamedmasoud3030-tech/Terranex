-- H1 — correct the classification/deduction naming (ADR 0034 §3.6).
--
-- The previous sector column was named `classified_deducted_minor_units` but was
-- defined as attributed + overhead. For Real Estate that is WRONG: a SELLING cost
-- is *classified* as attributed property cost, yet it is *deducted* zero times,
-- because `property_realized_result_read` already nets selling costs inside the
-- realized disposal result. The old column therefore reported 1,500,000 as
-- "deducted" while the result deducted 0.
--
-- "Deducted once" is ambiguous across those two layers. The invariant that
-- actually matters is:
--
--   the management result includes a cost's economic effect EXACTLY ONCE.
--
-- So classification and deduction are now separate, explicitly named concepts:
--
--   attributed_operating_cost_minor_units  CLASSIFICATION  cost classified as
--                                          attributed to an operating unit.
--                                          A SELLING cost appears here once.
--   result_deducted_cost_minor_units       DEDUCTION       cost subtracted in the
--                                          result arithmetic. A SELLING cost
--                                          appears here zero times, because its
--                                          effect already sits inside the
--                                          sector realized disposal result.
--
-- and the two are reconciled by the gate identity:
--   result = revenue components - result_deducted_cost.
--
-- `project_operating_result_read` is replaced with CREATE OR REPLACE (a column is
-- added at the end, which is permitted) so that financial_integrity_signals_read,
-- which depends on it, is not dropped. `sector_management_result_read` has no
-- dependents and its column definition changes, so it is dropped and recreated.

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
  current_date as as_of,
  -- The cost the management result actually DEDUCTS: attributed cost excluding
  -- SELLING for Real Estate, plus declared project overhead.
  --
  -- This is deliberately distinct from attributed_operating_cost_minor_units,
  -- which is a CLASSIFICATION / reconciliation bucket. A Real Estate SELLING
  -- cost is classified there exactly once while being deducted ZERO times,
  -- because its economic effect is already netted inside the sector-owned
  -- realized disposal result. Naming one in terms of the other is how a cost
  -- ends up counted twice or not at all.
  (d.deductible_attributed_minor + d.overhead_minor)::text as result_deducted_cost_minor_units
from derived d;

drop view if exists public.sector_management_result_read;

create view public.sector_management_result_read with (security_invoker=on) as
with grouped as (
  select
    r.organization_id,
    r.sector,
    r.currency,
    count(*) as project_count,
    min(r.result_basis) as basis,
    sum((r.management_result ->> 'amount_minor_units')::bigint) as amount_minor,
    sum(r.sale_revenue_minor_units::bigint) as sale_revenue_minor,
    sum(r.rental_revenue_minor_units::bigint) as rental_revenue_minor,
    sum(r.realized_disposal_minor_units::bigint) as realized_disposal_minor,
    sum(r.selling_costs_minor_units::bigint) as selling_costs_minor,
    sum(r.attributed_operating_cost_minor_units::bigint) as attributed_minor,
    sum(r.selling_cost_attributed_minor_units::bigint) as selling_attributed_minor,
    sum(r.project_overhead_minor_units::bigint) as overhead_minor,
    sum(r.excluded_from_result_minor_units::bigint) as excluded_minor,
    sum(r.unclassified_eligible_minor_units::bigint) as unclassified_minor,
    sum(r.expense_outside_classification_scope_minor_units::bigint) as outside_scope_minor,
    sum(r.result_deducted_cost_minor_units::bigint) as result_deducted_minor,
    sum(r.evidence_evidenced_count) as evidence_evidenced_count,
    sum(r.evidence_subject_count) as evidence_subject_count
  from public.project_operating_result_read r
  group by r.organization_id, r.sector, r.currency
),
derived as (
  select
    g.*,
    case
      when g.unclassified_minor > 0
       and (g.attributed_minor + g.overhead_minor + g.excluded_minor + g.outside_scope_minor) = 0
        then 'NONE'
      when g.unclassified_minor > 0 then 'PARTIAL'
      when (g.attributed_minor + g.overhead_minor + g.excluded_minor + g.outside_scope_minor) = 0
        then 'NOT_APPLICABLE_NO_OPERATING_COST'
      else 'COMPLETE'
    end as cost_classification_status,
    case
      when g.evidence_subject_count = 0 then 'NOT_APPLICABLE_NO_EVIDENCE_CONTRACT'
      when g.evidence_evidenced_count = g.evidence_subject_count then 'COMPLETE'
      when g.evidence_evidenced_count > 0 then 'PARTIAL'
      else 'INCOMPLETE'
    end as evidence_status
  from grouped g
)
select
  d.organization_id,
  d.sector,
  d.currency,
  d.project_count,
  d.basis as result_basis,
  d.cost_classification_status,
  d.evidence_status,

  jsonb_build_object(
    'amount_minor_units', d.amount_minor::text,
    'currency', d.currency,
    'basis', d.basis,
    'cost_classification_status', d.cost_classification_status,
    'evidence_status', d.evidence_status,
    'policy_availability', coalesce((
      select array_agg(distinct pol order by pol)
      from public.project_operating_result_read x,
           lateral jsonb_array_elements_text(x.management_result -> 'policy_availability') as pol(value)
      where x.organization_id = d.organization_id
        and x.sector = d.sector
        and x.currency = d.currency
    ), array[]::text[]),
    'as_of', current_date
  ) as management_result,

  d.sale_revenue_minor::text as sale_revenue_minor_units,
  d.rental_revenue_minor::text as rental_revenue_minor_units,
  d.realized_disposal_minor::text as realized_disposal_minor_units,
  d.selling_costs_minor::text as selling_costs_minor_units,
  d.attributed_minor::text as attributed_operating_cost_minor_units,
  d.selling_attributed_minor::text as selling_cost_attributed_minor_units,
  d.overhead_minor::text as project_overhead_minor_units,
  d.excluded_minor::text as excluded_from_result_minor_units,
  d.unclassified_minor::text as unclassified_eligible_minor_units,
  d.outside_scope_minor::text as expense_outside_classification_scope_minor_units,
  -- The cost the result actually deducts, summed from the project rows rather
  -- than recomputed here. For Real Estate this already excludes SELLING, whose
  -- economic effect is netted inside the sector realized disposal result.
  -- Summed in SQL so no financial arithmetic happens in the UI.
  d.result_deducted_minor::text as result_deducted_cost_minor_units,
  d.evidence_evidenced_count as evidence_evidenced_count,
  d.evidence_subject_count as evidence_subject_count,
  current_date as as_of
from derived d;

comment on view public.sector_management_result_read is
  'H1 sector roll-up of the qualified management operating result (ADR 0034). '
  'Groups by (sector, currency) so every summed project shares one currency, and '
  'recomputes cost-classification status from the summed buckets so a sector is '
  'COMPLETE only when every contributing project is classified. '
  'result_deducted_cost_minor_units is the cost the result arithmetic actually '
  'subtracts, which is NOT the same as the attributed classification bucket: a '
  'Real Estate SELLING cost is classified once but deducted zero times, because '
  'its economic effect is already inside the sector realized disposal result. '
  'The result amount exists only inside management_result; there is no bare scalar.';

grant select on public.sector_management_result_read to authenticated;
