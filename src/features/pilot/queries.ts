import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

// GF-009 / S7 read models. Money always arrives as text (bigint transported
// exactly through the *_read views) and free text arrives already neutralized
// against spreadsheet formula injection.

export type OpeningImport = {
  import_id: string;
  organization_id: string;
  project_id: string;
  schema_version: string;
  source_file_name: string;
  source_file_checksum: string;
  reporting_currency: string;
  status: 'DRAFT' | 'VALIDATED' | 'READY_FOR_APPROVAL' | 'APPROVED' | 'POSTED' | 'REJECTED' | 'FAILED';
  submitted_row_count: number;
  accepted_row_count: number;
  rejected_row_count: number;
  declared_debit_total_minor_units: string;
  declared_credit_total_minor_units: string;
  computed_debit_total_minor_units: string;
  computed_credit_total_minor_units: string;
  debit_variance_minor_units: string;
  credit_variance_minor_units: string;
  control_totals_match: boolean;
  mapping_summary: Record<string, { accepted_rows: number; debit_minor_units: string; credit_minor_units: string }>;
  rejection_summary: { row_number: number; reason: string }[];
  failure_reason: string | null;
  prepared_by: string;
  prepared_at: string;
  validated_at: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  approved_by: string | null;
  approved_at: string | null;
  posting_date: string | null;
  journal_batch_id: string | null;
  snapshot_content_hash: string | null;
  snapshot_captured_at: string | null;
  content_hash: string;
  is_reversed: boolean;
};

export type OpeningImportRow = {
  row_id: string;
  organization_id: string;
  project_id: string;
  import_id: string;
  row_number: number;
  mapping_code: string;
  mapping_label: string | null;
  account_role: string | null;
  party_id: string | null;
  party_legal_name: string | null;
  cash_account_id: string | null;
  debit_minor_units: string;
  credit_minor_units: string;
  description: string;
  status: 'ACCEPTED' | 'REJECTED';
  reject_reason: string | null;
  fingerprint: string;
};

export type OpeningMappingCode = {
  code: string;
  account_role: string;
  label_ar: string;
  natural_side: 'DEBIT' | 'CREDIT';
  requires_party: boolean;
  requires_cash_account: boolean;
};

export type ReconciliationCheckpoint = {
  checkpoint_id: string;
  organization_id: string;
  project_id: string;
  checkpoint_code: string;
  as_of_date: string;
  reporting_currency: string;
  external_value_minor_units: string;
  terranex_value_minor_units: string;
  variance_minor_units: string;
  is_zero_variance: boolean;
  external_source_reference: string;
  external_evidence_reference: string;
  status: 'MATCHED' | 'VARIANCE' | 'SIGNED_OFF';
  prepared_by: string;
  prepared_at: string;
  signed_off_by: string | null;
  signed_off_at: string | null;
  sign_off_evidence_reference: string | null;
  content_hash: string;
  open_exception_count: number;
  max_open_severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL' | null;
};

export type ReconciliationException = {
  exception_id: string;
  organization_id: string;
  project_id: string;
  checkpoint_id: string;
  checkpoint_code: string;
  as_of_date: string;
  severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  status: 'OPEN' | 'RESOLVED';
  owner_user_id: string;
  variance_minor_units: string;
  detail: string;
  resolution: string | null;
  resolution_evidence_reference: string | null;
  resolved_by: string | null;
  resolved_at: string | null;
  raised_at: string;
};

export type UatTask = {
  task_id: string;
  organization_id: string;
  project_id: string;
  task_code: string;
  title: string;
  expected_outcome: string;
  status: 'PENDING' | 'EXECUTED' | 'ACCEPTED' | 'REJECTED';
  executed_by: string | null;
  executed_at: string | null;
  execution_evidence_reference: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  acceptance_evidence_reference: string | null;
  notes: string | null;
  rejection_reason: string | null;
  created_by: string;
  created_at: string;
};

export type PilotRehearsal = {
  rehearsal_id: string;
  organization_id: string;
  project_id: string;
  rehearsal_code: 'END_TO_END_CYCLE' | 'BACKUP_RESTORE' | 'ACCESS_REVOCATION';
  result: 'PASS' | 'FAIL';
  detail: string;
  evidence: Record<string, unknown>;
  executed_by: string;
  executed_at: string;
};

export type PilotAcceptanceReport = {
  project_id: string;
  organization_id: string;
  reporting_currency: string;
  posted_opening_imports: number;
  opening_import_rejected_rows: number;
  opening_control_totals_match: boolean | null;
  reconciliation_checkpoints: number;
  reconciliation_non_zero_variances: number;
  reconciliation_max_abs_variance_minor_units: string;
  unresolved_exceptions: number;
  unresolved_critical_exceptions: number;
  unreconciled_bank_statement_lines: number;
  unbalanced_journal_batches: number;
  end_to_end_result: 'PASS' | 'FAIL' | null;
  backup_restore_result: 'PASS' | 'FAIL' | null;
  access_revocation_result: 'PASS' | 'FAIL' | null;
  uat_total_tasks: number;
  uat_accepted_tasks: number;
  uat_rejected_tasks: number;
  human_uat_status: 'NOT_STARTED' | 'PENDING' | 'ACCEPTED' | 'REJECTED';
};

export type MembershipAccess = {
  membership_id: string;
  organization_id: string;
  user_id: string;
  role: 'OWNER' | 'MEMBER';
  status: 'ACTIVE' | 'INACTIVE';
  has_access: boolean;
  created_at: string;
};

async function many<T>(view: string, columns: string, projectId: string, orderColumn?: string) {
  const s = await createClient();
  let query = s.from(view).select(columns).eq('project_id', projectId);
  if (orderColumn) query = query.order(orderColumn, { ascending: false });
  const { data, error } = await query;
  if (error) throwOperatorQuery(error);
  return data as unknown as T[];
}

export const getOpeningImports = (projectId: string) => many<OpeningImport>(
  's7_opening_imports_read',
  'import_id,organization_id,project_id,schema_version,source_file_name,source_file_checksum,reporting_currency,status,submitted_row_count,accepted_row_count,rejected_row_count,declared_debit_total_minor_units,declared_credit_total_minor_units,computed_debit_total_minor_units,computed_credit_total_minor_units,debit_variance_minor_units,credit_variance_minor_units,control_totals_match,mapping_summary,rejection_summary,failure_reason,prepared_by,prepared_at,validated_at,reviewed_by,reviewed_at,approved_by,approved_at,posting_date,journal_batch_id,snapshot_content_hash,snapshot_captured_at,content_hash,is_reversed',
  projectId,
  'prepared_at',
);

export async function getOpeningImportRows(importIds: string[]): Promise<OpeningImportRow[]> {
  if (importIds.length === 0) return [];
  const s = await createClient();
  const { data, error } = await s.from('s7_opening_import_rows_read')
    .select('row_id,organization_id,project_id,import_id,row_number,mapping_code,mapping_label,account_role,party_id,party_legal_name,cash_account_id,debit_minor_units,credit_minor_units,description,status,reject_reason,fingerprint')
    .in('import_id', importIds)
    .order('row_number');
  if (error) throwOperatorQuery(error);
  return data as unknown as OpeningImportRow[];
}

export async function getOpeningMappingCodes(): Promise<OpeningMappingCode[]> {
  const s = await createClient();
  const { data, error } = await s.from('s7_opening_mapping_codes_read')
    .select('code,account_role,label_ar,natural_side,requires_party,requires_cash_account')
    .order('code');
  if (error) throwOperatorQuery(error);
  return data as unknown as OpeningMappingCode[];
}

export const getReconciliationCheckpoints = (projectId: string) => many<ReconciliationCheckpoint>(
  's7_reconciliation_checkpoints_read',
  'checkpoint_id,organization_id,project_id,checkpoint_code,as_of_date,reporting_currency,external_value_minor_units,terranex_value_minor_units,variance_minor_units,is_zero_variance,external_source_reference,external_evidence_reference,status,prepared_by,prepared_at,signed_off_by,signed_off_at,sign_off_evidence_reference,content_hash,open_exception_count,max_open_severity',
  projectId,
  'as_of_date',
);

export const getReconciliationExceptions = (projectId: string) => many<ReconciliationException>(
  's7_reconciliation_exceptions_read',
  'exception_id,organization_id,project_id,checkpoint_id,checkpoint_code,as_of_date,severity,status,owner_user_id,variance_minor_units,detail,resolution,resolution_evidence_reference,resolved_by,resolved_at,raised_at',
  projectId,
  'raised_at',
);

export const getUatTasks = (projectId: string) => many<UatTask>(
  's7_uat_tasks_read',
  'task_id,organization_id,project_id,task_code,title,expected_outcome,status,executed_by,executed_at,execution_evidence_reference,reviewed_by,reviewed_at,acceptance_evidence_reference,notes,rejection_reason,created_by,created_at',
  projectId,
  'created_at',
);

export const getPilotRehearsals = (projectId: string) => many<PilotRehearsal>(
  's7_pilot_rehearsals_read',
  'rehearsal_id,organization_id,project_id,rehearsal_code,result,detail,evidence,executed_by,executed_at',
  projectId,
  'executed_at',
);

export async function getPilotAcceptanceReport(projectId: string): Promise<PilotAcceptanceReport | null> {
  const s = await createClient();
  const { data, error } = await s.from('s7_pilot_acceptance_report_read')
    .select('project_id,organization_id,reporting_currency,posted_opening_imports,opening_import_rejected_rows,opening_control_totals_match,reconciliation_checkpoints,reconciliation_non_zero_variances,reconciliation_max_abs_variance_minor_units,unresolved_exceptions,unresolved_critical_exceptions,unreconciled_bank_statement_lines,unbalanced_journal_batches,end_to_end_result,backup_restore_result,access_revocation_result,uat_total_tasks,uat_accepted_tasks,uat_rejected_tasks,human_uat_status')
    .eq('project_id', projectId)
    .maybeSingle();
  if (error) throwOperatorQuery(error);
  return data as PilotAcceptanceReport | null;
}

export async function getMembershipAccess(organizationId: string): Promise<MembershipAccess[]> {
  const s = await createClient();
  const { data, error } = await s.from('s7_membership_access_read')
    .select('membership_id,organization_id,user_id,role,status,has_access,created_at')
    .eq('organization_id', organizationId)
    .order('created_at');
  if (error) throwOperatorQuery(error);
  return data as unknown as MembershipAccess[];
}
