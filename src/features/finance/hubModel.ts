import type { Obligation, Project, Transaction } from '../../core/types/domain';
import { computeGlobalSummary } from '../../core/lib/profitability';
import { getOutstandingEgp, queryObligationAging } from './obligationQueries';
import type { FinanceContext } from './contracts';

export interface TransactionFilters extends FinanceContext {
  direction?: Transaction['direction'] | 'all';
  category?: Transaction['category'] | 'all';
  dateFrom?: string;
  dateTo?: string;
}

export interface ObligationFilters extends FinanceContext {
  direction?: Obligation['direction'] | 'all';
  status?: Obligation['status'] | 'all';
  aging?: 'all' | 'overdue' | 'not-due';
  asOf: string;
}

export function filterTransactions(items: Transaction[], filters: TransactionFilters) {
  return items.filter((item) => {
    if (filters.projectId && item.project_id !== filters.projectId) return false;
    if (filters.assetId && item.asset_id !== filters.assetId) return false;
    if (filters.partnerId && item.partner_id !== filters.partnerId) return false;
    if (filters.eventId && item.operational_event_id !== filters.eventId) return false;
    if (filters.direction && filters.direction !== 'all' && item.direction !== filters.direction) return false;
    if (filters.category && filters.category !== 'all' && item.category !== filters.category) return false;
    if (filters.dateFrom && item.transaction_date < filters.dateFrom) return false;
    if (filters.dateTo && item.transaction_date > filters.dateTo) return false;
    return true;
  });
}

export function filterObligations(items: Obligation[], filters: ObligationFilters) {
  return items.filter((item) => {
    if (filters.projectId && item.project_id !== filters.projectId) return false;
    if (filters.partnerId && item.partner_id !== filters.partnerId) return false;
    if (filters.obligationId && item.id !== filters.obligationId) return false;
    if (filters.direction && filters.direction !== 'all' && item.direction !== filters.direction) return false;
    if (filters.status && filters.status !== 'all' && item.status !== filters.status) return false;
    const overdue = Boolean(
      item.due_date
      && item.due_date < filters.asOf
      && item.status !== 'settled'
      && item.status !== 'written_off',
    );
    if (filters.aging === 'overdue' && !overdue) return false;
    if (filters.aging === 'not-due' && overdue) return false;
    return true;
  });
}

export function computeFinanceOverview(
  projects: Project[],
  transactions: Transaction[],
  obligations: Obligation[],
  asOf: string,
) {
  const summary = computeGlobalSummary(projects, transactions, obligations);
  const aging = queryObligationAging(obligations, { as_of: asOf });
  const actionable = obligations.filter((item) =>
    (item.status === 'open' || item.status === 'partial')
    && getOutstandingEgp(item) > 0,
  );
  return {
    incomeEgp: summary.total_income_egp,
    expenseEgp: summary.total_expense_egp,
    receivablesEgp: summary.open_receivables_egp,
    payablesEgp: summary.open_payables_egp,
    cashExposureEgp: summary.cash_exposure_egp,
    aging,
    actionable,
  };
}
