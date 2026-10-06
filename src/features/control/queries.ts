import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

// F3–F10 read models. Money arrives as text (bigint transported exactly
// through the *_read views) and is formatted with the shared money module.

export type ObligationDue = {
  obligation_id: string;
  organization_id: string;
  project_id: string;
  party_id: string;
  description: string;
  amount_minor_units: string;
  currency: string;
  transaction_date: string;
  cost_treatment: string;
  status: string;
  terms_id: string | null;
  terms_type: string | null;
  due_date: string | null;
  outstanding_minor_units: string;
  is_reversed: boolean;
  aging_bucket: string;
  days_overdue: number | null;
  is_disputed: boolean;
  payment_blocked: boolean;
  open_dispute_id: string | null;
  retention_minor_units: string;
  retention_released_minor_units: string;
  retention_remaining_minor_units: string;
  releasable_outstanding_minor_units: string;
};

export type AgingRow = {
  organization_id: string;
  project_id: string;
  currency: string;
  aging_bucket: string;
  obligation_count: number;
  overdue_outstanding_minor_units: string;
  total_outstanding_minor_units: string;
  retention_held_minor_units: string;
};

export type ProjectMilestone = {
  milestone_id: string;
  organization_id: string;
  project_id: string;
  code: string;
  label_ar: string;
  planned_date: string | null;
  status: string;
  achieved_date: string | null;
  evidence_reference: string | null;
  linked_schedule_lines: number;
};

export type BudgetRow = {
  budget_id: string;
  organization_id: string;
  project_id: string;
  period_start: string;
  period_end: string;
  budget_type: string;
  version: number;
  status: string;
  currency: string;
  description: string;
  evidence_reference: string | null;
  prepared_by: string;
  approved_by: string | null;
  approved_at: string | null;
  superseded_by_budget_id: string | null;
  total_budget_minor_units: string;
};

export type BudgetConsumption = {
  budget_id: string;
  organization_id: string;
  project_id: string;
  period_start: string;
  period_end: string;
  budget_type: string;
  version: number;
  status: string;
  currency: string;
  description: string;
  budget_line_id: string;
  cost_treatment: string;
  budget_minor_units: string;
  committed_obligations_minor_units: string;
  paid_minor_units: string;
  approved_exception_minor_units: string;
  authorization_remaining_minor_units: string;
  effective_remaining_minor_units: string;
  forecast_final_minor_units: string;
  actual_minor_units: string;
  approved_forecast_remainder_minor_units: string;
  fac_minor_units: string;
};

export type BudgetFac = {
  budget_id: string;
  organization_id: string;
  project_id: string;
  period_start: string;
  period_end: string;
  budget_type: string;
  version: number;
  currency: string;
  description: string;
  budget_total_minor_units: string;
  approved_exception_total_minor_units: string;
  actual_total_minor_units: string;
  open_commitment_minor_units: string;
  approved_forecast_remainder_minor_units: string;
  fac_minor_units: string;
};

export type ApprovalException = {
  exception_id: string;
  organization_id: string;
  project_id: string;
  domain: string;
  subject_type: string;
  subject_id: string | null;
  exception_kind: string;
  amount_minor_units: string | null;
  currency: string | null;
  status: string;
  opened_by: string;
  opened_at: string;
  decided_by: string | null;
  decided_at: string | null;
  reason: string;
  severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  owner_id: string | null;
  due_date: string | null;
  replaces_exception_id: string | null;
};

export type ApprovalPolicy = {
  policy_id: string;
  organization_id: string;
  policy_domain: string;
  threshold_minor_units: string | null;
  currency: string | null;
  evidence_required: boolean;
  active: boolean;
};

export type IntegritySignal = {
  organization_id: string;
  project_id: string | null;
  signal_code: string;
  signal_label_ar: string;
  severity: 'CRITICAL' | 'WARNING' | 'INFO';
  subject_count: number;
  amount_minor_units: string | null;
  currency: string | null;
};

export type ProjectPosition = {
  project_id: string;
  organization_id: string;
  project_name: string;
  sector: string;
  currency: string;
  cash_balance_minor_units: string;
  receivable_open_minor_units: string;
  revenue_recognized_minor_units: string;
  cost_of_sale_minor_units: string;
  expense_posted_minor_units: string;
  wip_posted_minor_units: string;
  contributions_received_minor_units: string;
  payable_open_minor_units: string;
  paid_minor_units: string;
  retention_held_minor_units: string;
  retention_declared_minor_units: string;
  disputed_obligations: number;
  overdue_obligations: number;
  overdue_outstanding_minor_units: string;
};

export type PortfolioRollup = {
  portfolio_id: string;
  organization_id: string;
  portfolio_name: string;
  portfolio_status: string;
  currency: string;
  org_reporting_currency: string | null;
  project_count: number;
  cash_balance_minor_units: string;
  receivable_open_minor_units: string;
  revenue_recognized_minor_units: string;
  cost_of_sale_minor_units: string;
  expense_posted_minor_units: string;
  wip_posted_minor_units: string;
  contributions_received_minor_units: string;
  payable_open_minor_units: string;
  paid_minor_units: string;
  retention_held_minor_units: string;
  disputed_obligations: number;
  overdue_obligations: number;
  fx_status: string;
  converted_cash_balance_minor_units: string | null;
  converted_payable_open_minor_units: string | null;
  converted_paid_minor_units: string | null;
  open_commitment_minor_units: string;
  realized_result_minor_units: string;
  fac_minor_units: string;
  open_exception_count: number;
  sector_exposure: Record<string, { project_count: number; cash_balance_minor_units: string }> | null;
  cash_concentration_ratio: string | null;
};

export async function getObligationDue(projectId: string): Promise<ObligationDue[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('cost_obligation_due_read')
    .select('*')
    .eq('project_id', projectId)
    .order('transaction_date', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as ObligationDue[];
}

export async function getObligationAging(projectId: string): Promise<AgingRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('cost_obligation_aging_read')
    .select('*')
    .eq('project_id', projectId)
    .order('aging_bucket', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as AgingRow[];
}

export async function getProjectMilestones(projectId: string): Promise<ProjectMilestone[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('project_milestones_read')
    .select('*')
    .eq('project_id', projectId)
    .order('planned_date', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as ProjectMilestone[];
}

export async function getProjectBudgets(projectId: string): Promise<BudgetRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('project_budgets_read')
    .select('*')
    .eq('project_id', projectId)
    .order('period_start', { ascending: true })
    .order('version', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as BudgetRow[];
}

export async function getProjectBudgetFac(projectId: string): Promise<BudgetFac[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('project_budget_fac_read')
    .select('*')
    .eq('project_id', projectId)
    .order('period_start', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as BudgetFac[];
}

export async function getBudgetConsumption(projectId: string): Promise<BudgetConsumption[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('project_budget_consumption_read')
    .select('*')
    .eq('project_id', projectId);
  if (error) throwOperatorQuery(error);
  return (data ?? []) as BudgetConsumption[];
}

export async function getApprovalExceptions(projectId: string): Promise<ApprovalException[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('approval_exception_registry_read')
    .select('*')
    .eq('project_id', projectId)
    .order('opened_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as ApprovalException[];
}

export async function getApprovalPolicies(organizationId: string): Promise<ApprovalPolicy[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('approval_policies_read')
    .select('*')
    .eq('organization_id', organizationId)
    .order('policy_domain', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as ApprovalPolicy[];
}

export async function getIntegritySignals(organizationId: string): Promise<IntegritySignal[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('financial_integrity_signals_read')
    .select('*')
    .eq('organization_id', organizationId)
    .order('severity', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as IntegritySignal[];
}

/**
 * The project's official financial position — one row per project, by
 * construction.
 *
 * CARDINALITY IS GENUINE. In `project_financial_position_read` the driving
 * table is `investment_projects p` (primary key) and every CTE is joined with
 * `on <cte>.project_id = p.id and <cte>.currency = p.reporting_currency`, each
 * matching at most one row of its (project, currency) grouping. Filtering by
 * `project_id` therefore returns exactly one row, so `.maybeSingle()` is the
 * honest model here and must not be turned into an array to satisfy a rule.
 *
 * CURRENCY SCOPE IS THE REAL LIMITATION. Those joins mean the view reports the
 * REPORTING-CURRENCY SLICE of the project and silently excludes facts posted in
 * any other currency; the CTEs' per-currency grouping is discarded by the join,
 * and `coalesce(...,0)` then renders the excluded amounts as zero. This is the
 * same shape as `project_operating_result_read`, and it is a recorded defect in
 * the SQL contract — not something a caller can repair, because re-deriving the
 * missing facts in React is exactly what the architecture forbids. The
 * per-currency contracts (`project_cash_by_currency_read`,
 * `project_capital_by_currency_read`, `project_result_by_currency_read`) are the
 * authoritative per-currency answers; this view answers the narrower
 * reporting-currency question. Callers must not present it as complete.
 */
export async function getProjectPosition(projectId: string): Promise<ProjectPosition | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('project_financial_position_read')
    .select('*')
    .eq('project_id', projectId)
    .maybeSingle();
  if (error) throwOperatorQuery(error);
  return (data ?? null) as ProjectPosition | null;
}

export async function getPortfolioRollup(portfolioId: string): Promise<PortfolioRollup[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('portfolio_financial_rollup_read')
    .select('*')
    .eq('portfolio_id', portfolioId);
  if (error) throwOperatorQuery(error);
  return (data ?? []) as PortfolioRollup[];
}

export type ConsolidationRow = {
  organization_id: string;
  level: 'BY_CURRENCY' | 'CONSOLIDATED';
  currency: string | null;
  org_reporting_currency: string | null;
  project_count: number;
  cash_balance_minor_units: string | null;
  receivable_open_minor_units: string | null;
  revenue_recognized_minor_units: string | null;
  cost_of_sale_minor_units: string | null;
  expense_posted_minor_units: string | null;
  wip_posted_minor_units: string | null;
  contributions_received_minor_units: string | null;
  payable_open_minor_units: string | null;
  paid_minor_units: string | null;
  retention_held_minor_units: string | null;
  disputed_obligations: number;
  overdue_obligations: number;
  fx_status: string;
  converted_cash_balance_minor_units: string | null;
  converted_payable_open_minor_units: string | null;
  converted_paid_minor_units: string | null;
};

export type FxSnapshot = {
  snapshot_id: string;
  organization_id: string;
  base_currency: string;
  quote_currency: string;
  rate_numerator: string;
  rate_denominator: string;
  rate_date: string;
  rate_source: string;
  provider_reference: string | null;
  captured_at: string;
  notes: string | null;
};

export type FxConversionLog = {
  conversion_id: string;
  organization_id: string;
  project_id: string | null;
  source_amount_minor_units: string;
  source_currency: string;
  target_currency: string;
  rate_snapshot_id: string;
  converted_amount_minor_units: string;
  conversion_date: string;
  purpose: string;
  rate_numerator: string;
  rate_denominator: string;
  snapshot_rate_date: string;
  rate_source: string;
};

export type TaxTreatment = {
  tax_registry_id: string;
  organization_id: string;
  tax_domain: string;
  tax_name: string;
  applies_to: string;
  treatment_status: string;
  authority: string | null;
  effective_from: string;
  effective_to: string | null;
  status: string;
  notes: string;
};

export async function getFxSnapshots(organizationId: string): Promise<FxSnapshot[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('fx_rate_snapshots_read')
    .select('*')
    .eq('organization_id', organizationId)
    .order('rate_date', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as FxSnapshot[];
}

export async function getFxConversionLog(organizationId: string): Promise<FxConversionLog[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('fx_conversion_log_read')
    .select('*')
    .eq('organization_id', organizationId)
    .order('conversion_date', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as FxConversionLog[];
}

export async function getTaxRegistry(organizationId: string): Promise<TaxTreatment[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('tax_registry_read')
    .select('*')
    .eq('organization_id', organizationId)
    .order('tax_domain', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as TaxTreatment[];
}

export async function getOrganizationReportingCurrency(
  organizationId: string,
): Promise<string | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('organizations')
    .select('reporting_currency')
    .eq('id', organizationId)
    .maybeSingle();
  if (error) throwOperatorQuery(error);
  return (data?.reporting_currency as string | null) ?? null;
}

export async function getOrganizationConsolidation(
  organizationId: string,
): Promise<ConsolidationRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('organization_financial_consolidation_read')
    .select('*')
    .eq('organization_id', organizationId)
    .order('level', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as ConsolidationRow[];
}
