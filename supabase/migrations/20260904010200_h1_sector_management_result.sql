-- H1 — Sector management result roll-up for the executive Home (ADR 0034 §2).
--
-- Home compares sectors, and that comparison is the defect being removed: today
-- `sector_performance_read.realized_result_minor_units` is net of cost of sale for
-- Real Estate but gross revenue for Agriculture and Livestock, so a crop project
-- with unattributed cost sits in the same column as a property disposal and looks
-- better. This view is the replacement.
--
-- It is NOT a new basis. It is the sector-owned per-project basis, aggregated:
--
--   * grouping is (sector, currency), so every project summed in a row shares one
--     currency — no implicit conversion, no floating point, no mixed-currency total;
--   * the cost-classification status is recomputed from the SUMMED buckets, so a
--     sector is COMPLETE only when every project contributing to it is classified;
--   * `basis` is min(basis). This is safe by construction rather than by defence:
--     result_basis is a pure function of sector, the group key is sector, and
--     investment_projects.sector is constrained to the three known sectors. There
--     is therefore at most one basis per group, and gate 100 asserts it rather
--     than this view branching on an impossible state.
--
-- The output carries the same qualified object as the project view. There is no
-- bare sector result scalar here either.

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
  -- Attributed cost plus declared overhead: exactly the cost the result deducts.
  -- Summed here rather than in the UI so no financial arithmetic happens outside
  -- the database.
  (d.attributed_minor + d.overhead_minor)::text as classified_deducted_minor_units,
  d.evidence_evidenced_count as evidence_evidenced_count,
  d.evidence_subject_count as evidence_subject_count,
  current_date as as_of
from derived d;

comment on view public.sector_management_result_read is
  'H1 sector roll-up of the qualified management operating result (ADR 0034). '
  'Groups by (sector, currency) so every summed project shares one currency, and '
  'recomputes cost-classification status from the summed buckets so a sector is '
  'COMPLETE only when every contributing project is classified. Replaces '
  'sector_performance_read.realized_result_minor_units, which was net of cost of '
  'sale for Real Estate but gross revenue for Agriculture and Livestock. The '
  'result amount exists only inside management_result; there is no bare scalar.';

grant select on public.sector_management_result_read to authenticated;
