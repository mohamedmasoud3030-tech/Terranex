import type { Transaction } from '../../core/types/domain';
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
