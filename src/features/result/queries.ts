import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

// H1 qualified-result read models (ADR 0034).
//
// Rows carry a `management_result` jsonb object and never a bare result scalar.
// Do not read the amount out of it here: parse it with
// `src/features/result/qualified-result.ts`, which is the only sanctioned path
// to displayable amount text.

export type ProjectOperatingResultRow = {
  project_id: string;
  organization_id: string;
  sector: 'REAL_ESTATE' | 'AGRICULTURE' | 'LIVESTOCK';
  currency: string;
  result_basis: string;
  cost_classification_status: string;
  evidence_status: string;
  /** The qualified result object. Parse it; do not destructure it. */
  management_result: unknown;
  sale_revenue_minor_units: string;
  rental_revenue_minor_units: string;
  cogs_derecognized_minor_units: string;
  realized_disposal_minor_units: string;
  selling_costs_minor_units: string;
  attributed_operating_cost_minor_units: string;
  selling_cost_attributed_minor_units: string;
  project_overhead_minor_units: string;
  excluded_from_result_minor_units: string;
  unclassified_eligible_minor_units: string;
  expense_outside_classification_scope_minor_units: string;
  /** DEDUCTION: cost actually subtracted in the result arithmetic. Distinct from
   *  the attributed classification bucket — a Real Estate SELLING cost is
   *  classified once but deducted zero times, because its economic effect is
   *  already inside the sector realized disposal result. */
  result_deducted_cost_minor_units: string;
  evidence_evidenced_count: number;
  evidence_subject_count: number;
  as_of: string;
};

export type SectorManagementResultRow = {
  organization_id: string;
  sector: 'REAL_ESTATE' | 'AGRICULTURE' | 'LIVESTOCK';
  currency: string;
  project_count: number;
  result_basis: string;
  cost_classification_status: string;
  evidence_status: string;
  management_result: unknown;
  sale_revenue_minor_units: string;
  rental_revenue_minor_units: string;
  realized_disposal_minor_units: string;
  selling_costs_minor_units: string;
  attributed_operating_cost_minor_units: string;
  selling_cost_attributed_minor_units: string;
  project_overhead_minor_units: string;
  excluded_from_result_minor_units: string;
  unclassified_eligible_minor_units: string;
  expense_outside_classification_scope_minor_units: string;
  /** DEDUCTION: cost actually subtracted in the result arithmetic, summed from
   *  the project rows. Not the same as the attributed classification bucket.
   *  Summed in SQL so no financial arithmetic happens in the UI. */
  result_deducted_cost_minor_units: string;
  evidence_evidenced_count: number;
  evidence_subject_count: number;
  as_of: string;
};

/**
 * One currency's management operating result for one project.
 *
 * `project_result_by_currency_read` groups the authoritative facts by the
 * currency OF THE FACTS. `currency` here is therefore the currency of the
 * posted revenue and cost, never `investment_projects.reporting_currency` — the
 * two are not guaranteed to agree, and the SQL contract does not assume they do.
 */
export type ProjectResultByCurrencyRow = {
  project_id: string;
  organization_id: string;
  sector: string;
  currency: string;
  result_basis: string;
  cost_classification_status: string;
  evidence_status: string;
  management_result: unknown;
  sale_revenue_minor_units: string;
  rental_revenue_minor_units: string;
  cogs_derecognized_minor_units: string;
  realized_disposal_minor_units: string;
  selling_costs_minor_units: string;
  /** CLASSIFICATION: cost classified as attributed to an operating unit. */
  attributed_operating_cost_minor_units: string;
  /** Portion of attributed cost that is SELLING: classified once, deducted zero
   *  times, because its effect is already netted inside the disposal result. */
  selling_cost_attributed_minor_units: string;
  project_overhead_minor_units: string;
  excluded_from_result_minor_units: string;
  unclassified_eligible_minor_units: string;
  expense_outside_classification_scope_minor_units: string;
  /** The revenue term of the result identity, per currency. */
  result_revenue_minor_units: string;
  /** DEDUCTION: cost actually subtracted. Not the attributed bucket. */
  result_deducted_cost_minor_units: string;
  evidence_evidenced_count: number;
  evidence_subject_count: number;
  as_of: string;
};

const PROJECT_RESULT_COLUMNS =
  'project_id,organization_id,sector,currency,result_basis,cost_classification_status,' +
  'evidence_status,management_result,sale_revenue_minor_units,rental_revenue_minor_units,' +
  'cogs_derecognized_minor_units,realized_disposal_minor_units,selling_costs_minor_units,' +
  'attributed_operating_cost_minor_units,selling_cost_attributed_minor_units,' +
  'project_overhead_minor_units,excluded_from_result_minor_units,' +
  'unclassified_eligible_minor_units,expense_outside_classification_scope_minor_units,' +
  'result_deducted_cost_minor_units,' +
  'evidence_evidenced_count,evidence_subject_count,as_of';

const PROJECT_RESULT_BY_CURRENCY_COLUMNS =
  'project_id,organization_id,sector,currency,result_basis,cost_classification_status,' +
  'evidence_status,management_result,sale_revenue_minor_units,rental_revenue_minor_units,' +
  'cogs_derecognized_minor_units,realized_disposal_minor_units,selling_costs_minor_units,' +
  'attributed_operating_cost_minor_units,selling_cost_attributed_minor_units,' +
  'project_overhead_minor_units,excluded_from_result_minor_units,' +
  'unclassified_eligible_minor_units,expense_outside_classification_scope_minor_units,' +
  'result_revenue_minor_units,result_deducted_cost_minor_units,' +
  'evidence_evidenced_count,evidence_subject_count,as_of';

const SECTOR_RESULT_COLUMNS =
  'organization_id,sector,currency,project_count,result_basis,cost_classification_status,' +
  'evidence_status,management_result,sale_revenue_minor_units,rental_revenue_minor_units,' +
  'realized_disposal_minor_units,selling_costs_minor_units,' +
  'attributed_operating_cost_minor_units,selling_cost_attributed_minor_units,' +
  'project_overhead_minor_units,excluded_from_result_minor_units,' +
  'unclassified_eligible_minor_units,expense_outside_classification_scope_minor_units,' +
  'result_deducted_cost_minor_units,' +
  'evidence_evidenced_count,evidence_subject_count,as_of';

export async function getProjectResultByCurrency(
  projectId: string,
): Promise<ProjectResultByCurrencyRow[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('project_result_by_currency_read')
    .select(PROJECT_RESULT_BY_CURRENCY_COLUMNS)
    .eq('project_id', projectId)
    .order('currency');
  if (error) throwOperatorQuery(error);
  return (data ?? []) as unknown as ProjectResultByCurrencyRow[];
}

export async function getProjectOperatingResult(
  organizationId: string,
  projectId: string,
): Promise<ProjectOperatingResultRow | null> {
  const s = await createClient();
  const { data, error } = await s
    .from('project_operating_result_read')
    .select(PROJECT_RESULT_COLUMNS)
    .eq('organization_id', organizationId)
    .eq('project_id', projectId)
    .maybeSingle();
  if (error) throwOperatorQuery(error);
  return (data ?? null) as unknown as ProjectOperatingResultRow | null;
}

export async function getSectorManagementResult(
  organizationId: string,
): Promise<SectorManagementResultRow[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('sector_management_result_read')
    .select(SECTOR_RESULT_COLUMNS)
    .eq('organization_id', organizationId)
    .order('sector');
  if (error) throwOperatorQuery(error);
  return (data ?? []) as unknown as SectorManagementResultRow[];
}
