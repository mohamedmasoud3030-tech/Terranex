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

const { randomUUID } = require('node:crypto');

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

function rpcCache(fn, requestId, compute) {
  const key = `${fn}:${requestId}`;
  const cache = table('__rpc_idempotency');
  if (cache.has(key)) return cache.get(key);
  const result = compute();
  cache.set(key, result);
  return result;
}

function activeProjectPartner(projectId, partnerId) {
  return rows('project_partners').find((row) => row.project_id === projectId && row.partner_id === partnerId && !row.effective_to);
}

function ownershipRowsAsOf(projectId, asOfDate) {
  return rows('project_partners')
    .filter((row) => row.project_id === projectId && row.effective_from <= asOfDate && (!row.effective_to || row.effective_to >= asOfDate))
    .sort((a, b) => a.effective_from.localeCompare(b.effective_from));
}

function roundMoney(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function ledgerEffect(entry) {
  switch (entry.entry_type) {
    case 'capital_contribution':
    case 'distribution_entitlement':
    case 'correction':
      return entry.amount_egp;
    case 'withdrawal':
    case 'distribution_payment':
      return -entry.amount_egp;
    case 'reversal':
      return 0;
    default:
      return 0;
  }
}

function otherActiveOwnershipPct(projectId, partnerId) {
  return rows('project_partners')
    .filter((row) => row.project_id === projectId && row.partner_id !== partnerId && !row.effective_to)
    .reduce((sum, row) => sum + Number(row.equity_pct), 0);
}

function validateFakeOwnershipChange(params, currentPct, newPct, otherPct) {
  const rules = [
    () => newPct < 0 || newPct > 100 ? 'equity percentage must be between 0 and 100' : null,
    () => params.p_change_type === 'entry' && currentPct > 0 ? 'cannot create entry: partner already has active ownership' : null,
    () => params.p_change_type === 'entry' && newPct <= 0 ? 'entry must set a positive percentage' : null,
    () => params.p_change_type === 'exit' && currentPct === 0 ? 'cannot exit: partner has no active ownership' : null,
    () => params.p_change_type === 'exit' && newPct > 0 ? 'exit must set percentage to 0' : null,
    () => params.p_change_type === 'increase' && newPct <= currentPct ? 'increase must set a higher percentage than current' : null,
    () => params.p_change_type === 'decrease' && newPct >= currentPct ? 'decrease must set a lower percentage than current' : null,
    () => otherPct + newPct > 100 ? 'total equity would exceed 100%' : null,
  ];
  const message = rules.map((rule) => rule()).find(Boolean);
  if (message) throw new Error(message);
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
  record_stock_adjustment_atomic: (params) => {
    const adj = params.p_adjustment ?? {};
    const id = adj.id;
    const asset = rows('assets').find((row) => row.id === adj.asset_id);
    const quantityBefore = Number(asset?.quantity ?? 0);
    const valueBefore = Number(asset?.current_value_egp ?? 0);
    const quantityDelta = Number(adj.quantity_delta ?? 0);
    const valueDelta = Number(adj.value_egp_delta ?? 0);
    const quantityAfter = quantityBefore + quantityDelta;
    const valueAfter = valueBefore + valueDelta;
    table('stock_adjustments').set(id, {
      id,
      asset_id: adj.asset_id,
      project_id: adj.project_id,
      adjustment_date: adj.adjustment_date,
      quantity_before: quantityBefore,
      quantity_after: quantityAfter,
      value_egp_before: valueBefore,
      value_egp_after: valueAfter,
      reason: adj.reason,
      notes: adj.notes,
      created_at: new Date().toISOString(),
    });
    if (asset) {
      table('assets').set(asset.id, { ...asset, quantity: quantityAfter, current_value_egp: valueAfter });
    }
    return {
      adjustment_id: id,
      quantity_before: quantityBefore,
      quantity_after: quantityAfter,
      value_egp_before: valueBefore,
      value_egp_after: valueAfter,
    };
  },
  change_ownership_atomic: (params) => rpcCache('change_ownership_atomic', params.p_request_id, () => {
    const current = activeProjectPartner(params.p_project_id, params.p_partner_id);
    const currentPct = Number(current?.equity_pct ?? 0);
    const newPct = Number(params.p_new_pct);
    const otherPct = otherActiveOwnershipPct(params.p_project_id, params.p_partner_id);
    validateFakeOwnershipChange(params, currentPct, newPct, otherPct);
    if (current) {
      table('project_partners').set(current.id, { ...current, effective_to: params.p_effective_date });
    }
    const ppId = newPct > 0 ? randomUUID() : null;
    if (ppId) {
      table('project_partners').set(ppId, {
        id: ppId,
        project_id: params.p_project_id,
        partner_id: params.p_partner_id,
        equity_pct: newPct,
        effective_from: params.p_effective_date,
        notes: params.p_notes,
      });
    }
    const eventId = randomUUID();
    table('equity_change_events').set(eventId, {
      id: eventId,
      project_id: params.p_project_id,
      partner_id: params.p_partner_id,
      effective_date: params.p_effective_date,
      previous_pct: currentPct,
      new_pct: newPct,
      change_type: params.p_change_type,
      reason: params.p_reason,
      notes: params.p_notes,
      created_by: 'fake-user',
      created_at: new Date().toISOString(),
    });
    return {
      equity_change_event_id: eventId,
      project_partner_id: ppId,
      previous_pct: currentPct,
      new_pct: newPct,
      total_equity_allocated: otherPct + newPct,
    };
  }),
  get_ownership_as_of: (params) => ownershipRowsAsOf(params.p_project_id, params.p_as_of_date).map((row) => ({
    partner_id: row.partner_id,
    equity_pct: row.equity_pct,
    effective_from: row.effective_from,
    effective_to: row.effective_to ?? null,
    project_partner_id: row.id,
  })),
  record_partner_ledger_entry_atomic: (params) => rpcCache('record_partner_ledger_entry_atomic', params.p_request_id, () => {
    if (Number(params.p_amount) <= 0) throw new Error('ledger entry amount must be positive');
    if (params.p_reversal_of_id && !rows('partner_ledger_entries').some((row) => row.id === params.p_reversal_of_id)) throw new Error('reversal target entry not found or belongs to a different owner');
    const id = randomUUID();
    const amountEgp = Number(params.p_amount) * Number(params.p_fx_rate);
    const row = {
      id,
      project_id: params.p_project_id,
      partner_id: params.p_partner_id,
      entry_type: params.p_entry_type,
      amount: Number(params.p_amount),
      currency: params.p_currency,
      fx_rate: Number(params.p_fx_rate),
      amount_egp: amountEgp,
      posting_date: params.p_posting_date,
      supporting_document_id: params.p_supporting_document_id,
      related_equity_event_id: params.p_related_equity_event_id,
      related_distribution_id: params.p_related_distribution_id,
      notes: params.p_notes,
      reversal_of_id: params.p_reversal_of_id,
      created_by: 'fake-user',
      created_at: new Date().toISOString(),
    };
    table('partner_ledger_entries').set(id, row);
    return { ledger_entry_id: id, amount_egp: amountEgp, entry_type: params.p_entry_type };
  }),
  record_distribution_atomic: (params) => rpcCache('record_distribution_atomic', params.p_request_id, () => {
    if (Number(params.p_total_amount) <= 0) throw new Error('distribution amount must be positive');
    if (params.p_ownership_as_of_date > params.p_distribution_date) throw new Error('ownership_as_of_date cannot be after distribution_date');
    const ownership = ownershipRowsAsOf(params.p_project_id, params.p_ownership_as_of_date);
    if (ownership.length === 0) throw new Error('no ownership rows for distribution');
    const distributionId = randomUUID();
    const total = Number(params.p_total_amount);
    const fx = Number(params.p_fx_rate);
    table('distributions').set(distributionId, {
      id: distributionId,
      project_id: params.p_project_id,
      distribution_date: params.p_distribution_date,
      ownership_as_of_date: params.p_ownership_as_of_date,
      total_amount: total,
      currency: params.p_currency,
      fx_rate: fx,
      total_amount_egp: total * fx,
      status: 'draft',
      notes: params.p_notes,
      supporting_document_id: params.p_supporting_document_id,
      created_by: 'fake-user',
      created_at: new Date().toISOString(),
    });
    const allocations = ownership.map((row) => ({ row, amount: roundMoney(total * Number(row.equity_pct) / 100) }));
    const sum = roundMoney(allocations.reduce((acc, item) => acc + item.amount, 0));
    const diff = roundMoney(total - sum);
    let largest = 0;
    for (let index = 1; index < allocations.length; index += 1) if (allocations[index].amount > allocations[largest].amount) largest = index;
    allocations[largest].amount = roundMoney(allocations[largest].amount + diff);
    for (const allocation of allocations) {
      const allocationId = randomUUID();
      table('distribution_allocations').set(allocationId, {
        id: allocationId,
        distribution_id: distributionId,
        partner_id: allocation.row.partner_id,
        equity_pct_snapshot: allocation.row.equity_pct,
        allocated_amount: allocation.amount,
        allocated_amount_egp: allocation.amount * fx,
        status: 'due',
      });
      const ledgerId = randomUUID();
      table('partner_ledger_entries').set(ledgerId, {
        id: ledgerId,
        project_id: params.p_project_id,
        partner_id: allocation.row.partner_id,
        entry_type: 'distribution_entitlement',
        amount: allocation.amount,
        currency: params.p_currency,
        fx_rate: fx,
        amount_egp: allocation.amount * fx,
        posting_date: params.p_distribution_date,
        related_distribution_id: distributionId,
        notes: params.p_notes,
        created_by: 'fake-user',
        created_at: new Date().toISOString(),
      });
    }
    return { distribution_id: distributionId, total_amount: total, total_amount_egp: total * fx, status: 'draft' };
  }),
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
      const result = handler(params);
      // Postgres set-returning functions come back as an array of rows; scalar
      // jsonb functions are wrapped like the existing guard RPC contract.
      return { data: Array.isArray(result) ? result : [result], error: null };
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
