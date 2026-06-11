const test = require('node:test');
const assert = require('node:assert/strict');
class MemoryStorage { constructor() { this.values = new Map(); } get length() { return this.values.size; } key(i) { return [...this.values.keys()][i] ?? null; } getItem(k) { return this.values.has(k) ? this.values.get(k) : null; } setItem(k, v) { this.values.set(k, String(v)); } removeItem(k) { this.values.delete(k); } clear() { this.values.clear(); } }
global.localStorage = new MemoryStorage();
const { obligationsStore } = require('./.compiled/features/obligations/storage.js');
const { settlementAllocationsStore } = require('./.compiled/features/settlement-allocations/storage.js');
const { settlementsStore } = require('./.compiled/features/settlements/storage.js');
const { recordSettlement, reverseSettlement } = require('./.compiled/features/settlements/workflow.js');
function reset() { global.localStorage.clear(); obligationsStore.reset(); settlementsStore.reset(); }
function obligation() { return obligationsStore.create({ project_id: 'project-1', partner_id: 'partner-1', direction: 'payable', amount: 100, currency: 'EGP', amount_egp: 100, status: 'open' }); }
test('posting creates allocation and reversal preserves history without active effect', () => { reset(); const item = obligation(); const settlement = recordSettlement(item.id, { amount: 40, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' }); assert.equal(settlementAllocationsStore.getBySettlement(settlement.id).length, 1); assert.equal(settlementAllocationsStore.getActiveTotalByObligation(item.id, settlementsStore.getAll()), 40); reverseSettlement(settlement.id, 'إلغاء سند خاطئ'); assert.equal(settlementAllocationsStore.getBySettlement(settlement.id).length, 1); assert.equal(settlementAllocationsStore.getActiveTotalByObligation(item.id, settlementsStore.getAll()), 0); });
