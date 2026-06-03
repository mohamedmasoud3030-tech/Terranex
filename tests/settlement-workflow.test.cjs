const test = require('node:test');
const assert = require('node:assert/strict');

class MemoryStorage {
  constructor() { this.values = new Map(); }
  get length() { return this.values.size; }
  key(index) { return [...this.values.keys()][index] ?? null; }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
  clear() { this.values.clear(); }
}

global.localStorage = new MemoryStorage();
const { obligationsStore } = require('./.compiled/features/obligations/storage.js');
const { documentsStore } = require('./.compiled/features/documents/storage.js');
const { settlementsStore } = require('./.compiled/features/settlements/storage.js');
const { recordSettlement, reverseSettlement } = require('./.compiled/features/settlements/workflow.js');

function resetStores() {
  global.localStorage.clear();
  obligationsStore.reset();
  settlementsStore.reset();
  documentsStore.reset();
}

function makeObligation(overrides = {}) {
  return obligationsStore.create({ project_id: 'project-1', partner_id: 'partner-1', direction: 'payable', amount: 100, currency: 'EGP', amount_egp: 100, status: 'open', ...overrides });
}

test('settlement records drive obligation balance and status', () => {
  resetStores();
  const obligation = makeObligation();
  assert.throws(() => recordSettlement(obligation.id, { amount: 0, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' }));
  assert.throws(() => recordSettlement(obligation.id, { amount: 101, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' }));
  recordSettlement(obligation.id, { amount: 40, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash', reference_number: 'CASH-1' });
  assert.equal(obligationsStore.getById(obligation.id).status, 'partial');
  assert.equal(obligationsStore.getById(obligation.id).amount_settled_egp, 40);
  recordSettlement(obligation.id, { amount: 60, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-02', payment_method: 'bank_transfer', reference_number: 'BANK-2' });
  assert.equal(obligationsStore.getById(obligation.id).status, 'settled');
  assert.equal(settlementsStore.getByObligation(obligation.id).length, 2);
});

test('reversal requires a reason and preserves timeline history', () => {
  resetStores();
  const obligation = makeObligation();
  const settlement = recordSettlement(obligation.id, { amount: 100, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' });
  assert.throws(() => reverseSettlement(settlement.id, ''));
  const reversed = reverseSettlement(settlement.id, 'إلغاء سند خاطئ');
  assert.equal(reversed.status, 'reversed');
  assert.equal(obligationsStore.getById(obligation.id).status, 'open');
  assert.equal(obligationsStore.getById(obligation.id).amount_settled_egp, 0);
  assert.equal(settlementsStore.getByObligation(obligation.id).length, 1);
});

test('written-off and disputed obligations cannot receive settlements', () => {
  resetStores();
  const input = { amount: 10, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' };
  assert.throws(() => recordSettlement(makeObligation({ status: 'written_off' }).id, input));
  assert.throws(() => recordSettlement(makeObligation({ status: 'disputed' }).id, input));
});

test('receipt must match settlement and remains protected from deletion', () => {
  resetStores();
  const obligation = makeObligation();
  const receipt = documentsStore.create({ project_id: 'project-1', partner_id: 'partner-1', type: 'receipt', title_ar: 'إيصال دفعة' });
  const invoice = documentsStore.create({ project_id: 'project-1', partner_id: 'partner-1', type: 'invoice', title_ar: 'فاتورة' });
  assert.throws(() => recordSettlement(obligation.id, { amount: 10, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash', receipt_document_id: invoice.id }));
  recordSettlement(obligation.id, { amount: 10, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash', receipt_document_id: receipt.id });
  assert.throws(() => documentsStore.remove(receipt.id));
});

test('legacy running balances migrate once to explicit settlement records', () => {
  resetStores();
  global.localStorage.setItem('terranex.obligations.v1', JSON.stringify([{ id: 'obl-legacy', partner_id: 'partner-1', direction: 'payable', amount: 100, currency: 'EGP', amount_egp: 100, status: 'partial', amount_settled_egp: 35, created_at: '2026-01-01T00:00:00.000Z', updated_at: '2026-01-02T00:00:00.000Z' }]));
  const migrated = settlementsStore.getByObligation('obl-legacy');
  assert.equal(migrated.length, 1);
  assert.equal(migrated[0].amount_egp, 35);
  assert.equal(migrated[0].origin, 'legacy_balance_migration');
  assert.equal(settlementsStore.getByObligation('obl-legacy').length, 1);
});

test('obligations with settlement history cannot be deleted', () => {
  resetStores();
  const obligation = makeObligation();
  recordSettlement(obligation.id, { amount: 10, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' });
  assert.throws(() => obligationsStore.remove(obligation.id));
});
