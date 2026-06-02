import type { Obligation, Transaction } from '../../core/types/domain';
import { obligationsStore } from '../obligations/storage';
import { transactionsStore, type TransactionInput } from './storage';

export interface DeferredExpenseTransactionInput extends TransactionInput {
  create_payable_obligation?: boolean;
  payable_due_date?: string;
}

function requireDeferredExpense(input: DeferredExpenseTransactionInput) {
  if (!input.create_payable_obligation) return;
  if (input.direction !== 'expense') {
    throw new Error('لا يمكن إنشاء ذمة دائنة تلقائياً إلا من معاملة مصروف.');
  }
  if (!input.payable_due_date?.trim()) {
    throw new Error('تاريخ استحقاق الذمة الدائنة مطلوب للمصروف الآجل.');
  }
}

function toTransactionInput(transaction: Transaction): TransactionInput {
  const { id: _id, created_at: _createdAt, updated_at: _updatedAt, ...input } = transaction;
  return input;
}

function getLinkedPayable(transactionId: string): Obligation | undefined {
  const linkedPayables = obligationsStore.getAll().filter(
    (obligation) => obligation.source_transaction_id === transactionId && obligation.direction === 'payable',
  );
  if (linkedPayables.length > 1) {
    throw new Error('توجد أكثر من ذمة دائنة مرتبطة بنفس المعاملة. راجع البيانات المحلية قبل المتابعة.');
  }
  return linkedPayables[0];
}

function buildPayableUpdate(transaction: Transaction, payable: Obligation) {
  if (transaction.direction !== 'expense') {
    throw new Error('لا يمكن تحويل معاملة مرتبطة بذمة دائنة إلى إيراد.');
  }
  if (!transaction.partner_id) {
    throw new Error('يجب أن تظل معاملة المصروف الآجل مرتبطة بطرف أو شريك.');
  }
  if (payable.amount_settled_egp > transaction.amount_egp) {
    throw new Error('لا يمكن تخفيض قيمة المصروف الآجل عن المبلغ المسدد بالفعل.');
  }
  if (payable.status === 'written_off' || payable.status === 'disputed') {
    throw new Error('لا يمكن تعديل معاملة مرتبطة بذمة مشطوبة أو متنازع عليها.');
  }

  const status: Obligation['status'] = payable.amount_settled_egp === 0
    ? 'open'
    : payable.amount_settled_egp >= transaction.amount_egp
      ? 'settled'
      : 'partial';

  return {
    project_id: transaction.project_id,
    partner_id: transaction.partner_id,
    amount: transaction.amount,
    currency: transaction.currency,
    amount_egp: transaction.amount_egp,
    document_id: transaction.document_id,
    notes: transaction.notes,
    status,
  };
}

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
      project_id: transaction.project_id,
      partner_id: transaction.partner_id!,
      direction: 'payable',
      amount: transaction.amount,
      currency: transaction.currency,
      amount_egp: transaction.amount_egp,
      due_date: payable_due_date!.trim(),
      status: 'open',
      source_transaction_id: transaction.id,
      document_id: transaction.document_id,
      notes: transaction.notes,
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
