/**
 * In-memory fake Supabase client for the Node test suite.
 *
 * DESIGN CONTRACT — this fake must mirror the *real* `@supabase/supabase-js`
 * call shapes that `src/` actually uses. If the fake is more permissive than
 * the real client, the suite reports green while production is broken. The
 * shapes covered here are exactly the ones used by:
 *
 *   - `supabaseStore.ts`  → client.from(t).select('*').order(col, {ascending})
 *                           client.from(t).insert(rows)
 *                           client.from(t).update(row).eq('id', id)
 *                           client.from(t).delete().in('id', ids)
 *                           client.channel(name).on(...).subscribe()
 *                           client.removeAllChannels()
 *   - `deletionGuards.ts` → client.rpc(fn, params)   ← on the CLIENT, not from()
 *
 * IMPORTANT / KNOWN GAP (kept honest on purpose):
 * The `rpc()` implementation below emulates the *intended* behaviour of the
 * `guard_*_deletion` Postgres functions. Those functions DO NOT EXIST in the
 * Supabase project yet (Phase 2 owns schema + RPC + RLS). So a green suite
 * here proves the client-side contract only — never that production works.
 * `failRpc()` exists precisely so we can assert the fail-closed path that
 * production currently takes.
 *
 * Every table is a Map keyed by row id. No auth, no RLS, no owner scoping.
 */

const fakeDb = {};

/** Injected-failure configuration, reset by `resetFakeSupabase()`. */
const failures = {
  select: new Map(), // table -> message
  insert: new Map(),
  update: new Map(),
  delete: new Map(),
  rpc: new Map(), // fn name -> message
  rpcEmpty: new Set(), // fn name -> return [] (malformed payload)
};

/** Call log so tests can assert the exact wire calls that were issued. */
const calls = { select: [], insert: [], update: [], delete: [], rpc: [] };

function table(name) {
  if (!fakeDb[name]) fakeDb[name] = new Map();
  return fakeDb[name];
}

function rows(name) {
  return Array.from(table(name).values()).map((row) => ({ ...row }));
}

function supabaseError(message, code = 'FAKE_ERROR') {
  // Shape mirrors PostgrestError: { message, details, hint, code }
  return { message, details: '', hint: '', code };
}

function applyFilters(list, filters) {
  return list.filter((row) => filters.every((filter) => {
    const value = row[filter.column];
    switch (filter.op) {
      case 'eq': return value === filter.value;
      case 'neq': return value !== filter.value;
      case 'in': return filter.value.includes(value);
      case 'is': return filter.value === null ? value === null || value === undefined : value === filter.value;
      case 'gt': return value > filter.value;
      case 'gte': return value >= filter.value;
      case 'lt': return value < filter.value;
      case 'lte': return value <= filter.value;
      default: throw new Error(`فلتر غير مدعوم في العميل الوهمي: ${filter.op}`);
    }
  }));
}

function applyOrder(list, order) {
  if (!order) return list;
  return [...list].sort((a, b) => {
    const av = a[order.column];
    const bv = b[order.column];
    if (av === bv) return 0;
    if (av === undefined || av === null) return order.ascending ? -1 : 1;
    if (bv === undefined || bv === null) return order.ascending ? 1 : -1;
    const cmp = av < bv ? -1 : 1;
    return order.ascending ? cmp : -cmp;
  });
}

/**
 * Thenable builder — mirrors PostgrestFilterBuilder: it is NOT a promise until
 * awaited, filters/order chain freely, and resolves to `{ data, error }`.
 * It never rejects, exactly like the real client.
 */
class FakeQueryBuilder {
  constructor(tableName, operation, payload = null) {
    this.tableName = tableName;
    this.operation = operation;
    this.payload = payload;
    this.filters = [];
    this.order_ = null;
    this.limit_ = null;
    this.single_ = false;
    this.maybeSingle_ = false;
    this.returning_ = false;
    this.settled = false;
  }

  select(columns = '*') {
    // `.insert(...).select()` / `.update(...).select()` request the written rows back.
    if (this.operation === 'select') {
      this.columns = columns;
      return this;
    }
    this.returning_ = true;
    return this;
  }

  order(column, options = {}) {
    const ascending = options.ascending !== false;
    this.order_ = { column, ascending };
    return this;
  }

  limit(count) { this.limit_ = count; return this; }
  single() { this.single_ = true; return this; }
  maybeSingle() { this.maybeSingle_ = true; return this; }

  eq(column, value) { this.filters.push({ column, op: 'eq', value }); return this; }
  neq(column, value) { this.filters.push({ column, op: 'neq', value }); return this; }
  in(column, values) {
    if (!Array.isArray(values)) throw new TypeError('in() تتطلب مصفوفة قيم.');
    this.filters.push({ column, op: 'in', value: values });
    return this;
  }
  is(column, value) { this.filters.push({ column, op: 'is', value }); return this; }
  gt(column, value) { this.filters.push({ column, op: 'gt', value }); return this; }
  gte(column, value) { this.filters.push({ column, op: 'gte', value }); return this; }
  lt(column, value) { this.filters.push({ column, op: 'lt', value }); return this; }
  lte(column, value) { this.filters.push({ column, op: 'lte', value }); return this; }

  execute() {
    const injected = failures[this.operation]?.get(this.tableName);
    if (injected) {
      calls[this.operation].push({ table: this.tableName, failed: true });
      return { data: null, error: supabaseError(injected) };
    }

    switch (this.operation) {
      case 'select': return this.executeSelect();
      case 'insert': return this.executeInsert();
      case 'update': return this.executeUpdate();
      case 'delete': return this.executeDelete();
      default:
        return { data: null, error: supabaseError(`عملية غير معروفة: ${this.operation}`) };
    }
  }

  executeSelect() {
    calls.select.push({ table: this.tableName, filters: this.filters, order: this.order_ });
    let result = applyOrder(applyFilters(rows(this.tableName), this.filters), this.order_);
    if (this.limit_ !== null) result = result.slice(0, this.limit_);

    if (this.single_) {
      if (result.length !== 1) return { data: null, error: supabaseError('صف واحد متوقع.', 'PGRST116') };
      return { data: result[0], error: null };
    }
    if (this.maybeSingle_) return { data: result[0] ?? null, error: null };
    return { data: result, error: null };
  }

  executeInsert() {
    const store = table(this.tableName);
    const incoming = Array.isArray(this.payload) ? this.payload : [this.payload];
    calls.insert.push({ table: this.tableName, count: incoming.length });

    // Real Postgres rejects duplicate primary keys instead of silently upserting.
    const duplicate = incoming.find((row) => row.id !== undefined && store.has(row.id));
    if (duplicate) {
      return {
        data: null,
        error: supabaseError(
          `duplicate key value violates unique constraint "${this.tableName}_pkey"`,
          '23505',
        ),
      };
    }

    const written = incoming.map((row) => ({ ...row }));
    for (const row of written) store.set(row.id, { ...row });
    return { data: this.returning_ ? written : null, error: null };
  }

  executeUpdate() {
    const store = table(this.tableName);
    calls.update.push({ table: this.tableName, filters: this.filters });
    // The real client requires a filter on update; an unfiltered update is a
    // whole-table overwrite and must never happen silently in this codebase.
    if (this.filters.length === 0) {
      return { data: null, error: supabaseError('تحديث بدون فلتر مرفوض.', 'FAKE_UNFILTERED_UPDATE') };
    }

    const written = applyFilters(rows(this.tableName), this.filters).map((row) => {
      const updated = { ...row, ...this.payload };
      store.set(updated.id, { ...updated });
      return updated;
    });
    return { data: this.returning_ ? written : null, error: null };
  }

  executeDelete() {
    const store = table(this.tableName);
    calls.delete.push({ table: this.tableName, filters: this.filters });
    if (this.filters.length === 0) {
      return { data: null, error: supabaseError('حذف بدون فلتر مرفوض.', 'FAKE_UNFILTERED_DELETE') };
    }

    const matched = applyFilters(rows(this.tableName), this.filters);
    for (const row of matched) store.delete(row.id);
    return { data: this.returning_ ? matched : null, error: null };
  }

}

const CHAIN_METHODS = [
  'select', 'order', 'limit', 'single', 'maybeSingle',
  'eq', 'neq', 'in', 'is', 'gt', 'gte', 'lt', 'lte',
];

/**
 * Wraps a builder in a plain thenable object.
 *
 * The real PostgrestFilterBuilder is itself a thenable: it is not a promise
 * until awaited, and chaining returns the same object. We reproduce that here
 * with an object literal rather than a `then` method on the class, because a
 * class whose instances are thenable is a genuine footgun (an accidental
 * `await` inside the class, or returning `this` from an async function, would
 * recurse). Keeping `then` on a plain wrapper gives identical semantics
 * without that hazard.
 */
function makeThenable(builder) {
  const thenable = {};

  for (const method of CHAIN_METHODS) {
    thenable[method] = (...args) => {
      builder[method](...args);
      return thenable;
    };
  }

  // Deliberately async (microtask) so tests cannot accidentally depend on
  // synchronous persistence — the real network round trip never is.
  thenable.then = (resolve, reject) => Promise.resolve()
    .then(() => builder.execute())
    .then(resolve, reject);
  thenable.catch = (onRejected) => thenable.then(undefined, onRejected);
  thenable.finally = (onFinally) => thenable.then().finally(onFinally);

  return thenable;
}

// ---------------------------------------------------------------------------
// RPC: emulation of the intended `guard_*_deletion` Postgres functions.
// Mirrors the pre-migration localStorage guard semantics and Arabic messages.
// ---------------------------------------------------------------------------

function blockIf(count, label) {
  return count === 0 ? null : `${label}: ${count}`;
}

function guardResult(blockers, entity) {
  const active = blockers.filter(Boolean);
  if (active.length === 0) {
    return { can_delete: true, message_ar: `يمكن حذف ${entity} بعد التأكيد. لا توجد روابط تشغيلية تمنع الحذف.` };
  }
  return {
    can_delete: false,
    message_ar: `لا يمكن حذف ${entity} لأنه مرتبط بسجلات مالية أو تشغيلية. افصل أو عالج الروابط أولاً: ${active.join('، ')}.`,
  };
}

function countWhere(tableName, predicate) {
  return rows(tableName).filter((row) => predicate(row)).length;
}

const RPC_HANDLERS = {
  guard_project_deletion: (params) => {
    const id = params.p_project_id;
    return guardResult([
      blockIf(countWhere('transactions', (r) => r.project_id === id), 'معاملات'),
      blockIf(countWhere('obligations', (r) => r.project_id === id), 'التزامات'),
      blockIf(countWhere('assets', (r) => r.project_id === id), 'أصول'),
      blockIf(countWhere('documents', (r) => r.project_id === id), 'مستندات'),
      blockIf(countWhere('project_partners', (r) => r.project_id === id), 'شركاء'),
      blockIf(countWhere('operational_events', (r) => r.project_id === id), 'أحداث تشغيلية'),
      blockIf(countWhere('stock_adjustments', (r) => r.project_id === id), 'تسويات مخزون'),
    ], 'المشروع');
  },
  guard_partner_deletion: (params) => {
    const id = params.p_partner_id;
    return guardResult([
      blockIf(countWhere('transactions', (r) => r.partner_id === id), 'معاملات'),
      blockIf(countWhere('obligations', (r) => r.partner_id === id), 'التزامات'),
      blockIf(countWhere('documents', (r) => r.partner_id === id), 'مستندات'),
      blockIf(countWhere('project_partners', (r) => r.partner_id === id), 'مشاريع ملكية'),
    ], 'الشريك');
  },
  guard_asset_deletion: (params) => {
    const id = params.p_asset_id;
    return guardResult([
      blockIf(countWhere('transactions', (r) => r.asset_id === id), 'معاملات'),
      blockIf(countWhere('documents', (r) => r.asset_id === id), 'مستندات'),
      blockIf(countWhere('operational_events', (r) => r.asset_id === id), 'أحداث تشغيلية'),
      blockIf(countWhere('stock_adjustments', (r) => r.asset_id === id), 'تسويات مخزون'),
    ], 'الأصل');
  },
  guard_document_deletion: (params) => {
    const id = params.p_document_id;
    return guardResult([
      blockIf(countWhere('transactions', (r) => r.document_id === id), 'معاملات'),
      blockIf(countWhere('obligations', (r) => r.document_id === id), 'التزامات'),
      blockIf(countWhere('settlements', (r) => r.receipt_document_id === id), 'تسويات'),
      blockIf(countWhere('operational_events', (r) => r.document_id === id), 'أحداث تشغيلية'),
    ], 'المستند');
  },
  guard_transaction_deletion: (params) => {
    const id = params.p_transaction_id;
    return guardResult([
      blockIf(countWhere('obligations', (r) => r.source_transaction_id === id), 'التزامات'),
      blockIf(countWhere('operational_events', (r) => r.linked_transaction_id === id), 'أحداث تشغيلية'),
    ], 'المعاملة');
  },
};

class FakeSupabaseClient {
  from(tableName) {
    table(tableName);
    return {
      select: (columns) => makeThenable(new FakeQueryBuilder(tableName, 'select')).select(columns),
      insert: (payload) => makeThenable(new FakeQueryBuilder(tableName, 'insert', payload)),
      upsert: (payload) => makeThenable(new FakeQueryBuilder(tableName, 'insert', payload)),
      update: (payload) => makeThenable(new FakeQueryBuilder(tableName, 'update', payload)),
      delete: () => makeThenable(new FakeQueryBuilder(tableName, 'delete')),
    };
  }

  /**
   * `rpc` lives on the client in supabase-js v2 — NOT on the `from()` builder.
   * The previous fake exposed it on `from()`, so `deletionGuards.ts` was never
   * actually exercised. Returns `{ data, error }` and never rejects.
   */
  rpc(fn, params = {}) {
    calls.rpc.push({ fn, params });
    return Promise.resolve().then(() => {
      const injected = failures.rpc.get(fn);
      if (injected) return { data: null, error: supabaseError(injected) };
      if (failures.rpcEmpty.has(fn)) return { data: [], error: null };
      const handler = RPC_HANDLERS[fn];
      if (!handler) {
        return {
          data: null,
          error: supabaseError(`Could not find the function public.${fn} in the schema cache`, 'PGRST202'),
        };
      }
      // Postgres set-returning functions come back as an array of rows.
      return { data: [handler(params)], error: null };
    });
  }

  channel(name) {
    const chan = {
      on: () => chan,
      subscribe: () => chan,
      unsubscribe: () => Promise.resolve('ok'),
      topic: name,
    };
    return chan;
  }

  removeAllChannels() { return Promise.resolve([]); }
  removeChannel() { return Promise.resolve('ok'); }
}

/** Seed rows straight into a table without going through the store layer. */
function seedFakeTable(tableName, records) {
  const store = table(tableName);
  for (const record of records) store.set(record.id, { ...record });
}

function resetFakeSupabase() {
  for (const key of Object.keys(fakeDb)) delete fakeDb[key];
  // Every entry is a Map or a Set; both expose clear().
  for (const key of Object.keys(failures)) failures[key].clear();
  for (const key of Object.keys(calls)) calls[key].length = 0;
}

/** Force a specific operation on a table to return a Supabase error. */
function failOperation(operation, tableName, message = 'فشل مُحاكى من Supabase.') {
  if (!failures[operation]) throw new Error(`عملية غير معروفة: ${operation}`);
  failures[operation].set(tableName, message);
}

function clearFailure(operation, tableName) {
  failures[operation]?.delete(tableName);
}

/** Force an RPC to error (simulates the functions not existing in production). */
function failRpc(fn, message = 'Could not find the function in the schema cache') {
  failures.rpc.set(fn, message);
}

/** Force an RPC to return an empty payload (malformed guard response). */
function failRpcWithEmptyPayload(fn) {
  failures.rpcEmpty.add(fn);
}

module.exports = {
  FakeSupabaseClient,
  resetFakeSupabase,
  seedFakeTable,
  failOperation,
  clearFailure,
  failRpc,
  failRpcWithEmptyPayload,
  fakeDb,
  calls,
};
