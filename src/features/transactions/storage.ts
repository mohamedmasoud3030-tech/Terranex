import { guardTransactionDeletion } from '../../core/lib/deletionGuards';
import { validateTransactionReferences } from '../../core/lib/referenceValidation';
import { isFiniteNumber } from '../../core/lib/validation';
import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import type { Transaction } from '../../core/types/domain';
import { bindSupportingDocument, releaseSupportingDocument } from '../documents/transactionDocumentIntegrity';
import { obligationsStore } from '../obligations/storage';

const KEY = 'terranex.transactions.v2';

function parse(raw: unknown): Transaction[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (r): r is Transaction =>
      r && typeof r === 'object' &&
      typeof r.id === 'string' &&
      typeof r.project_id === 'string' &&
      typeof r.amount === 'number',
  ).sort((a, b) => b.transaction_date.localeCompare(a.transaction_date));
}

function makeId() {
  return `trx-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

const store = createLocalStorageStore<Transaction[]>(KEY, [], parse);

type PersistedTransactionInput = Omit<Transaction, 'id' | 'created_at' | 'updated_at'>;

export type TransactionInput = PersistedTransactionInput & {
  create_payable_obligation?: boolean;
  payable_due_date?: string;
};

function normalizeInput(input: TransactionInput, transactionId?: string): PersistedTransactionInput {
  const { create_payable_obligation: _createPayable, payable_due_date: _payableDueDate, ...transactionInput } = input;
  validateTransactionReferences(transactionInput, transactionId);
  if (!isFiniteNumber(transactionInput.amount) || transactionInput.amount <= 0) {
    throw new Error('قيمة المعاملة يجب أن تكون رقماً صالحاً أكبر من صفر.');
  }
  if (!transactionInput.transaction_date) throw new Error('تاريخ المعاملة مطلوب.');

  const fxRate = transactionInput.currency === 'EGP' ? 1 : transactionInput.fx_rate;
  if (!isFiniteNumber(fxRate) || fxRate <= 0) {
    throw new Error('سعر الصرف يجب أن يكون رقماً صالحاً أكبر من صفر.');
  }

  return {
    ...transactionInput,
    project_id: transactionInput.project_id.trim(),
    partner_id: transactionInput.partner_id?.trim(),
    document_id: transactionInput.document_id?.trim(),
    fx_rate: fxRate,
    amount_egp: transactionInput.amount * fxRate,
  };
}

function validatePayableExpenseRequest(input: TransactionInput, normalized: PersistedTransactionInput) {
  if (!input.create_payable_obligation) return;
  if (normalized.direction !== 'expense') {
    throw new Error('لا يمكن إنشاء ذمة دائنة تلقائياً إلا من معاملة مصروف.');
  }
  if (!input.payable_due_date?.trim()) {
    throw new Error('تاريخ استحقاق الذمة الدائنة مطلوب للمصروف الآجل.');
  }
}

function rollbackPayableExpense(transaction: Transaction, documentBound: boolean) {
  const rollbackErrors: unknown[] = [];

  for (const obligation of obligationsStore.getAll().filter((item) => item.source_transaction_id === transaction.id)) {
    try {
      obligationsStore.remove(obligation.id);
    } catch (error) {
      rollbackErrors.push(error);
    }
  }

  try {
    store.update((all) => all.filter((item) => item.id !== transaction.id));
  } catch (error) {
    rollbackErrors.push(error);
  }

  if (documentBound) {
    try {
      releaseSupportingDocument(transaction.document_id!, transaction.id);
    } catch (error) {
      rollbackErrors.push(error);
    }
  }

  if (rollbackErrors.length > 0) {
    throw new Error('تعذر إنشاء الذمة الدائنة وتعذر التراجع الكامل عن قيد المصروف. راجع البيانات المحلية فوراً.');
  }
}

function createPayableObligation(transaction: Transaction, dueDate: string) {
  return obligationsStore.create({
    project_id: transaction.project_id,
    partner_id: transaction.partner_id!,
    direction: 'payable',
    amount: transaction.amount,
    currency: transaction.currency,
    amount_egp: transaction.amount_egp,
    due_date: dueDate,
    status: 'open',
    source_transaction_id: transaction.id,
    document_id: transaction.document_id,
    notes: transaction.notes,
  });
}

function requireTransaction(id: string) {
  const transaction = store.get().find((item) => item.id === id);
  if (!transaction) throw new Error('المعاملة المطلوبة غير موجودة.');
  return transaction;
}

export const transactionsStore = {
  getAll: () => store.get(),
  getByProject: (projectId: string) => store.get().filter((t) => t.project_id === projectId),
  getByAsset: (assetId: string) => store.get().filter((t) => t.asset_id === assetId),
  getByPartner: (partnerId: string) => store.get().filter((t) => t.partner_id === partnerId),
  create: (input: TransactionInput): Transaction => {
    const normalized = normalizeInput(input);
    validatePayableExpenseRequest(input, normalized);
    const now = new Date().toISOString();
    const tx: Transaction = { ...normalized, id: makeId(), created_at: now, updated_at: now };
    const documentBound = bindSupportingDocument(tx.document_id!, tx.id);
    try {
      store.update((all) => [tx, ...all]);
    } catch (error) {
      if (documentBound) releaseSupportingDocument(tx.document_id!, tx.id);
      throw error;
    }

    if (!input.create_payable_obligation) return tx;

    try {
      createPayableObligation(tx, input.payable_due_date!.trim());
      return tx;
    } catch (error) {
      rollbackPayableExpense(tx, documentBound);
      throw error;
    }
  },
  update: (id: string, input: Partial<TransactionInput>): void => {
    const existing = requireTransaction(id);
    const normalized = normalizeInput({ ...existing, ...input }, id);
    const previousDocumentId = existing.document_id!;
    const nextDocumentId = normalized.document_id!;
    const documentChanged = previousDocumentId !== nextDocumentId;
    let nextDocumentBound = false;
    let previousDocumentReleased = false;

    if (documentChanged) {
      nextDocumentBound = bindSupportingDocument(nextDocumentId, id);
      try {
        previousDocumentReleased = releaseSupportingDocument(previousDocumentId, id);
      } catch (error) {
        if (nextDocumentBound) releaseSupportingDocument(nextDocumentId, id);
        throw error;
      }
    }

    try {
      store.update((all) => all.map((transaction) => transaction.id === id
        ? { ...transaction, ...normalized, updated_at: new Date().toISOString() }
        : transaction));
    } catch (error) {
      if (documentChanged) {
        if (previousDocumentReleased) bindSupportingDocument(previousDocumentId, id);
        if (nextDocumentBound) releaseSupportingDocument(nextDocumentId, id);
      }
      throw error;
    }
  },
  remove: (id: string): void => {
    const existing = requireTransaction(id);
    const guard = guardTransactionDeletion(id);
    if (!guard.canDelete) throw new Error(guard.message_ar);

    const documentReleased = releaseSupportingDocument(existing.document_id!, id);
    try {
      store.update((all) => all.filter((transaction) => transaction.id !== id));
    } catch (error) {
      if (documentReleased) bindSupportingDocument(existing.document_id!, id);
      throw error;
    }
  },
  subscribe: store.subscribe,
  reset: store.reset,
};
