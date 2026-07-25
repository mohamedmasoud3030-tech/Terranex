/**
 * Shared bootstrap for the Supabase-backed test suites.
 *
 * ORDER MATTERS. Every feature `storage.ts` calls `createSupabaseStore(...)` at
 * module load, and that constructor immediately calls `requireClient()` to
 * hydrate. So the fake client must be injected BEFORE any storage module is
 * required, otherwise the store throws "Supabase client غير مهيأ" from an
 * unawaited promise and the failure surfaces as an unhandledRejection in a
 * later, unrelated test. Requiring this file first makes that impossible.
 *
 * It also gives every suite:
 *   - a MemoryStorage `localStorage` (backup/theme/i18n code still uses it),
 *   - `resetWorkspace()` which truncates the fake DB AND re-hydrates every
 *     store, so no rows leak between tests,
 *   - `awaitHydration()` so tests never read before the first load finished.
 */

const {
  FakeSupabaseClient,
  resetFakeSupabase,
  seedFakeTable,
  failOperation,
  clearFailure,
  failRpc,
  failRpcWithEmptyPayload,
  fakeDb,
  calls,
} = require('./fakeSupabase.cjs');

class MemoryStorage {
  constructor() { this.values = new Map(); }
  get length() { return this.values.size; }
  key(index) { return Array.from(this.values.keys())[index] ?? null; }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
  clear() { this.values.clear(); }
}

global.localStorage = new MemoryStorage();

// `crypto.randomUUID` is used by every store's `makeId()`.
if (!global.crypto) global.crypto = require('node:crypto').webcrypto;

const fakeSupabase = new FakeSupabaseClient();

// Inject before ANY storage module is loaded.
const { setSupabaseClient, rehydrateAllStores, clearAllStoreCaches } =
  require('../.compiled/core/storage/supabaseStore.js');
setSupabaseClient(fakeSupabase);

/** Waits for the first hydration of every store passed in. */
async function awaitHydration(...stores) {
  await Promise.all(stores.map((store) => store.ready ?? store));
}

/**
 * Truncates the fake database and re-hydrates every registered store so the
 * in-memory caches match the now-empty tables. Without the re-hydrate, rows
 * created by a previous test stay visible in the cache — that is exactly the
 * cross-test bleed this suite is meant to prevent.
 */
async function resetWorkspace(seed = {}) {
  global.localStorage.clear();
  resetFakeSupabase();
  for (const [tableName, records] of Object.entries(seed)) {
    seedFakeTable(tableName, records);
  }
  await rehydrateAllStores();
}

module.exports = {
  MemoryStorage,
  fakeSupabase,
  awaitHydration,
  resetWorkspace,
  resetFakeSupabase,
  seedFakeTable,
  failOperation,
  clearFailure,
  failRpc,
  failRpcWithEmptyPayload,
  rehydrateAllStores,
  clearAllStoreCaches,
  fakeDb,
  calls,
};
