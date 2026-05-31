import { isFiniteNumber } from '../../core/lib/validation';
import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import type { Transaction } from '../../core/types/domain';

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

function normalizeInput(input: TransactionInput): TransactionInput {
  if (!input.project_id.trim()) throw new Error('يجب اختيار مشروع صالح للمعاملة.');
  if (!input.partner_id?.trim()) throw new Error('يجب ربط المعاملة بطرف أو شريك.');
  if (!input.document_id?.trim()) throw new Error('يجب ربط المعاملة بوثيقة داعمة.');
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
    fx_rate: fxRate,
    amount_egp: input.amount * fxRate,
  };
}

export const transactionsStore = {
  getAll: () => store.get(),
  getByProject: (projectId: string) => store.get().filter((t) => t.project_id === projectId),
  getByAsset: (assetId: string) => store.get().filter((t) => t.asset_id === assetId),
  getByPartner: (partnerId: string) => store.get().filter((t) => t.partner_id === partnerId),
  create: (input: TransactionInput): Transaction => {
    const now = new Date().toISOString();
    const tx: Transaction = { ...normalizeInput(input), id: makeId(), created_at: now, updated_at: now };
    store.update((all) => [tx, ...all]);
    return tx;
  },
  update: (id: string, input: Partial<TransactionInput>): void => {
    store.update((all) =>
      all.map((t) => {
        if (t.id !== id) return t;
        return { ...t, ...normalizeInput({ ...t, ...input }), updated_at: new Date().toISOString() };
      }),
    );
  },
  remove: (id: string): void => {
    store.update((all) => all.filter((t) => t.id !== id));
  },
  subscribe: store.subscribe,
  reset: store.reset,
};
