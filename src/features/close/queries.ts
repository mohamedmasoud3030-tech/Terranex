import { createClient } from '@/shared/supabase/server';

export type AccountingPeriod = {
  period_id: string;
  organization_id: string;
  project_id: string;
  reporting_currency: string;
  start_date: string;
  end_date: string;
  status: 'OPEN' | 'CLOSED';
  version: number;
  supersedes_period_id: string | null;
  opened_at: string;
  opened_by: string;
  closed_at: string | null;
  closed_by: string | null;
  source_close_run_id: string | null;
  source_close_version: number | null;
  source_close_snapshot_id: string | null;
};

export type CloseRun = {
  close_run_id: string;
  organization_id: string;
  project_id: string;
  period_id: string;
  version: number;
  status: 'PREPARED' | 'APPROVED' | 'REJECTED';
  source_cutoff_date: string;
  generated_at: string;
  generated_by: string;
  reviewed_by: string | null;
  reviewed_at: string | null;
  approved_by: string | null;
  approved_at: string | null;
  approval_idempotency_key: string | null;
  notes: string | null;
  period_start_date: string;
  period_end_date: string;
  reporting_currency: string;
  supersedes_period_id: string | null;
  snapshot_id: string | null;
  snapshot_content_hash: string | null;
  snapshot_captured_at: string | null;
  passing_gates: number;
  failing_gates: number;
  exception_gates: number;
  not_applicable_gates: number;
};

export type CloseRunGate = {
  gate_id: string;
  organization_id: string;
  close_run_id: string;
  gate_code:
    | 'JOURNAL_BATCHES_BALANCED'
    | 'BANK_RECONCILIATION_COVERAGE'
    | 'SUSPENSE_CONTROL_ACCOUNTS'
    | 'RECEIVABLE_PAYABLE_AGING'
    | 'ASSET_SECTOR_ROLLFORWARDS'
    | 'EVIDENCE_AND_APPROVALS'
    | 'POSTING_CURRENCY_RULES'
    | 'SECTOR_CUT_OFF'
    | 'PARTNER_CAPITAL_ROLLFORWARD'
    | 'CLOSE_REPORT_AND_EXCEPTIONS';
  result: 'PASS' | 'FAIL' | 'APPROVED_EXCEPTION' | 'NOT_APPLICABLE';
  detail: string;
  evidence: Record<string, unknown>;
  evaluated_at: string;
  exception_id: string | null;
  exception_status: 'PENDING' | 'APPROVED' | 'REJECTED' | null;
  exception_reason: string | null;
  exception_evidence_reference: string | null;
  exception_materiality_comment: string | null;
  exception_approved_by: string | null;
  exception_approved_at: string | null;
};

export type CloseRunException = {
  exception_id: string;
  organization_id: string;
  close_run_id: string;
  gate_code: string;
  reason: string;
  evidence_reference: string;
  materiality_comment: string | null;
  requested_by: string;
  requested_at: string;
  approved_by: string | null;
  approved_at: string | null;
  status: 'PENDING' | 'APPROVED' | 'REJECTED';
  project_id: string;
  period_id: string;
};

export type CloseRunSnapshot = {
  snapshot_id: string;
  organization_id: string;
  close_run_id: string;
  project_id: string;
  period_id: string;
  content_hash: string;
  totals: {
    project_id?: string;
    period_id?: string;
    currency?: string;
    cash_minor_units?: string;
    committed_capital_minor_units?: string;
    called_minor_units?: string;
    contributed_minor_units?: string;
    receivable_minor_units?: string;
    recognized_revenue_minor_units?: string;
    carrying_cost_derecognized_minor_units?: string;
    selling_costs_minor_units?: string;
    realized_result_minor_units?: string;
    collected_cash_minor_units?: string;
    outstanding_receivable_minor_units?: string;
  };
  captured_at: string;
  close_version: number;
  close_status: 'PREPARED' | 'APPROVED' | 'REJECTED';
  source_cutoff_date: string;
  approved_by: string | null;
  approved_at: string | null;
};

export type CorrectionRequest = {
  correction_id: string;
  organization_id: string;
  project_id: string;
  target_batch_id: string;
  target_source_type: string;
  target_transaction_date: string;
  source_period_id: string;
  correction_period_id: string;
  reason: string;
  evidence_reference: string;
  status: 'REQUESTED' | 'APPROVED' | 'REJECTED' | 'EXECUTED' | 'SUPERSEDED';
  requested_by: string;
  requested_at: string;
  reviewed_by: string | null;
  reviewed_at: string | null;
  reversal_batch_id: string | null;
  replacement_batch_id: string | null;
};

const GATE_LABEL_AR: Record<CloseRunGate['gate_code'], string> = {
  JOURNAL_BATCHES_BALANCED: 'توازن القيود اليومية',
  BANK_RECONCILIATION_COVERAGE: 'تغطية مطابقة البنك',
  SUSPENSE_CONTROL_ACCOUNTS: 'حسابات المعلقة والرقابة',
  RECEIVABLE_PAYABLE_AGING: 'تقادم الذمم',
  ASSET_SECTOR_ROLLFORWARDS: 'تطابق سجل الأصول/القطاع',
  EVIDENCE_AND_APPROVALS: 'الأدلة والاعتمادات',
  POSTING_CURRENCY_RULES: 'قواعد الترحيل والعملات',
  SECTOR_CUT_OFF: 'قطع الفترة القطاعي',
  PARTNER_CAPITAL_ROLLFORWARD: 'تطابق سجل رأس مال الشركاء',
  CLOSE_REPORT_AND_EXCEPTIONS: 'تقرير الإغلاق والاستثناءات',
};
export function gateLabelAr(code: string): string {
  return GATE_LABEL_AR[code as CloseRunGate['gate_code']] ?? code;
}

const RESULT_LABEL_AR: Record<CloseRunGate['result'], string> = {
  PASS: 'اجتياز',
  FAIL: 'فشل',
  APPROVED_EXCEPTION: 'استثناء معتمد',
  NOT_APPLICABLE: 'لا ينطبق',
};
export function gateResultLabelAr(result: string): string {
  return RESULT_LABEL_AR[result as CloseRunGate['result']] ?? result;
}

async function many<T>(view: string, columns: string, projectId: string, orderColumn?: string): Promise<T[]> {
  const s = await createClient();
  let query = s.from(view).select(columns).eq('project_id', projectId);
  if (orderColumn) query = query.order(orderColumn, { ascending: false });
  const { data, error } = await query;
  if (error) throw error;
  return data as unknown as T[];
}

export const getAccountingPeriods = (projectId: string) => many<AccountingPeriod>(
  'accounting_periods_read',
  'period_id,organization_id,project_id,reporting_currency,start_date,end_date,status,version,supersedes_period_id,opened_at,opened_by,closed_at,closed_by,source_close_run_id,source_close_version,source_close_snapshot_id',
  projectId,
  'opened_at',
);

export const getCloseRuns = (projectId: string) => many<CloseRun>(
  'close_runs_read',
  'close_run_id,organization_id,project_id,period_id,version,status,source_cutoff_date,generated_at,generated_by,reviewed_by,reviewed_at,approved_by,approved_at,approval_idempotency_key,notes,period_start_date,period_end_date,reporting_currency,supersedes_period_id,snapshot_id,snapshot_content_hash,snapshot_captured_at,passing_gates,failing_gates,exception_gates,not_applicable_gates',
  projectId,
  'generated_at',
);

export async function getCloseRunGates(closeRunId: string): Promise<CloseRunGate[]> {
  const s = await createClient();
  const { data, error } = await s.from('close_run_gates_read')
    .select('gate_id,organization_id,close_run_id,gate_code,result,detail,evidence,evaluated_at,exception_id,exception_status,exception_reason,exception_evidence_reference,exception_materiality_comment,exception_approved_by,exception_approved_at')
    .eq('close_run_id', closeRunId);
  if (error) throw error;
  return data as unknown as CloseRunGate[];
}

export async function getCloseRunExceptions(closeRunId: string): Promise<CloseRunException[]> {
  const s = await createClient();
  const { data, error } = await s.from('close_run_exceptions_read')
    .select('exception_id,organization_id,close_run_id,gate_code,reason,evidence_reference,materiality_comment,requested_by,requested_at,approved_by,approved_at,status,project_id,period_id')
    .eq('close_run_id', closeRunId);
  if (error) throw error;
  return data as unknown as CloseRunException[];
}

export const getCloseRunSnapshots = (projectId: string) => many<CloseRunSnapshot>(
  'close_run_snapshots_read',
  'snapshot_id,organization_id,close_run_id,project_id,period_id,content_hash,totals,captured_at,close_version,close_status,source_cutoff_date,approved_by,approved_at',
  projectId,
  'captured_at',
);

export const getCorrectionRequests = (projectId: string) => many<CorrectionRequest>(
  'correction_requests_read',
  'correction_id,organization_id,project_id,target_batch_id,target_source_type,target_transaction_date,source_period_id,correction_period_id,reason,evidence_reference,status,requested_by,requested_at,reviewed_by,reviewed_at,reversal_batch_id,replacement_batch_id',
  projectId,
  'requested_at',
);

export const GATE_CODES: CloseRunGate['gate_code'][] = [
  'JOURNAL_BATCHES_BALANCED',
  'BANK_RECONCILIATION_COVERAGE',
  'SUSPENSE_CONTROL_ACCOUNTS',
  'RECEIVABLE_PAYABLE_AGING',
  'ASSET_SECTOR_ROLLFORWARDS',
  'EVIDENCE_AND_APPROVALS',
  'POSTING_CURRENCY_RULES',
  'SECTOR_CUT_OFF',
  'PARTNER_CAPITAL_ROLLFORWARD',
  'CLOSE_REPORT_AND_EXCEPTIONS',
];
