import { guardTransactionDeletion } from '../../core/lib/deletionGuards';
import { validateTransactionReferences } from '../../core/lib/referenceValidation';
import { isFiniteNumber } from '../../core/lib/validation';
import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import type { Transaction } from '../../core/types/domain';
import { bindSupportingDocument, releaseSupportingDocument } from '../documents/transactionDocumentIntegrity';

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

export type TransactionInput = Omit<Transaction, 'id' | 'created_at' | 'updated_at'>;

function toInput(transaction: Transaction): TransactionInput {
  const { id: _id, created_at: _createdAt, updated_at: _updatedAt, ...input } = transaction;
  return input;
}

function normalizeInput(input: TransactionInput, transactionId?: string): TransactionInput {
  validateTransactionReferences(input, transactionId);
  if (!isFiniteNumber(input.amount) || input.amount <= 0) {
    throw new Error('قيمة المعاملة يجب أن تكون رقماً صالحاً أكبر من صفر.');
  }
  if (!input.transaction_date) throw new Error('تاريخ المعاملة مطلوب.');

  const fxRate = input.currency === 'EGP' ? 1 : input.fx_rate;
  if (!isFiniteNumber(fxRate) || fxRate <= 0) {
    throw new Error('سعر الصرف يجب أن يكون رقماً صالحاً أكبر من صفر.');
  }

  return {
    ...input,
    project_id: input.project_id.trim(),
    partner_id: input.partner_id?.trim(),
    document_id: input.document_id?.trim(),
    fx_rate: fxRate,
    amount_egp: input.amount * fxRate,
  };
}

function requireTransaction(id: string) {
  const transaction = store.get().find((item) => item.id === id);
  if (!transaction) throw new Error('المعاملة المطلوبة غير موجودة.');
  return transaction;
}

function buildUpdatedTransaction(id: string, input: Partial<TransactionInput>): Transaction {
  const existing = requireTransaction(id);
  const normalized = normalizeInput({ ...toInput(existing), ...input }, id);
  return { ...existing, ...normalized, updated_at: new Date().toISOString() };
}

export const transactionsStore = {
  getAll: () => store.get(),
  getById: (id: string) => store.get().find((item) => item.id === id),
  getByProject: (projectId: string) => store.get().filter((t) => t.project_id === projectId),
  getByAsset: (assetId: string) => store.get().filter((t) => t.asset_id === assetId),
  getByPartner: (partnerId: string) => store.get().filter((t) => t.partner_id === partnerId),
  create: (input: TransactionInput): Transaction => {
    const normalized = normalizeInput(input);
    const now = new Date().toISOString();
    const tx: Transaction = { ...normalized, id: makeId(), created_at: now, updated_at: now };
    const documentBound = bindSupportingDocument(tx.document_id!, tx.id);
    try {
      store.update((all) => [tx, ...all]);
    } catch (error) {
      if (documentBound) releaseSupportingDocument(tx.document_id!, tx.id);
      throw error;
    }
    return tx;
  },
  previewUpdate: (id: string, input: Partial<TransactionInput>): Transaction => buildUpdatedTransaction(id, input),
  update: (id: string, input: Partial<TransactionInput>): Transaction => {
    const existing = requireTransaction(id);
    const nextTransaction = buildUpdatedTransaction(id, input);
    const previousDocumentId = existing.document_id!;
    const nextDocumentId = nextTransaction.document_id!;
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
      store.update((all) => all.map((transaction) => transaction.id === id ? nextTransaction : transaction));
      return nextTransaction;
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
