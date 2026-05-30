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

export const transactionsStore = {
  getAll: () => store.get(),
  getByProject: (projectId: string) => store.get().filter((t) => t.project_id === projectId),
  getByAsset: (assetId: string) => store.get().filter((t) => t.asset_id === assetId),
  getByPartner: (partnerId: string) => store.get().filter((t) => t.partner_id === partnerId),
  create: (input: TransactionInput): Transaction => {
    const now = new Date().toISOString();
    const tx: Transaction = { ...input, id: makeId(), created_at: now, updated_at: now };
    store.update((all) => [tx, ...all]);
    return tx;
  },
  update: (id: string, input: Partial<TransactionInput>): void => {
    store.update((all) =>
      all.map((t) => t.id === id ? { ...t, ...input, updated_at: new Date().toISOString() } : t),
    );
  },
  remove: (id: string): void => {
    store.update((all) => all.filter((t) => t.id !== id));
  },
  subscribe: store.subscribe,
  reset: store.reset,
};
