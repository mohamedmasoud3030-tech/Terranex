const test = require('node:test');
const assert = require('node:assert/strict');

class MemoryStorage {
  constructor() { this.values = new Map(); }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
  clear() { this.values.clear(); }
}

global.localStorage = new MemoryStorage();
const { transactionsStore } = require('./.compiled/features/transactions/storage.js');

function input(overrides = {}) {
  return {
    project_id: 'project-1',
    partner_id: 'partner-1',
    document_id: 'document-1',
    direction: 'income',
    category: 'sale',
    amount: 100,
    currency: 'EGP',
    fx_rate: 99,
    amount_egp: 9999,
    transaction_date: '2026-01-01',
    ...overrides,
  };
}

test('transaction storage requires project, partner, and supporting document', () => {
  transactionsStore.reset();
  assert.throws(() => transactionsStore.create(input({ project_id: '' })), /مشروع/);
  assert.throws(() => transactionsStore.create(input({ partner_id: undefined })), /طرف أو شريك/);
  assert.throws(() => transactionsStore.create(input({ document_id: undefined })), /وثيقة داعمة/);
});

test('transaction storage rejects invalid amount and foreign exchange rate', () => {
  transactionsStore.reset();
  assert.throws(() => transactionsStore.create(input({ amount: 0 })), /أكبر من صفر/);
  assert.throws(() => transactionsStore.create(input({ amount: Infinity })), /أكبر من صفر/);
  assert.throws(() => transactionsStore.create(input({ currency: 'USD', fx_rate: 0 })), /سعر الصرف/);
  assert.throws(() => transactionsStore.create(input({ currency: 'USD', fx_rate: Infinity })), /سعر الصرف/);
});

test('EGP transactions force rate one and recompute stored EGP amount', () => {
  transactionsStore.reset();
  const created = transactionsStore.create(input({ amount: 125, fx_rate: 88, amount_egp: 9999 }));
  assert.equal(created.fx_rate, 1);
  assert.equal(created.amount_egp, 125);
});

test('foreign transactions recompute stored EGP amount from amount and exchange rate', () => {
  transactionsStore.reset();
  const created = transactionsStore.create(input({ amount: 10, currency: 'USD', fx_rate: 50, amount_egp: 1 }));
  assert.equal(created.fx_rate, 50);
  assert.equal(created.amount_egp, 500);
});

test('updates normalize derived EGP values again', () => {
  transactionsStore.reset();
  const created = transactionsStore.create(input({ amount: 10, currency: 'USD', fx_rate: 50, amount_egp: 1 }));
  transactionsStore.update(created.id, { currency: 'EGP', amount: 200, fx_rate: 30, amount_egp: 9999 });
  const updated = transactionsStore.getAll()[0];
  assert.equal(updated.fx_rate, 1);
  assert.equal(updated.amount_egp, 200);
});
