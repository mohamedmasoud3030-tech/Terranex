import { newId } from '../../core/lib/id';
import type { Obligation, Transaction, TransactionDirection } from '../../core/types/domain';
import { obligationsStore } from '../obligations/storage';
import { linkFinancialMovement } from '../banking/storage';
import {
  generateRequestId,
  invokeFinanceRpc,
  P1B_ATOMIC_RPC_NAMES,
} from '../finance/financeWriteBoundary';
import {
  normalizeTransactionInput,
  transactionsStore,
  toTransactionInput,
  type TransactionInput,
} from './storage';

export interface DeferredExpenseTransactionInput extends TransactionInput {
  create_payable_obligation?: boolean;
  payable_due_date?: string;
  /** Optional bank/cash/wallet account that this transaction moves money through. */
  bank_account_id?: string;
  /**
   * Stable identifier for the form instance that produced this input.
   *
   * Supplied by the UI (see `TransactionForm`), it is mixed into the
   * idempotency key so two clicks on the same open form collapse to one
   * request, while two deliberately separate entries — even with identical
   * amounts, partner and date — each carry their own draft id and are recorded
   * as two distinct transactions.
   */
  draft_id?: string;
}

export interface RecordTransactionAtomicPayload {
  p_request_id: string;
  p_transaction: Record<string, unknown>;
  p_payable?: Record<string, unknown> | null;
}

export interface RecordTransactionAtomicResult {
  transaction_id: string;
  payable_id: string | null;
}

export interface UpdateTransactionAtomicResult {
  transaction_id: string;
  payable_id: string | null;
}

export function buildRecordTransactionAtomicPayload(
  input: DeferredExpenseTransactionInput,
  transactionId: string,
  payableId?: string,
  requestId = generateRequestId(
    P1B_ATOMIC_RPC_NAMES[0],
    input.draft_id ?? '',
    transactionId,
  ),
): RecordTransactionAtomicPayload {
  return {
    p_request_id: requestId,
    p_transaction: {
      id: transactionId,
      project_id: input.project_id,
      asset_id: input.asset_id,
      partner_id: input.partner_id,
      operational_event_id: input.operational_event_id,
      bank_account_id: input.bank_account_id ?? null,
      direction: input.direction,
      category: input.category,
      description: input.description,
      amount: input.amount,
      currency: input.currency,
      fx_rate: input.fx_rate,
      amount_egp: input.amount_egp,
      transaction_date: input.transaction_date,
      document_id: input.document_id,
      notes: input.notes,
    },
    p_payable: input.create_payable_obligation && payableId ? {
      id: payableId,
      project_id: input.project_id,
      partner_id: input.partner_id,
      direction: input.direction === 'income' ? 'receivable' : 'payable',
      amount: input.amount,
      currency: input.currency,
      amount_egp: input.amount_egp,
      due_date: input.payable_due_date,
      document_id: input.document_id,
      notes: input.notes,
    } : null,
  };
}

function requireDeferredExpense(input: DeferredExpenseTransactionInput) {
  if (!input.create_payable_obligation) return;
  if (input.direction !== 'expense' && input.direction !== 'income') {
    throw new Error('لا يمكن إنشاء ذمة تلقائياً إلا من معاملة مصروف أو إيراد.');
  }
  if (!input.partner_id?.trim()) {
    throw new Error('يجب ربط المعاملة الآجلة بطرف أو شريك.');
  }
  if (!input.payable_due_date?.trim()) {
    throw new Error('تاريخ الاستحقاق مطلوب للمعاملة الآجلة.');
  }
}

function getLinkedPayable(transactionId: string): Obligation | undefined {
  const linked = obligationsStore.getAll().filter(
    (obligation) => obligation.source_transaction_id === transactionId
      && (obligation.direction === 'payable' || obligation.direction === 'receivable'),
  );
  if (linked.length > 1) {
    throw new Error('توجد أكثر من ذمة مرتبطة بنفس المعاملة. راجع البيانات قبل المتابعة.');
  }
  return linked[0];
}

function buildPayableFields(transaction: Transaction) {
  if (!transaction.partner_id) {
    throw new Error('يجب أن تظل المعاملة الآجلة مرتبطة بطرف أو شريك.');
  }
  return {
    project_id: transaction.project_id,
    partner_id: transaction.partner_id,
    amount: transaction.amount,
    currency: transaction.currency,
    fx_rate: transaction.fx_rate,
    amount_egp: transaction.amount_egp,
    document_id: transaction.document_id,
    notes: transaction.notes,
  };
}

function buildPayableUpdate(transaction: Transaction, payable: Obligation) {
  const expectedDirection: TransactionDirection = payable.direction === 'receivable' ? 'income' : 'expense';
  if (transaction.direction !== expectedDirection) {
    throw new Error(
      payable.direction === 'receivable'
        ? 'لا يمكن تحويل معاملة مرتبطة بذمة مدينة إلى مصروف.'
        : 'لا يمكن تحويل معاملة مرتبطة بذمة دائنة إلى إيراد.',
    );
  }
  if (payable.amount_settled_egp > transaction.amount_egp) {
    throw new Error('لا يمكن تخفيض قيمة المعاملة الآجلة عن المبلغ المسدد بالفعل.');
  }
  if (payable.status === 'written_off' || payable.status === 'disputed') {
    throw new Error('لا يمكن تعديل معاملة مرتبطة بذمة مشطوبة أو متنازع عليها.');
  }

  const status: Obligation['status'] = payable.amount_settled_egp === 0
    ? 'open'
    : payable.amount_settled_egp >= transaction.amount_egp
      ? 'settled'
      : 'partial';

  return { ...buildPayableFields(transaction), status };
}

function requireTransactionAfterRpc(id: string): Transaction {
  const transaction = transactionsStore.getById(id);
  if (!transaction) {
    throw new Error('نجحت العملية على الخادم لكن تعذر تحميل المعاملة المحدثة. أعد المحاولة.');
  }
  return transaction;
}

/** Creates the transaction and optional payable in one PostgreSQL transaction. */
export async function createTransactionWithOptionalPayableAtomic(
  input: DeferredExpenseTransactionInput,
): Promise<Transaction> {
  requireDeferredExpense(input);
  const { create_payable_obligation, payable_due_date, ...transactionInput } = input;
  const normalized = normalizeTransactionInput(transactionInput);
  const atomicInput: DeferredExpenseTransactionInput = {
    ...normalized,
    create_payable_obligation,
    payable_due_date: payable_due_date?.trim(),
  };
  const transactionId = newId();
  const payableId = create_payable_obligation ? newId() : undefined;
  const payload = buildRecordTransactionAtomicPayload(atomicInput, transactionId, payableId);

  const result = await invokeFinanceRpc<RecordTransactionAtomicResult>(
    P1B_ATOMIC_RPC_NAMES[0],
    payload,
  );
  const saved = requireTransactionAfterRpc(result.transaction_id);

  // Mirror the movement into the bank ledger if a bank/cash account was chosen.
  if (input.bank_account_id) {
    try {
      await linkFinancialMovement({
        reference_type: 'transaction',
        reference_id: saved.id,
        bank_account_id: input.bank_account_id,
        direction: input.direction === 'income' ? 'deposit' : 'withdrawal',
        amount: input.amount,
        currency: input.currency,
        fx_rate_to_base: input.fx_rate ?? 1,
        transaction_date: input.transaction_date,
        memo: input.description ?? null,
        partner_id: input.partner_id ?? null,
        document_id: input.document_id ?? null,
      }, payload.p_request_id + '_bank');
    } catch {
      // Non-fatal: bank ledger entry may be created manually; don't lose the
      // financial transaction. Operator can reconcile from the Banking page.
    }
  }

  return saved;
}

/** Updates the transaction and its linked payable in one PostgreSQL transaction. */
export async function updateTransactionWithLinkedPayableAtomic(
  id: string,
  input: Partial<TransactionInput>,
): Promise<Transaction> {
  const payable = getLinkedPayable(id);
  const nextTransaction = transactionsStore.previewUpdate(id, input);
  const payableUpdates = payable ? buildPayableUpdate(nextTransaction, payable) : null;

  const result = await invokeFinanceRpc<UpdateTransactionAtomicResult>(
    P1B_ATOMIC_RPC_NAMES[1],
    {
      p_request_id: generateRequestId(P1B_ATOMIC_RPC_NAMES[1], id, JSON.stringify(input)),
      p_transaction_id: id,
      p_updates: toTransactionInput(nextTransaction),
      p_payable_updates: payableUpdates,
    },
  );
  return requireTransactionAfterRpc(result.transaction_id);
}

/** Deletes the transaction and its linked payable as one atomic graph. */
export async function deleteTransactionAtomic(id: string): Promise<void> {
  await invokeFinanceRpc(
    P1B_ATOMIC_RPC_NAMES[2],
    {
      p_request_id: generateRequestId(P1B_ATOMIC_RPC_NAMES[2], id),
      p_transaction_id: id,
    },
  );
}

// Legacy synchronous helpers remain for isolated model tests and migrations of
// non-UI callers. Production hooks and FinanceHub use the atomic variants above.
function rollbackTransaction(transaction: Transaction) {
  try {
    transactionsStore.update(transaction.id, toTransactionInput(transaction));
  } catch {
    throw new Error('تعذر تحديث الذمة الدائنة وتعذر التراجع الكامل عن تعديل المصروف. راجع البيانات المحلية فوراً.');
  }
}

export function createTransactionWithOptionalPayable(input: DeferredExpenseTransactionInput): Transaction {
  requireDeferredExpense(input);
  const { create_payable_obligation, payable_due_date, ...transactionInput } = input;
  const transaction = transactionsStore.create(transactionInput);

  if (!create_payable_obligation) return transaction;

  try {
    obligationsStore.create({
      ...buildPayableFields(transaction),
      direction: input.direction === 'income' ? 'receivable' : 'payable',
      due_date: payable_due_date!.trim(),
      status: 'open',
      source_transaction_id: transaction.id,
    });
    return transaction;
  } catch (error) {
    transactionsStore.remove(transaction.id);
    throw error;
  }
}

export function updateTransactionWithLinkedPayable(id: string, input: Partial<TransactionInput>): Transaction {
  const payable = getLinkedPayable(id);
  if (!payable) return transactionsStore.update(id, input);

  const previousTransaction = transactionsStore.getById(id);
  if (!previousTransaction) throw new Error('المعاملة المطلوبة غير موجودة.');
  const nextTransaction = transactionsStore.previewUpdate(id, input);
  const payableUpdate = buildPayableUpdate(nextTransaction, payable);

  transactionsStore.update(id, input);
  try {
    obligationsStore.update(payable.id, payableUpdate);
    return nextTransaction;
  } catch (error) {
    rollbackTransaction(previousTransaction);
    throw error;
  }
}
