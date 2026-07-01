import { createSupabaseStore } from '../../core/storage/supabaseStore';
import { guardAssetDeletion } from '../../core/lib/deletionGuards';
import type { Asset } from '../../core/types/domain';

const TABLE = 'assets';

function parseOne(raw: unknown): Asset {
  return raw as Asset;
}

function makeId() {
  return crypto.randomUUID();
}

const store = createSupabaseStore<Asset>(TABLE, parseOne);

export const assetsReady = store.ready;

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
  remove: async (id: string): Promise<void> => {
    const guard = await guardAssetDeletion(id);
    if (!guard.canDelete) throw new Error(guard.message_ar);
    store.update((all) => all.filter((a) => a.id !== id));
  },
  subscribe: store.subscribe,
  reset: store.reset,
};
