/**
 * Generic Supabase-backed store factory.
 * Exposes the SAME synchronous read interface as createLocalStorageStore
 * (get/set/update/subscribe/reset) so existing feature `storage.ts` files
 * do not need to change their calling code — only the import.
 *
 * Underneath, it keeps an in-memory cache hydrated from Supabase on load,
 * kept live via Postgres Realtime, and persists writes asynchronously
 * (optimistic local update, then diffed insert/update/delete against
 * Supabase). RLS scopes every row to `owner_id = auth.uid()` automatically.
 *
 * KNOWN LIMITATION (documented, not hidden): writes are optimistic from the
 * caller's point of view, matching the old synchronous localStorage contract.
 * They are NO LONGER fire-and-forget, though:
 *
 *   - every write is tracked, so `flush()` awaits the round trip and REJECTS
 *     with the Supabase error when the write failed;
 *   - a failed write re-hydrates from the server, so the optimistic cache is
 *     rolled back instead of reporting a fake local success;
 *   - `getWriteError()` exposes the last failure for callers that cannot await.
 *
 * Threading a real `Promise` return through every call site (transactions,
 * settlements, obligations) and making multi-row financial writes atomic is
 * Phase 2 work — it needs the Supabase schema and RPC layer that does not
 * exist yet.
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
  /** Re-reads the whole table from Supabase and replaces the cache. */
  rehydrate(): Promise<void>;
  /**
   * Awaits every write issued so far. Rejects with the Supabase error if any
   * of them failed, then clears the recorded error. Use this anywhere a
   * "saved" confirmation would otherwise be a lie.
   */
  flush(): Promise<void>;
  /** Last hydration error, or null. `get()` returns [] when this is set. */
  getLoadError(): Error | null;
  /** Last write error that has not been consumed by `flush()`, or null. */
  getWriteError(): Error | null;
  /**
   * How many times `get()` was called before the first hydration finished.
   * Reads in that window return an empty list that is indistinguishable from
   * "the user genuinely has no rows", so every one of them is a latent bug.
   */
  getReadsBeforeHydration(): number;
}

interface StoreHandle {
  rehydrate(): Promise<void>;
  clearCache(): void;
}

const registry = new Set<StoreHandle>();

/**
 * Re-hydrates every store from Supabase. Needed whenever the authenticated
 * identity changes: the cache of the previous session must never be shown to
 * the next one.
 */
export async function rehydrateAllStores(): Promise<void> {
  await Promise.all([...registry].map((store) => store.rehydrate()));
}

/** Drops every in-memory cache without touching Supabase. */
export function clearAllStoreCaches(): void {
  for (const store of registry) store.clearCache();
}

function toError(value: unknown, fallback: string): Error {
  if (value instanceof Error) return value;
  if (value && typeof value === 'object' && 'message' in value) {
    return new Error(String((value as { message: unknown }).message));
  }
  return new Error(fallback);
}

export function createSupabaseStore<T extends { id: string }>(
  table: string,
  parse: (raw: unknown) => T = (v) => v as T,
  orderColumn = 'created_at',
): SupabaseStore<T> {
  let cache: T[] = [];
  let loaded = false;
  let loadError: Error | null = null;
  let writeError: Error | null = null;
  let readsBeforeHydration = 0;
  let pendingWrites: Array<Promise<void>> = [];
  const listeners = new Set<Listener<T[]>>();
  let channel: RealtimeChannel | null = null;

  function notify() {
    listeners.forEach((l) => l(cache));
  }

  async function hydrate(): Promise<void> {
    const { data, error } = await requireClient()
      .from(table)
      .select('*')
      .order(orderColumn, { ascending: false });
    if (error) {
      loadError = toError(error, `تعذر تحميل بيانات ${table} من Supabase.`);
      console.error(`تعذر تحميل بيانات ${table} من Supabase: ${loadError.message}`);
      // Keep the cache empty rather than serving stale rows, and mark the store
      // loaded so the UI is not stuck — `getLoadError()` carries the truth.
      cache = [];
      loaded = true;
      notify();
      return;
    }
    loadError = null;
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

  function track(operation: Promise<void>): void {
    // Never rejects: the error is recorded and surfaced through `flush()`.
    const guarded = operation.catch(async (error: unknown) => {
      writeError = toError(error, `فشل حفظ التغييرات على ${table} في Supabase.`);
      console.error(`فشل حفظ التغييرات على ${table} في Supabase:`, writeError.message);
      // Roll the optimistic cache back to server truth so the UI never shows a
      // write that Supabase rejected.
      await hydrate();
    });
    pendingWrites.push(guarded);
  }

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

    track((async () => {
      if (toInsert.length > 0) {
        const { error } = await requireClient().from(table).insert(toInsert);
        if (error) throw toError(error, `تعذر إدراج صفوف في ${table}.`);
      }
      for (const item of toUpdate) {
        const { error } = await requireClient().from(table).update(item).eq('id', item.id);
        if (error) throw toError(error, `تعذر تحديث صف في ${table}.`);
      }
      if (toDeleteIds.length > 0) {
        const { error } = await requireClient().from(table).delete().in('id', toDeleteIds);
        if (error) throw toError(error, `تعذر حذف صفوف من ${table}.`);
      }
    })());
  }

  const handle: SupabaseStore<T> = {
    get: () => {
      if (!loaded) readsBeforeHydration += 1;
      return cache;
    },
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
        track((async () => {
          const { error } = await requireClient().from(table).delete().in('id', idsToDelete);
          if (error) throw toError(error, `تعذر حذف صفوف من ${table}.`);
        })());
      }
    },
    ready,
    isLoaded: () => loaded,
    async rehydrate() {
      await hydrate();
    },
    async flush() {
      while (pendingWrites.length > 0) {
        const batch = pendingWrites;
        pendingWrites = [];
        await Promise.all(batch);
      }
      if (writeError) {
        const error = writeError;
        writeError = null;
        throw error;
      }
    },
    getLoadError: () => loadError,
    getWriteError: () => writeError,
    getReadsBeforeHydration: () => readsBeforeHydration,
  };

  registry.add({
    rehydrate: async () => {
      pendingWrites = [];
      writeError = null;
      readsBeforeHydration = 0;
      await hydrate();
    },
    clearCache: () => {
      cache = [];
      loaded = false;
      loadError = null;
      writeError = null;
      pendingWrites = [];
      notify();
    },
  });

  return handle;
}

export function disposeAllRealtimeChannels() {
  requireClient().removeAllChannels();
}
