import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type AllocationRuleSet = {
  rule_set_id: string;
  organization_id: string;
  project_id: string;
  governing_version_id: string;
  policy: 'PRO_RATA' | 'FIXED_SHARES';
  common_denominator: string;
  content_hash: string;
  basis_evidence_reference: string;
  effective_from: string;
  effective_to: string | null;
  created_by: string;
  created_at: string;
  participant_count: number;
};

export type AllocationRun = {
  allocation_run_id: string;
  organization_id: string;
  project_id: string;
  source_period_id: string;
  close_run_id: string;
  close_snapshot_id: string;
  snapshot_content_hash: string;
  snapshot_captured_at: string;
  governing_version_id: string;
  rule_set_id: string;
  policy: 'PRO_RATA' | 'FIXED_SHARES';
  algorithm_version: string;
  reporting_currency: string;
  source_category: 'REALIZED_RESULT';
  source_amount_minor_units: string;
  status: 'PREPARED' | 'APPROVED';
  content_hash: string;
  prepared_by: string;
  prepared_at: string;
  approved_by: string | null;
  approved_at: string | null;
  posting_date: string | null;
  journal_batch_id: string | null;
  prior_run_id: string | null;
  allocated_total_minor_units: string;
  line_count: number;
  is_reversed: boolean;
};

export type AllocationLine = {
  allocation_line_id: string;
  organization_id: string;
  project_id: string;
  run_id: string;
  participant_party_id: string;
  legal_name: string;
  weight_numerator: string;
  weight_denominator: string;
  exact_floor_minor_units: string;
  remainder_numerator: string;
  rounding_award_minor_units: number;
  allocated_minor_units: string;
  currency: string;
};

export type Distribution = {
  distribution_id: string;
  organization_id: string;
  project_id: string;
  allocation_run_id: string;
  participant_party_id: string;
  legal_name: string;
  requested_amount_minor_units: string;
  approved_amount_minor_units: string | null;
  currency: string;
  evidence_reference: string;
  status: 'PREPARED' | 'APPROVED';
  prepared_by: string;
  prepared_at: string;
  approved_by: string | null;
  approved_at: string | null;
  approval_posting_date: string | null;
  approval_journal_batch_id: string | null;
  paid_minor_units: string;
  outstanding_minor_units: string;
  is_approval_reversed: boolean;
  settlement_status: 'PREPARED' | 'APPROVED' | 'PARTIALLY_PAID' | 'PAID' | 'REVERSED';
};

/**
 * One currency's distribution capacity.
 *
 * `s5_distribution_capacity_read` groups `journal_lines` by
 * `(organization_id, project_id, currency)`, so it returns one row per
 * project+currency. The reader used to call `.maybeSingle()` against it, which
 * makes PostgREST answer `406 PGRST116` as soon as a project holds a second
 * currency — the same invalid singleton that was removed from the project
 * position reader. A capacity figure is only meaningful with the currency it is
 * stated in, so the grain is kept and no total across currencies is exposed.
 */
export type DistributionCapacity = {
  organization_id: string;
  project_id: string;
  currency: string;
  cash_minor_units: string;
  supplier_payable_minor_units: string;
  distribution_payable_minor_units: string;
  technical_capacity_bridge_minor_units: string;
};

export type PartnerCapitalStatement = {
  organization_id: string;
  project_id: string;
  participant_party_id: string;
  legal_name: string;
  currency: string;
  opening_capital_minor_units: string;
  contributions_minor_units: string;
  allocated_income_minor_units: string;
  allocated_loss_minor_units: string;
  approved_distributions_minor_units: string;
  paid_distributions_minor_units: string;
  closing_capital_minor_units: string;
};

async function many<T>(view: string, columns: string, projectId: string, orderColumn?: string) {
  const s = await createClient();
  let query = s.from(view).select(columns).eq('project_id', projectId);
  if (orderColumn) query = query.order(orderColumn, { ascending: false });
  const { data, error } = await query;
  if (error) throwOperatorQuery(error);
  return data as unknown as T[];
}

export const getAllocationRuleSets = (projectId: string) => many<AllocationRuleSet>(
  's5_rule_sets_read',
  'rule_set_id,organization_id,project_id,governing_version_id,policy,common_denominator,content_hash,basis_evidence_reference,effective_from,effective_to,created_by,created_at,participant_count',
  projectId,
  'created_at',
);

export const getAllocationRuns = (projectId: string) => many<AllocationRun>(
  's5_allocation_runs_read',
  'allocation_run_id,organization_id,project_id,source_period_id,close_run_id,close_snapshot_id,snapshot_content_hash,snapshot_captured_at,governing_version_id,rule_set_id,policy,algorithm_version,reporting_currency,source_category,source_amount_minor_units,status,content_hash,prepared_by,prepared_at,approved_by,approved_at,posting_date,journal_batch_id,prior_run_id,allocated_total_minor_units,line_count,is_reversed',
  projectId,
  'prepared_at',
);

export async function getAllocationLines(runIds: string[]): Promise<AllocationLine[]> {
  if (runIds.length === 0) return [];
  const s = await createClient();
  const { data, error } = await s.from('s5_allocation_lines_read')
    .select('allocation_line_id,organization_id,project_id,run_id,participant_party_id,legal_name,weight_numerator,weight_denominator,exact_floor_minor_units,remainder_numerator,rounding_award_minor_units,allocated_minor_units,currency')
    .in('run_id', runIds)
    .order('legal_name');
  if (error) throwOperatorQuery(error);
  return data as unknown as AllocationLine[];
}

export const getDistributions = (projectId: string) => many<Distribution>(
  's5_distributions_read',
  'distribution_id,organization_id,project_id,allocation_run_id,participant_party_id,legal_name,requested_amount_minor_units,approved_amount_minor_units,currency,evidence_reference,status,prepared_by,prepared_at,approved_by,approved_at,approval_posting_date,approval_journal_batch_id,paid_minor_units,outstanding_minor_units,is_approval_reversed,settlement_status',
  projectId,
  'prepared_at',
);

export async function getDistributionCapacity(projectId: string): Promise<DistributionCapacity[]> {
  const s = await createClient();
  const { data, error } = await s.from('s5_distribution_capacity_read')
    .select('organization_id,project_id,currency,cash_minor_units,supplier_payable_minor_units,distribution_payable_minor_units,technical_capacity_bridge_minor_units')
    .eq('project_id', projectId)
    .order('currency');
  if (error) throwOperatorQuery(error);
  return (data ?? []) as DistributionCapacity[];
}

export const getPartnerCapitalStatement = (projectId: string) => many<PartnerCapitalStatement>(
  's5_partner_capital_statement_read',
  'organization_id,project_id,participant_party_id,legal_name,currency,opening_capital_minor_units,contributions_minor_units,allocated_income_minor_units,allocated_loss_minor_units,approved_distributions_minor_units,paid_distributions_minor_units,closing_capital_minor_units',
  projectId,
  'legal_name',
);
