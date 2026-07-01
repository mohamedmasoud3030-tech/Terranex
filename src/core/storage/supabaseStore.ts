/**
 * Generic Supabase-backed store factory.
 * Exposes the SAME synchronous interface as createLocalStorageStore
 * (get/set/update/subscribe/reset) so existing feature `storage.ts` files
 * do not need to change their calling code — only the import.
 *
 * Underneath, it keeps an in-memory cache hydrated from Supabase on load,
 * kept live via Postgres Realtime, and persists writes asynchronously
 * (optimistic local update, then diffed insert/update/delete against
 * Supabase). RLS scopes every row to `owner_id = auth.uid()` automatically.
 *
 * KNOWN LIMITATION (documented, not hidden): writes are optimistic and
 * fire-and-forget from the caller's point of view, matching the old
 * synchronous localStorage contract. If a remote write fails (e.g. RLS
 * rejection, network loss) the error is logged and the store re-syncs from
 * the server on the next hydrate. This is an accepted tradeoff to avoid
 * rewriting every feature's call sites in this pass; a follow-up should
 * thread a `Promise` return through the highest-risk paths (transactions,
 * settlements, obligations).
 *
 * CLIENT INJECTION: this module does NOT import the real `supabase` client
 * directly (that would pull `import.meta.env` into every consumer, including
 * the Node-based test suite). Instead, `setSupabaseClient` must be called
 * once at app bootstrap (see `supabaseBootstrap.ts`, imported first thing in
 * `main.tsx`) or, in tests, with an in-memory fake client
 * (see `tests/helpers/fakeSupabase.cjs`).
 */
import type { RealtimeChannel } from '@supabase/supabase-js';
import type { Listener } from './localStorageStore';
import { requireClient } from './supabaseClientRegistry';

export { setSupabaseClient } from './supabaseClientRegistry';

export interface SupabaseStore<T extends { id: string }> {
  get(): T[];
  set(value: T[]): void;
  update(fn: (current: T[]) => T[]): void;
  subscribe(listener: Listener<T[]>): () => void;
  reset(): void;
  ready: Promise<void>;
  isLoaded(): boolean;
}

export function createSupabaseStore<T extends { id: string }>(
  table: string,
  parse: (raw: unknown) => T = (v) => v as T,
  orderColumn = 'created_at',
): SupabaseStore<T> {
  let cache: T[] = [];
  let loaded = false;
  const listeners = new Set<Listener<T[]>>();
  let channel: RealtimeChannel | null = null;

  function notify() {
    listeners.forEach((l) => l(cache));
  }

  async function hydrate(): Promise<void> {
    const { data, error } = await requireClient().from(table).select('*').order(orderColumn, { ascending: false });
    if (error) {
      console.error(`تعذر تحميل بيانات ${table} من Supabase: ${error.message}`);
      loaded = true;
      return;
    }
    cache = (data ?? []).map((row) => parse(row));
    loaded = true;
    notify();
  }

  function subscribeRealtime() {
    if (typeof window === 'undefined') return;
    channel = requireClient()
      .channel(`store:${table}`)
      .on('postgres_changes', { event: '*', schema: 'public', table }, () => {
        void hydrate();
      })
      .subscribe();
  }

  const ready = hydrate();
  subscribeRealtime();

  function diffAndPersist(next: T[]) {
    const prevById = new Map(cache.map((item) => [item.id, item]));
    const nextById = new Map(next.map((item) => [item.id, item]));

    const toInsert: T[] = [];
    const toUpdate: T[] = [];
    for (const item of next) {
      const prev = prevById.get(item.id);
      if (!prev) {
        toInsert.push(item);
      } else if (JSON.stringify(prev) !== JSON.stringify(item)) {
        toUpdate.push(item);
      }
    }
    const toDeleteIds = [...prevById.keys()].filter((id) => !nextById.has(id));

    void (async () => {
      try {
        if (toInsert.length > 0) {
          const { error } = await requireClient().from(table).insert(toInsert);
          if (error) throw error;
        }
        for (const item of toUpdate) {
          const { error } = await requireClient().from(table).update(item).eq('id', item.id);
          if (error) throw error;
        }
        if (toDeleteIds.length > 0) {
          const { error } = await requireClient().from(table).delete().in('id', toDeleteIds);
          if (error) throw error;
        }
      } catch (error) {
        console.error(`فشل حفظ التغييرات على ${table} في Supabase:`, error);
        void hydrate();
      }
    })();
  }

  return {
    get: () => cache,
    set(value: T[]) {
      diffAndPersist(value);
      cache = value;
      notify();
    },
    update(fn) {
      const next = fn(cache);
      diffAndPersist(next);
      cache = next;
      notify();
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    reset() {
      const idsToDelete = cache.map((item) => item.id);
      cache = [];
      notify();
      if (idsToDelete.length > 0) {
        void requireClient().from(table).delete().in('id', idsToDelete);
      }
    },
    ready,
    isLoaded: () => loaded,
  };
}

export function disposeAllRealtimeChannels() {
  requireClient().removeAllChannels();
}
