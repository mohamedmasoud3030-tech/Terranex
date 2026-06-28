import { requireDateOnly, toDateOnly } from '../../core/lib/dateOnly';
import type { Obligation, ObligationDirection } from '../../core/types/domain';
import type { Settlement } from '../settlements/types';
import type { SettlementAllocation } from '../settlement-allocations/types';

const MONEY_EPSILON = 0.000001;

export const AGING_BUCKETS = [
  'not_due',
  'overdue_1_30',
  'overdue_31_60',
  'overdue_61_90',
  'overdue_91_plus',
  'undated',
] as const;

export type ObligationAgingBucket = typeof AGING_BUCKETS[number];

export interface ObligationAgingQuery {
  as_of: string;
  partner_id?: string;
  project_id?: string;
  direction?: ObligationDirection;
  include_disputed?: boolean;
}

export interface ObligationAgingRow {
  obligation_id: string;
  partner_id: string;
  project_id?: string;
  direction: ObligationDirection;
  status: Obligation['status'];
  due_date?: string;
  amount_egp: number;
  settled_egp: number;
  outstanding_egp: number;
  days_overdue?: number;
  bucket: ObligationAgingBucket;
}

export interface ObligationAgingBucketTotals {
  not_due_egp: number;
  overdue_1_30_egp: number;
  overdue_31_60_egp: number;
  overdue_61_90_egp: number;
  overdue_91_plus_egp: number;
  undated_egp: number;
}

export interface ObligationAgingTotals extends ObligationAgingBucketTotals {
  receivable_egp: number;
  payable_egp: number;
  outstanding_egp: number;
}

export interface PartnerAgingSummary {
  partner_id: string;
  totals: ObligationAgingTotals;
}

export interface ObligationAgingResult {
  as_of: string;
  rows: ObligationAgingRow[];
  totals: ObligationAgingTotals;
  by_partner: PartnerAgingSummary[];
}

export type PartnerStatementEntryType = 'obligation' | 'settlement_allocation';

export interface PartnerStatementQuery {
  partner_id: string;
  project_id?: string;
  include_reversed?: boolean;
}

export interface PartnerStatementEntry {
  id: string;
  entry_type: PartnerStatementEntryType;
  entry_date: string;
  partner_id: string;
  project_id?: string;
  obligation_id: string;
  settlement_id?: string;
  direction: ObligationDirection;
  debit_egp: number;
  credit_egp: number;
  amount_egp: number;
  is_effective: boolean;
  settlement_status?: Settlement['status'];
  running_balance_egp: number;
}

export interface PartnerStatementResult {
  partner_id: string;
  project_id?: string;
  entries: PartnerStatementEntry[];
  debit_total_egp: number;
  credit_total_egp: number;
  closing_balance_egp: number;
  closing_direction: 'receivable' | 'payable' | 'balanced';
}

function daysBetween(laterDate: string, earlierDate: string): number {
  const [laterYear, laterMonth, laterDay] = laterDate.split('-').map(Number);
  const [earlierYear, earlierMonth, earlierDay] = earlierDate.split('-').map(Number);
  const laterUtc = Date.UTC(laterYear, laterMonth - 1, laterDay);
  const earlierUtc = Date.UTC(earlierYear, earlierMonth - 1, earlierDay);
  return Math.round((laterUtc - earlierUtc) / 86_400_000);
}

function emptyTotals(): ObligationAgingTotals {
  return {
    not_due_egp: 0,
    overdue_1_30_egp: 0,
    overdue_31_60_egp: 0,
    overdue_61_90_egp: 0,
    overdue_91_plus_egp: 0,
    undated_egp: 0,
    receivable_egp: 0,
    payable_egp: 0,
    outstanding_egp: 0,
  };
}

function bucketTotalKey(bucket: ObligationAgingBucket): keyof ObligationAgingBucketTotals {
  return `${bucket}_egp` as keyof ObligationAgingBucketTotals;
}

function classifyAging(asOf: string, dueDate: string | undefined): Pick<ObligationAgingRow, 'bucket' | 'days_overdue' | 'due_date'> {
  const validDueDate = toDateOnly(dueDate);
  if (!validDueDate) return { bucket: 'undated' };

  const daysOverdue = daysBetween(asOf, validDueDate);
  if (daysOverdue <= 0) return { bucket: 'not_due', days_overdue: daysOverdue, due_date: validDueDate };
  if (daysOverdue <= 30) return { bucket: 'overdue_1_30', days_overdue: daysOverdue, due_date: validDueDate };
  if (daysOverdue <= 60) return { bucket: 'overdue_31_60', days_overdue: daysOverdue, due_date: validDueDate };
  if (daysOverdue <= 90) return { bucket: 'overdue_61_90', days_overdue: daysOverdue, due_date: validDueDate };
  return { bucket: 'overdue_91_plus', days_overdue: daysOverdue, due_date: validDueDate };
}

function isAgingEligible(obligation: Obligation, query: ObligationAgingQuery): boolean {
  if (obligation.status === 'settled' || obligation.status === 'written_off') return false;
  if (obligation.status === 'disputed' && query.include_disputed === false) return false;
  if (query.partner_id && obligation.partner_id !== query.partner_id) return false;
  if (query.project_id !== undefined && obligation.project_id !== query.project_id) return false;
  if (query.direction && obligation.direction !== query.direction) return false;
  return getOutstandingEgp(obligation) > MONEY_EPSILON;
}

function compareAgingRows(first: ObligationAgingRow, second: ObligationAgingRow): number {
  return (
    first.partner_id.localeCompare(second.partner_id) ||
    (first.due_date ?? '9999-12-31').localeCompare(second.due_date ?? '9999-12-31') ||
    first.obligation_id.localeCompare(second.obligation_id)
  );
}

function addToTotals(totals: ObligationAgingTotals, row: ObligationAgingRow): void {
  const bucketKey = bucketTotalKey(row.bucket);
  totals[bucketKey] += row.outstanding_egp;
  totals.outstanding_egp += row.outstanding_egp;
  if (row.direction === 'receivable') totals.receivable_egp += row.outstanding_egp;
  else totals.payable_egp += row.outstanding_egp;
}

export function getOutstandingEgp(obligation: Obligation): number {
  return Math.max(0, obligation.amount_egp - obligation.amount_settled_egp);
}

export function queryObligationAging(
  obligations: Obligation[],
  query: ObligationAgingQuery,
): ObligationAgingResult {
  const asOf = requireDateOnly(query.as_of, 'تاريخ التقرير');
  const rows = obligations
    .filter((obligation) => isAgingEligible(obligation, query))
    .map((obligation): ObligationAgingRow => ({
      obligation_id: obligation.id,
      partner_id: obligation.partner_id,
      project_id: obligation.project_id,
      direction: obligation.direction,
      status: obligation.status,
      amount_egp: obligation.amount_egp,
      settled_egp: obligation.amount_settled_egp,
      outstanding_egp: getOutstandingEgp(obligation),
      ...classifyAging(asOf, obligation.due_date),
    }))
    .sort(compareAgingRows);

  const totals = emptyTotals();
  const partnerTotals = new Map<string, ObligationAgingTotals>();
  for (const row of rows) {
    addToTotals(totals, row);
    const current = partnerTotals.get(row.partner_id) ?? emptyTotals();
    addToTotals(current, row);
    partnerTotals.set(row.partner_id, current);
  }

  const byPartner = [...partnerTotals.entries()]
    .map(([partner_id, partnerTotals]) => ({ partner_id, totals: partnerTotals }))
    .sort((first, second) => first.partner_id.localeCompare(second.partner_id));

  return { as_of: asOf, rows, totals, by_partner: byPartner };
}

function isStatementObligation(obligation: Obligation, query: PartnerStatementQuery): boolean {
  if (obligation.partner_id !== query.partner_id) return false;
  if (query.project_id !== undefined && obligation.project_id !== query.project_id) return false;
  return obligation.status !== 'written_off';
}

function statementDate(value: string | undefined, fallback: string | undefined): string {
  return toDateOnly(value) ?? toDateOnly(fallback) ?? '9999-12-31';
}

function makeObligationStatementEntry(obligation: Obligation): Omit<PartnerStatementEntry, 'running_balance_egp'> {
  const amount = obligation.amount_egp;
  const isReceivable = obligation.direction === 'receivable';
  return {
    id: `obligation:${obligation.id}`,
    entry_type: 'obligation',
    entry_date: statementDate(obligation.created_at, obligation.due_date),
    partner_id: obligation.partner_id,
    project_id: obligation.project_id,
    obligation_id: obligation.id,
    direction: obligation.direction,
    debit_egp: isReceivable ? amount : 0,
    credit_egp: isReceivable ? 0 : amount,
    amount_egp: amount,
    is_effective: true,
  };
}

function makeSettlementStatementEntry(
  allocation: SettlementAllocation,
  settlement: Settlement,
  obligation: Obligation,
): Omit<PartnerStatementEntry, 'running_balance_egp'> {
  const isEffective = settlement.status === 'active';
  const amount = isEffective ? allocation.allocated_amount_egp : 0;
  const isReceivable = obligation.direction === 'receivable';
  return {
    id: `settlement-allocation:${allocation.id}`,
    entry_type: 'settlement_allocation',
    entry_date: statementDate(settlement.settlement_date, settlement.created_at),
    partner_id: obligation.partner_id,
    project_id: obligation.project_id,
    obligation_id: obligation.id,
    settlement_id: settlement.id,
    direction: obligation.direction,
    debit_egp: isReceivable ? 0 : amount,
    credit_egp: isReceivable ? amount : 0,
    amount_egp: allocation.allocated_amount_egp,
    is_effective: isEffective,
    settlement_status: settlement.status,
  };
}

function compareStatementEntries(
  first: Omit<PartnerStatementEntry, 'running_balance_egp'>,
  second: Omit<PartnerStatementEntry, 'running_balance_egp'>,
): number {
  return (
    first.entry_date.localeCompare(second.entry_date) ||
    first.entry_type.localeCompare(second.entry_type) ||
    first.id.localeCompare(second.id)
  );
}

function directionForBalance(balance: number): PartnerStatementResult['closing_direction'] {
  if (balance > MONEY_EPSILON) return 'receivable';
  if (balance < -MONEY_EPSILON) return 'payable';
  return 'balanced';
}

/**
 * Builds a current-state party statement from obligation origins and settlement allocations.
 * Reversed settlements are excluded by default because their active effect is zero. When requested,
 * they are retained as zero-effect audit rows; this is not a historical as-of ledger reconstruction.
 */
export function queryPartnerStatement(
  obligations: Obligation[],
  settlements: Settlement[],
  allocations: SettlementAllocation[],
  query: PartnerStatementQuery,
): PartnerStatementResult {
  const statementObligations = obligations.filter((obligation) => isStatementObligation(obligation, query));
  const obligationsById = new Map(statementObligations.map((obligation) => [obligation.id, obligation]));
  const settlementsById = new Map(settlements.map((settlement) => [settlement.id, settlement]));

  const entries: Array<Omit<PartnerStatementEntry, 'running_balance_egp'>> = statementObligations.map(makeObligationStatementEntry);
  for (const allocation of allocations) {
    const obligation = obligationsById.get(allocation.obligation_id);
    const settlement = settlementsById.get(allocation.settlement_id);
    if (!obligation || !settlement) continue;
    if (settlement.status === 'reversed' && !query.include_reversed) continue;
    entries.push(makeSettlementStatementEntry(allocation, settlement, obligation));
  }

  entries.sort(compareStatementEntries);

  let debitTotal = 0;
  let creditTotal = 0;
  let runningBalance = 0;
  const rows = entries.map((entry) => {
    debitTotal += entry.debit_egp;
    creditTotal += entry.credit_egp;
    runningBalance += entry.debit_egp - entry.credit_egp;
    return { ...entry, running_balance_egp: runningBalance };
  });

  return {
    partner_id: query.partner_id,
    project_id: query.project_id,
    entries: rows,
    debit_total_egp: debitTotal,
    credit_total_egp: creditTotal,
    closing_balance_egp: runningBalance,
    closing_direction: directionForBalance(runningBalance),
  };
}
