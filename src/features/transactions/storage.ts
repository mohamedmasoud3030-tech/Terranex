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

export const transactionsStore = {
  getAll: () => store.get(),
  getByProject: (projectId: string) => store.get().filter((t) => t.project_id === projectId),
  getByAsset: (assetId: string) => store.get().filter((t) => t.asset_id === assetId),
  getByPartner: (partnerId: string) => store.get().filter((t) => t.partner_id === partnerId),
  create: (input: TransactionInput): Transaction => {
    const normalized = normalizeInput(input);
    const now = new Date().toISOString();
    const tx: Transaction = { ...normalized, id: makeId(), created_at: now, updated_at: now };
    bindSupportingDocument(tx.document_id!, tx.id);
    try {
      store.update((all) => [tx, ...all]);
      return tx;
    } catch (error) {
      releaseSupportingDocument(tx.document_id!, tx.id);
      throw error;
    }
  },
  update: (id: string, input: Partial<TransactionInput>): void => {
    const existing = requireTransaction(id);
    const normalized = normalizeInput({ ...existing, ...input }, id);
    const previousDocumentId = existing.document_id!;
    const nextDocumentId = normalized.document_id!;
    const documentChanged = previousDocumentId !== nextDocumentId;

    if (documentChanged) bindSupportingDocument(nextDocumentId, id);
    try {
      store.update((all) => all.map((transaction) => transaction.id === id
        ? { ...transaction, ...normalized, updated_at: new Date().toISOString() }
        : transaction));
    } catch (error) {
      if (documentChanged) releaseSupportingDocument(nextDocumentId, id);
      throw error;
    }
    if (documentChanged) releaseSupportingDocument(previousDocumentId, id);
  },
  remove: (id: string): void => {
    const existing = requireTransaction(id);
    releaseSupportingDocument(existing.document_id!, id);
    try {
      store.update((all) => all.filter((transaction) => transaction.id !== id));
    } catch (error) {
      bindSupportingDocument(existing.document_id!, id);
      throw error;
    }
  },
  subscribe: store.subscribe,
  reset: store.reset,
};
