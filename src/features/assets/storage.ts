import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import { guardAssetDeletion } from '../../core/domain/deletionGuards';
import { documentsStore } from '../documents/storage';
import { operationalEventsStore, stockAdjustmentsStore } from '../events/storage';
import { transactionsStore } from '../transactions/storage';
import type { Asset } from '../../core/types/domain';

const KEY = 'terranex.assets.v1';

function parse(raw: unknown): Asset[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (r): r is Asset =>
      r && typeof r === 'object' &&
      typeof r.id === 'string' &&
      typeof r.name_ar === 'string',
  ).sort((a, b) => b.created_at.localeCompare(a.created_at));
}

function makeId() {
  return `ast-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

const store = createLocalStorageStore<Asset[]>(KEY, [], parse);

export type AssetInput = Omit<Asset, 'id' | 'created_at'>;

export const assetsStore = {
  getAll: () => store.get(),
  getByProject: (projectId: string) => store.get().filter((a) => a.project_id === projectId),
  create: (input: AssetInput): Asset => {
    const asset: Asset = { ...input, id: makeId(), created_at: new Date().toISOString() };
    store.update((all) => [asset, ...all]);
    return asset;
  },
  update: (id: string, input: Partial<AssetInput>): void => {
    store.update((all) => all.map((a) => a.id === id ? { ...a, ...input } : a));
  },
  remove: (id: string): void => {
    const guard = guardAssetDeletion(id, {
      transactions: transactionsStore.getAll(),
      assets: store.get(),
      obligations: [],
      documents: documentsStore.getAll(),
      projectPartners: [],
      operationalEvents: operationalEventsStore.getAll(),
      stockAdjustments: stockAdjustmentsStore.getAll(),
    });
    if (!guard.allowed) throw new Error(guard.message);
    store.update((all) => all.filter((a) => a.id !== id));
  },
  subscribe: store.subscribe,
  reset: store.reset,
};
