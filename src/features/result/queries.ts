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
  /** Attributed cost + declared overhead: exactly what the result deducts.
   *  Summed in SQL so no financial arithmetic happens in the UI. */
  classified_deducted_minor_units: string;
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
  'evidence_evidenced_count,evidence_subject_count,as_of';

const SECTOR_RESULT_COLUMNS =
  'organization_id,sector,currency,project_count,result_basis,cost_classification_status,' +
  'evidence_status,management_result,sale_revenue_minor_units,rental_revenue_minor_units,' +
  'realized_disposal_minor_units,selling_costs_minor_units,' +
  'attributed_operating_cost_minor_units,selling_cost_attributed_minor_units,' +
  'project_overhead_minor_units,excluded_from_result_minor_units,' +
  'unclassified_eligible_minor_units,expense_outside_classification_scope_minor_units,' +
  'classified_deducted_minor_units,' +
  'evidence_evidenced_count,evidence_subject_count,as_of';

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
