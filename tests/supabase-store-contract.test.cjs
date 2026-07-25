/**
 * Regression guards for the three failure modes that made the previous suite
 * report green while the Supabase migration was actually broken.
 *
 *   1. Reading data before hydration finished.
 *   2. Test data bleeding between tests.
 *   3. Fake local success when Supabase rejected the write.
 *
 * These are contract tests over `createSupabaseStore`. They are deliberately
 * written against the store factory rather than a feature module so that any
 * future store inherits the guarantees automatically.
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  resetWorkspace,
  seedFakeTable,
  failOperation,
  clearFailure,
  calls,
  fakeDb,
} = require('./helpers/setup.cjs');

const { createSupabaseStore } = require('./.compiled/core/storage/supabaseStore.js');

// ---------------------------------------------------------------------------
// 1. Reading before hydration completes
// ---------------------------------------------------------------------------

test('a store is not marked loaded until the first hydration resolves', async () => {
  await resetWorkspace();
  seedFakeTable('contract_probe', [{ id: 'a', created_at: '2026-01-01T00:00:00.000Z' }]);

  const store = createSupabaseStore('contract_probe');
  assert.equal(store.isLoaded(), false, 'يجب ألا يكون المخزن محمّلاً قبل انتهاء hydration.');
  assert.deepEqual(store.get(), [], 'القراءة المبكرة ترجع قائمة فارغة — وهذا بالضبط الخطر.');

  await store.ready;

  assert.equal(store.isLoaded(), true);
  assert.equal(store.get().length, 1);
});

test('every read issued before hydration is counted so it can never pass silently', async () => {
  await resetWorkspace();
  seedFakeTable('contract_probe_counted', [{ id: 'a', created_at: '2026-01-01T00:00:00.000Z' }]);

  const store = createSupabaseStore('contract_probe_counted');
  store.get();
  store.get();
  assert.equal(store.getReadsBeforeHydration(), 2);

  await store.ready;
  store.get();
  assert.equal(store.getReadsBeforeHydration(), 2, 'القراءات بعد التحميل يجب ألا تُحسب.');
});

test('an empty result before hydration is distinguishable from a genuinely empty table', async () => {
  await resetWorkspace();
  const empty = createSupabaseStore('contract_probe_empty');
  await empty.ready;

  // Genuinely empty: loaded, no error, no early reads.
  assert.deepEqual(empty.get(), []);
  assert.equal(empty.isLoaded(), true);
  assert.equal(empty.getLoadError(), null);

  const pending = createSupabaseStore('contract_probe_pending');
  assert.deepEqual(pending.get(), []);
  assert.equal(pending.isLoaded(), false, 'نفس النتيجة الفارغة لكن الحالة مختلفة تماماً.');
  await pending.ready;
});

test('a failed hydration is reported instead of masquerading as an empty workspace', async () => {
  await resetWorkspace();
  seedFakeTable('contract_probe_failed', [{ id: 'a', created_at: '2026-01-01T00:00:00.000Z' }]);
  failOperation('select', 'contract_probe_failed', 'JWT expired');

  const store = createSupabaseStore('contract_probe_failed');
  await store.ready;

  assert.deepEqual(store.get(), [], 'لا تُقدّم صفوفاً قديمة عند فشل التحميل.');
  assert.match(String(store.getLoadError()?.message), /JWT expired/);

  clearFailure('select', 'contract_probe_failed');
  await store.rehydrate();
  assert.equal(store.getLoadError(), null);
  assert.equal(store.get().length, 1);
});

// ---------------------------------------------------------------------------
// 2. Cross-test data bleed
// ---------------------------------------------------------------------------

test('resetWorkspace truncates every table in the fake database', async () => {
  await resetWorkspace();
  seedFakeTable('bleed_probe', [{ id: 'leftover', created_at: '2026-01-01T00:00:00.000Z' }]);
  assert.equal(fakeDb.bleed_probe.size, 1);

  await resetWorkspace();
  assert.equal(fakeDb.bleed_probe, undefined, 'الجداول يجب أن تُمسح بالكامل بين الاختبارات.');
});

test('resetWorkspace re-hydrates registered stores so no cached row survives', async () => {
  await resetWorkspace({ bleed_cached: [{ id: 'row-1', created_at: '2026-01-01T00:00:00.000Z' }] });
  const store = createSupabaseStore('bleed_cached');
  await store.ready;
  assert.equal(store.get().length, 1);

  await resetWorkspace();

  // The critical assertion: the cache is empty too, not just the table.
  // Truncating the DB without re-hydrating would leave this at 1.
  assert.equal(store.get().length, 0, 'الكاش يجب أن يتبع قاعدة البيانات بعد الإفراغ.');
});

test('resetWorkspace clears recorded calls and injected failures', async () => {
  await resetWorkspace();
  failOperation('insert', 'bleed_failures', 'boom');
  const store = createSupabaseStore('bleed_failures');
  await store.ready;
  store.set([{ id: 'x' }]);
  await assert.rejects(() => store.flush(), /boom/);

  await resetWorkspace();
  assert.equal(calls.insert.length, 0, 'سجل الاستدعاءات يجب أن يُصفّر.');

  const clean = createSupabaseStore('bleed_failures');
  await clean.ready;
  clean.set([{ id: 'x' }]);
  await clean.flush(); // must not throw — the injected failure is gone
  assert.equal(clean.get().length, 1);
});

// ---------------------------------------------------------------------------
// 3. Fake local success when Supabase rejects the write
// ---------------------------------------------------------------------------

test('a rejected insert is surfaced by flush and rolled back out of the cache', async () => {
  await resetWorkspace();
  const store = createSupabaseStore('write_probe');
  await store.ready;

  failOperation('insert', 'write_probe', 'new row violates row-level security policy');
  store.set([{ id: 'ghost', created_at: '2026-01-01T00:00:00.000Z' }]);

  assert.equal(store.get().length, 1, 'الكتابة المتفائلة تظهر فوراً — سلوك موثّق.');
  await assert.rejects(() => store.flush(), /row-level security/);
  assert.equal(store.get().length, 0, 'يجب التراجع عنها بعد رفض الخادم.');
  assert.equal(fakeDb.write_probe.size, 0);
});

test('a rejected update is surfaced and the cache resyncs to server truth', async () => {
  await resetWorkspace({ write_update: [{ id: 'r1', amount: 100, created_at: '2026-01-01T00:00:00.000Z' }] });
  const store = createSupabaseStore('write_update');
  await store.ready;

  failOperation('update', 'write_update', 'permission denied for table write_update');
  store.update((all) => all.map((row) => ({ ...row, amount: 999 })));

  await assert.rejects(() => store.flush(), /permission denied/);
  assert.equal(store.get()[0].amount, 100, 'القيمة يجب أن تعود لقيمة الخادم لا القيمة المرفوضة.');
});

test('a rejected delete is surfaced and the row comes back into the cache', async () => {
  await resetWorkspace({ write_delete: [{ id: 'r1', created_at: '2026-01-01T00:00:00.000Z' }] });
  const store = createSupabaseStore('write_delete');
  await store.ready;

  failOperation('delete', 'write_delete', 'permission denied for table write_delete');
  store.update((all) => all.filter((row) => row.id !== 'r1'));

  await assert.rejects(() => store.flush(), /permission denied/);
  assert.equal(store.get().length, 1, 'الصف الذي رفض الخادم حذفه يجب أن يظل موجوداً.');
});

test('flush resolves quietly when every write succeeded', async () => {
  await resetWorkspace();
  const store = createSupabaseStore('write_ok');
  await store.ready;

  store.set([{ id: 'r1', created_at: '2026-01-01T00:00:00.000Z' }]);
  await store.flush();

  assert.equal(store.getWriteError(), null);
  assert.equal(fakeDb.write_ok.size, 1);
});

test('flush reports the failure only once so a later flush is not falsely red', async () => {
  await resetWorkspace();
  const store = createSupabaseStore('write_once');
  await store.ready;

  failOperation('insert', 'write_once', 'boom');
  store.set([{ id: 'r1' }]);
  await assert.rejects(() => store.flush(), /boom/);

  clearFailure('insert', 'write_once');
  await store.flush();
  assert.equal(store.getWriteError(), null);
});

// ---------------------------------------------------------------------------
// Wire-shape contract: the fake must reject calls the real client rejects.
// ---------------------------------------------------------------------------

test('the store issues the exact select/order call shape the real client expects', async () => {
  await resetWorkspace();
  const store = createSupabaseStore('shape_probe', (v) => v, 'settlement_date');
  await store.ready;

  const select = calls.select.find((call) => call.table === 'shape_probe');
  assert.ok(select, 'يجب إصدار استعلام select واحد على الأقل.');
  assert.deepEqual(select.order, { column: 'settlement_date', ascending: false });
});

test('updates and deletes always carry a filter — never a whole-table write', async () => {
  await resetWorkspace({ filter_probe: [{ id: 'r1', amount: 1, created_at: '2026-01-01T00:00:00.000Z' }] });
  const store = createSupabaseStore('filter_probe');
  await store.ready;

  store.update((all) => all.map((row) => ({ ...row, amount: 2 })));
  await store.flush();
  store.update((all) => all.filter(() => false));
  await store.flush();

  const update = calls.update.find((call) => call.table === 'filter_probe');
  const remove = calls.delete.find((call) => call.table === 'filter_probe');
  assert.ok(update.filters.length > 0, 'تحديث بدون فلتر يعني الكتابة فوق الجدول بالكامل.');
  assert.ok(remove.filters.length > 0, 'حذف بدون فلتر يعني إفراغ الجدول بالكامل.');
});

test('the fake rejects duplicate primary keys exactly like Postgres does', async () => {
  await resetWorkspace({ pk_probe: [{ id: 'dup', created_at: '2026-01-01T00:00:00.000Z' }] });
  const store = createSupabaseStore('pk_probe');
  await store.ready;

  // Force a re-insert of an id that already exists server-side by desyncing
  // the cache first — this is what a stale client does in production.
  await resetWorkspace({ pk_probe: [{ id: 'dup', created_at: '2026-01-01T00:00:00.000Z' }] });
  const stale = createSupabaseStore('pk_probe');
  stale.set([{ id: 'dup', created_at: '2026-01-01T00:00:00.000Z' }]);

  await assert.rejects(() => stale.flush(), /duplicate key value/);
});
