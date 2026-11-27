import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

// Owner insights read models. Org-level, read-only; money arrives as text
// (bigint transported exactly through the *_read views) and is formatted
// with the shared money module.

export type OwnerWeeklyCashRow = {
  organization_id: string;
  week_start: string;
  currency: string;
  in_minor_units: string;
  out_minor_units: string;
};

export type OwnerOverdueObligationRow = {
  organization_id: string;
  project_id: string;
  obligation_id: string;
  description: string;
  currency: string;
  outstanding_minor_units: string;
  due_date: string;
  days_overdue: number;
};

export type OwnerBankSuggestionKind = 'PAY_OBLIGATION' | 'RECORD_OUTFLOW' | 'RECORD_INFLOW';

export type OwnerBankSuggestionRow = {
  line_id: string;
  organization_id: string;
  project_id: string;
  cash_account_id: string;
  transaction_date: string;
  amount_minor_units: string;
  currency: string;
  description: string;
  suggestion_kind: OwnerBankSuggestionKind;
  suggested_obligation_id: string | null;
  suggested_obligation_description: string | null;
};

export type OwnerCashPositionRow = {
  cash_account_id: string;
  organization_id: string;
  project_id: string;
  name: string;
  currency: string;
  balance_minor_units: string;
  last_posting_date: string | null;
};

export async function getOwnerWeeklyCash(organizationId: string): Promise<OwnerWeeklyCashRow[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('owner_weekly_cash_read')
    .select('organization_id,week_start,currency,in_minor_units,out_minor_units')
    .eq('organization_id', organizationId)
    .order('week_start', { ascending: false });
  if (error) throwOperatorQuery(error);
  return data as OwnerWeeklyCashRow[];
}

export async function getOwnerOverdueObligations(organizationId: string): Promise<OwnerOverdueObligationRow[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('owner_overdue_obligations_read')
    .select('organization_id,project_id,obligation_id,description,currency,outstanding_minor_units,due_date,days_overdue')
    .eq('organization_id', organizationId)
    .order('days_overdue', { ascending: false });
  if (error) throwOperatorQuery(error);
  return data as OwnerOverdueObligationRow[];
}

export async function getOwnerBankSuggestions(organizationId: string): Promise<OwnerBankSuggestionRow[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('owner_bank_line_suggestions_read')
    .select('line_id,organization_id,project_id,cash_account_id,transaction_date,amount_minor_units,currency,description,suggestion_kind,suggested_obligation_id,suggested_obligation_description')
    .eq('organization_id', organizationId)
    .order('transaction_date', { ascending: false });
  if (error) throwOperatorQuery(error);
  return data as OwnerBankSuggestionRow[];
}

export async function getOwnerCashPositions(organizationId: string): Promise<OwnerCashPositionRow[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('project_cash_position_read')
    .select('cash_account_id,organization_id,project_id,name,currency,balance_minor_units,last_posting_date')
    .eq('organization_id', organizationId)
    .order('name');
  if (error) throwOperatorQuery(error);
  return data as OwnerCashPositionRow[];
}
