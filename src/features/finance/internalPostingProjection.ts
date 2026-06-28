import { requireDateOnly } from '../../core/lib/dateOnly';
import type { Obligation, ObligationDirection } from '../../core/types/domain';
import type { Settlement } from '../settlements/types';
import type { SettlementAllocation } from '../settlement-allocations/types';

const MONEY_EPSILON = 0.000001;

/**
 * Minimal semantic accounts for Terranex's internal posting contract.
 * They are not a configurable chart of accounts and are intentionally hidden from the UI.
 */
export type InternalPostingAccount =
  | 'trade_receivables'
  | 'trade_payables'
  | 'settlement_clearing'
  | 'obligation_offset';

export type InternalPostingSourceType =
  | 'obligation'
  | 'settlement_allocation'
  | 'settlement_reversal';

export interface InternalPostingLine {
  account: InternalPostingAccount;
  debit_egp: number;
  credit_egp: number;
}

export interface InternalPosting {
  id: string;
  source_type: InternalPostingSourceType;
  source_id: string;
  posting_date: string;
  partner_id: string;
  project_id?: string;
  obligation_id: string;
  settlement_id?: string;
  document_id?: string;
  reversal_of_posting_id?: string;
  lines: InternalPostingLine[];
}

export interface InternalAccountBalance {
  account: InternalPostingAccount;
  debit_egp: number;
  credit_egp: number;
  balance_egp: number;
}

export interface InternalPostingProjectionOptions {
  /** Includes original and opposite reversal postings for cancelled settlements. */
  include_reversed?: boolean;
}

export interface InternalPostingProjection {
  postings: InternalPosting[];
  skipped_allocation_ids: string[];
  account_balances: InternalAccountBalance[];
}

function ensureAmount(value: number, label: string): number {
  if (!Number.isFinite(value) || value <= MONEY_EPSILON) {
    throw new Error(`${label} يجب أن يكون رقماً صالحاً أكبر من صفر.`);
  }
  return value;
}

function buildLines(
  debitAccount: InternalPostingAccount,
  creditAccount: InternalPostingAccount,
  amount: number,
): InternalPostingLine[] {
  return [
    { account: debitAccount, debit_egp: amount, credit_egp: 0 },
    { account: creditAccount, debit_egp: 0, credit_egp: amount },
  ];
}

function reverseLines(lines: InternalPostingLine[]): InternalPostingLine[] {
  return lines.map((line) => ({
    account: line.account,
    debit_egp: line.credit_egp,
    credit_egp: line.debit_egp,
  }));
}

function balanceOfLines(lines: InternalPostingLine[]) {
  return lines.reduce(
    (totals, line) => ({
      debit_egp: totals.debit_egp + line.debit_egp,
      credit_egp: totals.credit_egp + line.credit_egp,
    }),
    { debit_egp: 0, credit_egp: 0 },
  );
}

export function validateInternalPosting(posting: InternalPosting): void {
  if (!posting.id.trim()) throw new Error('معرّف القيد الداخلي مطلوب.');
  if (!posting.source_id.trim()) throw new Error('مرجع مصدر القيد الداخلي مطلوب.');
  requireDateOnly(posting.posting_date, 'تاريخ القيد الداخلي');
  if (!posting.partner_id.trim()) throw new Error('طرف القيد الداخلي مطلوب.');
  if (!posting.obligation_id.trim()) throw new Error('التزام القيد الداخلي مطلوب.');
  if (posting.lines.length < 2) throw new Error('القيد الداخلي يجب أن يحتوي على طرفين على الأقل.');

  for (const line of posting.lines) {
    if (!Number.isFinite(line.debit_egp) || !Number.isFinite(line.credit_egp)) {
      throw new Error('قيم القيد الداخلي يجب أن تكون أرقاماً صالحة.');
    }
    if (line.debit_egp < 0 || line.credit_egp < 0) {
      throw new Error('قيم القيد الداخلي لا يمكن أن تكون سالبة.');
    }
    if ((line.debit_egp > MONEY_EPSILON) === (line.credit_egp > MONEY_EPSILON)) {
      throw new Error('كل سطر في القيد الداخلي يجب أن يكون مديناً أو دائناً فقط.');
    }
  }

  const totals = balanceOfLines(posting.lines);
  if (Math.abs(totals.debit_egp - totals.credit_egp) > MONEY_EPSILON) {
    throw new Error('القيد الداخلي غير متوازن بين المدين والدائن.');
  }
}

function obligationOpeningAccounts(direction: ObligationDirection): [InternalPostingAccount, InternalPostingAccount] {
  return direction === 'receivable'
    ? ['trade_receivables', 'obligation_offset']
    : ['obligation_offset', 'trade_payables'];
}

function settlementAllocationAccounts(direction: ObligationDirection): [InternalPostingAccount, InternalPostingAccount] {
  return direction === 'receivable'
    ? ['settlement_clearing', 'trade_receivables']
    : ['trade_payables', 'settlement_clearing'];
}

function makeObligationPosting(obligation: Obligation): InternalPosting | undefined {
  if (obligation.status === 'written_off') return undefined;
  const amount = ensureAmount(obligation.amount_egp, 'قيمة الالتزام');
  const [debitAccount, creditAccount] = obligationOpeningAccounts(obligation.direction);
  const posting: InternalPosting = {
    id: `posting:obligation:${obligation.id}`,
    source_type: 'obligation',
    source_id: obligation.id,
    posting_date: requireDateOnly(obligation.created_at, 'تاريخ إنشاء الالتزام'),
    partner_id: obligation.partner_id,
    project_id: obligation.project_id,
    obligation_id: obligation.id,
    document_id: obligation.document_id,
    lines: buildLines(debitAccount, creditAccount, amount),
  };
  validateInternalPosting(posting);
  return posting;
}

function makeSettlementAllocationPosting(
  allocation: SettlementAllocation,
  settlement: Settlement,
  obligation: Obligation,
): InternalPosting {
  const amount = ensureAmount(allocation.allocated_amount_egp, 'قيمة توزيع التسوية');
  const [debitAccount, creditAccount] = settlementAllocationAccounts(obligation.direction);
  const posting: InternalPosting = {
    id: `posting:settlement-allocation:${allocation.id}`,
    source_type: 'settlement_allocation',
    source_id: allocation.id,
    posting_date: requireDateOnly(settlement.settlement_date, 'تاريخ التسوية'),
    partner_id: obligation.partner_id,
    project_id: obligation.project_id,
    obligation_id: obligation.id,
    settlement_id: settlement.id,
    document_id: settlement.receipt_document_id,
    lines: buildLines(debitAccount, creditAccount, amount),
  };
  validateInternalPosting(posting);
  return posting;
}

function makeSettlementReversalPosting(
  original: InternalPosting,
  settlement: Settlement,
): InternalPosting {
  const posting: InternalPosting = {
    ...original,
    id: `posting:settlement-reversal:${original.source_id}`,
    source_type: 'settlement_reversal',
    posting_date: requireDateOnly(settlement.reversed_at ?? settlement.updated_at, 'تاريخ عكس التسوية'),
    reversal_of_posting_id: original.id,
    lines: reverseLines(original.lines),
  };
  validateInternalPosting(posting);
  return posting;
}

function comparePostings(first: InternalPosting, second: InternalPosting): number {
  return (
    first.posting_date.localeCompare(second.posting_date) ||
    first.source_type.localeCompare(second.source_type) ||
    first.id.localeCompare(second.id)
  );
}

export function computeInternalAccountBalances(postings: InternalPosting[]): InternalAccountBalance[] {
  const balances = new Map<InternalPostingAccount, InternalAccountBalance>();
  for (const posting of postings) {
    validateInternalPosting(posting);
    for (const line of posting.lines) {
      const current = balances.get(line.account) ?? {
        account: line.account,
        debit_egp: 0,
        credit_egp: 0,
        balance_egp: 0,
      };
      current.debit_egp += line.debit_egp;
      current.credit_egp += line.credit_egp;
      current.balance_egp = current.debit_egp - current.credit_egp;
      balances.set(line.account, current);
    }
  }

  return [...balances.values()].sort((first, second) => first.account.localeCompare(second.account));
}

/**
 * Rebuilds a deterministic, read-only double-entry projection from current Terranex records.
 * The projection never creates substitute allocations from a legacy settlement link: a missing
 * allocation is reported to the caller and is left out until the settlement-allocation migration runs.
 * Written-off obligations are excluded because this stage does not yet model a write-off posting.
 */
export function projectInternalPostings(
  obligations: Obligation[],
  settlements: Settlement[],
  allocations: SettlementAllocation[],
  options: InternalPostingProjectionOptions = {},
): InternalPostingProjection {
  const postings: InternalPosting[] = [];
  const skippedAllocationIds: string[] = [];
  const obligationsById = new Map(obligations.map((obligation) => [obligation.id, obligation]));
  const settlementsById = new Map(settlements.map((settlement) => [settlement.id, settlement]));

  for (const obligation of obligations) {
    const posting = makeObligationPosting(obligation);
    if (posting) postings.push(posting);
  }

  for (const allocation of allocations) {
    const obligation = obligationsById.get(allocation.obligation_id);
    const settlement = settlementsById.get(allocation.settlement_id);
    if (!obligation || !settlement || obligation.status === 'written_off') {
      skippedAllocationIds.push(allocation.id);
      continue;
    }

    if (settlement.status === 'reversed' && !options.include_reversed) continue;

    const original = makeSettlementAllocationPosting(allocation, settlement, obligation);
    postings.push(original);
    if (settlement.status === 'reversed') postings.push(makeSettlementReversalPosting(original, settlement));
  }

  postings.sort(comparePostings);
  return {
    postings,
    skipped_allocation_ids: [...new Set(skippedAllocationIds)].sort(),
    account_balances: computeInternalAccountBalances(postings),
  };
}
