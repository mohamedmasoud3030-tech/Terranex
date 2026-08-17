import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';
import { activePostedSourceIds } from './reversal';

// S2 read models. Money arrives as text (bigint transported exactly through
// the *_read views); it is formatted with the shared money module.

export type CashAccountPosition = {
  cash_account_id: string;
  organization_id: string;
  project_id: string;
  name: string;
  currency: string;
  balance_minor_units: string;
  last_posting_date: string | null;
};

export type ObligationPosition = {
  obligation_id: string;
  organization_id: string;
  project_id: string;
  party_id: string;
  description: string;
  amount_minor_units: string;
  currency: string;
  transaction_date: string;
  cost_treatment: 'EXPENSE' | 'CAPITALIZABLE_WIP';
  status: 'DRAFT' | 'AUTHORIZED';
  prepared_by: string;
  authorized_by: string | null;
  authorized_at: string | null;
  created_at: string;
  paid_minor_units: string;
  outstanding_minor_units: string;
  is_posted: boolean;
  is_reversed: boolean;
  authorization_batch_id: string | null;
  reversal_batch_id: string | null;
};

export type PaymentProposal = {
  payment_proposal_id: string;
  organization_id: string;
  project_id: string;
  obligation_id: string;
  cash_account_id: string;
  cash_account_name: string;
  amount_minor_units: string;
  currency: string;
  payment_date: string;
  status: 'PROPOSED' | 'APPROVED' | 'POSTED';
  prepared_by: string;
  prepared_at: string;
  approved_by: string | null;
  approved_at: string | null;
  project_payment_id: string | null;
  obligation_description: string;
};

export type PaymentStatus = {
  payment_id: string;
  organization_id: string;
  project_id: string;
  obligation_id: string;
  cash_account_id: string;
  amount_minor_units: string;
  currency: string;
  payment_date: string;
  paid_by: string;
  posted_at: string;
  batch_id: string;
  is_reversed: boolean;
  reversal_batch_id: string | null;
  is_reconciled: boolean;
  match_id: string | null;
};

export type BankStatementLineStatus = {
  line_id: string;
  organization_id: string;
  project_id: string;
  cash_account_id: string;
  import_id: string;
  provider_reference: string | null;
  transaction_date: string;
  amount_minor_units: string;
  currency: string;
  description: string;
  fingerprint: string;
  created_at: string;
  is_reconciled: boolean;
  match_id: string | null;
  matched_payment_id: string | null;
  matched_at: string | null;
};

export type JournalLedgerLine = {
  batch_id: string;
  organization_id: string;
  project_id: string;
  source_type: string;
  source_id: string;
  batch_transaction_date: string;
  posted_at: string;
  posted_by: string | null;
  reversal_of_batch_id: string | null;
  line_id: string;
  account_id: string;
  account_role: string;
  account_label: string;
  debit_minor_units: string;
  credit_minor_units: string;
  currency: string;
  cash_account_id: string | null;
  obligation_id: string | null;
  party_id: string | null;
  line_transaction_date: string;
};

export type AuditEvent = {
  id: string;
  event_type: string;
  entity_type: string;
  entity_id: string;
  payload: Record<string, unknown>;
  created_at: string;
};

export async function getCurrentMembership(organizationId: string): Promise<{ user_id: string; role: string } | null> {
  const s = await createClient();
  const { data, error } = await s
    .from('memberships')
    .select('user_id,role')
    .eq('organization_id', organizationId)
    .eq('status', 'ACTIVE')
    .maybeSingle();
  if (error) throwOperatorQuery(error);
  return data as { user_id: string; role: string } | null;
}

export async function getCashAccountPositions(projectId: string): Promise<CashAccountPosition[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('project_cash_position_read')
    .select('cash_account_id,organization_id,project_id,name,currency,balance_minor_units,last_posting_date')
    .eq('project_id', projectId)
    .order('name');
  if (error) throwOperatorQuery(error);
  return data as CashAccountPosition[];
}

export async function getObligationPositions(projectId: string): Promise<ObligationPosition[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('cost_obligation_position_read')
    .select('obligation_id,organization_id,project_id,party_id,description,amount_minor_units,currency,transaction_date,cost_treatment,status,prepared_by,authorized_by,authorized_at,created_at,paid_minor_units,outstanding_minor_units,is_posted,is_reversed,authorization_batch_id,reversal_batch_id')
    .eq('project_id', projectId)
    .order('created_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return data as ObligationPosition[];
}

export async function getPaymentProposals(projectId: string): Promise<PaymentProposal[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('cost_payment_proposals_read')
    .select('payment_proposal_id,organization_id,project_id,obligation_id,cash_account_id,cash_account_name,amount_minor_units,currency,payment_date,status,prepared_by,prepared_at,approved_by,approved_at,project_payment_id,obligation_description')
    .eq('project_id', projectId)
    .order('prepared_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return data as PaymentProposal[];
}

export async function getPayments(projectId: string): Promise<PaymentStatus[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('payment_status_read')
    .select('payment_id,organization_id,project_id,obligation_id,cash_account_id,amount_minor_units,currency,payment_date,paid_by,posted_at,batch_id,is_reversed,reversal_batch_id,is_reconciled,match_id')
    .eq('project_id', projectId)
    .order('posted_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return data as PaymentStatus[];
}

export async function getStatementLines(projectId: string): Promise<BankStatementLineStatus[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('bank_statement_line_status_read')
    .select('line_id,organization_id,project_id,cash_account_id,import_id,provider_reference,transaction_date,amount_minor_units,currency,description,fingerprint,created_at,is_reconciled,match_id,matched_payment_id,matched_at')
    .eq('project_id', projectId)
    .order('transaction_date', { ascending: false });
  if (error) throwOperatorQuery(error);
  return data as BankStatementLineStatus[];
}

export async function getLedgerForObligation(obligationId: string): Promise<JournalLedgerLine[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('journal_ledger_read')
    .select('batch_id,organization_id,project_id,source_type,source_id,batch_transaction_date,posted_at,posted_by,reversal_of_batch_id,line_id,account_id,account_role,account_label,debit_minor_units,credit_minor_units,currency,cash_account_id,obligation_id,party_id,line_transaction_date')
    .eq('obligation_id', obligationId)
    .order('posted_at');
  if (error) throwOperatorQuery(error);
  return data as JournalLedgerLine[];
}

export async function getLedgerForBatch(batchId: string): Promise<JournalLedgerLine[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('journal_ledger_read')
    .select('batch_id,organization_id,project_id,source_type,source_id,batch_transaction_date,posted_at,posted_by,reversal_of_batch_id,line_id,account_id,account_role,account_label,debit_minor_units,credit_minor_units,currency,cash_account_id,obligation_id,party_id,line_transaction_date')
    .eq('batch_id', batchId)
    .order('posted_at');
  if (error) throwOperatorQuery(error);
  return data as JournalLedgerLine[];
}

export async function getAuditEvents(entityIds: string[]): Promise<AuditEvent[]> {
  if (entityIds.length === 0) return [];
  const s = await createClient();
  const { data, error } = await s
    .from('audit_events')
    .select('id,event_type,entity_type,entity_id,payload,created_at')
    .in('entity_id', entityIds)
    .order('created_at', { ascending: false })
    .limit(200);
  if (error) throwOperatorQuery(error);
  return data as AuditEvent[];
}

export type Contribution = {
  id: string;
  project_id: string;
  participant_id: string;
  agreement_version_id: string;
  capital_call_id: string;
  contribution_minor_units: string;
  currency: string;
  occurred_on: string;
  created_at: string;
};

export async function getUnpostedContributions(projectId: string): Promise<Contribution[]> {
  const s = await createClient();
  const { data: contributions, error } = await s
    .from('contributions_read')
    .select('id,project_id,participant_id,agreement_version_id,capital_call_id,contribution_minor_units,currency,occurred_on,created_at')
    .eq('project_id', projectId)
    .order('occurred_on');
  if (error) throwOperatorQuery(error);
  const list = contributions as Contribution[];
  const { data: batches, error: batchError } = await s
    .from('journal_batches')
    .select('id,source_id')
    .eq('source_type', 'CONTRIBUTION_CASH_ATTRIBUTION');
  if (batchError) throw batchError;
  const { data: reversals, error: reversalError } = await s
    .from('journal_batches')
    .select('reversal_of_batch_id')
    .not('reversal_of_batch_id', 'is', null);
  if (reversalError) throw reversalError;

  const postedSourceIds = activePostedSourceIds(batches ?? [], reversals ?? []);
  return list.filter((contribution) => !postedSourceIds.has(contribution.id));
}
