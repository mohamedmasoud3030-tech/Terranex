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

const { createTerranexBackup } = require('./.compiled/core/storage/backup.js');
const { obligationsStore } = require('./.compiled/features/obligations/storage.js');
const { settlementAllocationsStore } = require('./.compiled/features/settlement-allocations/storage.js');
const { settlementsStore } = require('./.compiled/features/settlements/storage.js');

function reset() {
  global.localStorage.clear();
  obligationsStore.reset();
  settlementsStore.reset();
}

test('legacy settlement records migrate once to allocation records and enter backups', () => {
  reset();
  global.localStorage.setItem('terranex.obligations.v1', JSON.stringify([{
    id: 'obl-legacy',
    project_id: 'project-1',
    partner_id: 'partner-1',
    direction: 'payable',
    amount: 25,
    currency: 'EGP',
    amount_egp: 25,
    amount_settled_egp: 25,
    status: 'settled',
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-01-01T00:00:00.000Z',
  }]));
  global.localStorage.setItem('terranex.settlements.v1', JSON.stringify([{
    id: 'set-legacy',
    obligation_id: 'obl-legacy',
    amount: 25,
    currency: 'EGP',
    fx_rate: 1,
    amount_egp: 25,
    settlement_date: '2026-01-01',
    payment_method: 'unknown',
    status: 'active',
    origin: 'legacy_balance_migration',
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-01-01T00:00:00.000Z',
  }]));

  const firstRead = settlementAllocationsStore.getAll();
  const secondRead = settlementAllocationsStore.getAll();

  assert.equal(firstRead.length, 1);
  assert.equal(secondRead.length, 1);
  assert.equal(firstRead[0].settlement_id, 'set-legacy');
  assert.equal(firstRead[0].obligation_id, 'obl-legacy');
  assert.equal(firstRead[0].allocated_amount_egp, 25);
  assert.equal(firstRead[0].created_at, '2026-01-01T00:00:00.000Z');

  const backup = createTerranexBackup();
  assert.ok(backup.records['terranex.settlementAllocations.v1']);
});
