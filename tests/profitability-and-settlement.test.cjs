const test = require('node:test');
const assert = require('node:assert/strict');

const { computeProjectProfitability, computeGlobalSummary } = require('./.compiled/core/lib/profitability.js');

class MemoryStorage {
  constructor() { this.values = new Map(); }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
  clear() { this.values.clear(); }
}

global.localStorage = new MemoryStorage();
const { obligationsStore } = require('./.compiled/features/obligations/storage.js');
const { settlementsStore } = require('./.compiled/features/settlements/storage.js');
const { recordSettlement } = require('./.compiled/features/settlements/workflow.js');

const project = {
  id: 'project-1', sector_id: 'real-estate', name_ar: 'مشروع أول', name_en: 'First project',
  status: 'active', start_date: '2026-01-01', base_currency: 'EGP', created_at: '2026-01-01', updated_at: '2026-01-01',
};
const transactions = [
  { id: 'tx-1', project_id: project.id, direction: 'income', category: 'sale', amount: 1000, currency: 'EGP', fx_rate: 1, amount_egp: 1000, transaction_date: '2026-01-01', created_at: '2026-01-01', updated_at: '2026-01-01' },
  { id: 'tx-2', project_id: project.id, direction: 'expense', category: 'maintenance', amount: 250, currency: 'EGP', fx_rate: 1, amount_egp: 250, transaction_date: '2026-01-02', created_at: '2026-01-02', updated_at: '2026-01-02' },
];
const obligations = [
  { id: 'obl-1', project_id: project.id, partner_id: 'partner-1', direction: 'receivable', amount: 500, currency: 'EGP', amount_egp: 500, status: 'open', amount_settled_egp: 0, created_at: '2026-01-01', updated_at: '2026-01-01' },
  { id: 'obl-2', project_id: project.id, partner_id: 'partner-1', direction: 'payable', amount: 400, currency: 'EGP', amount_egp: 400, status: 'partial', amount_settled_egp: 100, created_at: '2026-01-01', updated_at: '2026-01-01' },
  { id: 'obl-3', project_id: project.id, partner_id: 'partner-1', direction: 'payable', amount: 900, currency: 'EGP', amount_egp: 900, status: 'settled', amount_settled_egp: 900, created_at: '2026-01-01', updated_at: '2026-01-01' },
  { id: 'obl-4', project_id: project.id, partner_id: 'partner-1', direction: 'receivable', amount: 300, currency: 'EGP', amount_egp: 300, status: 'written_off', amount_settled_egp: 0, created_at: '2026-01-01', updated_at: '2026-01-01' },
];

test('profitability keeps accounting profit separate from open cash exposure', () => {
  const result = computeProjectProfitability(
    project,
    transactions,
    obligations,
    [{ id: 'pp-1', project_id: project.id, partner_id: 'partner-1', equity_pct: 40, effective_from: '2026-01-01' }],
    [{ id: 'partner-1', name_ar: 'شريك', category: 'equity_partner', created_at: '2026-01-01' }],
  );
  assert.equal(result.total_income_egp, 1000);
  assert.equal(result.total_expense_egp, 250);
  assert.equal(result.gross_profit_egp, 750);
  assert.equal(result.net_profit_egp, 750);
  assert.equal(result.open_receivables_egp, 500);
  assert.equal(result.open_payables_egp, 300);
  assert.equal(result.cash_exposure_egp, 200);
  assert.equal(result.partner_splits[0].share_egp, 300);
});

test('global summary aggregates projects and excludes closed obligations from exposure', () => {
  const second = { ...project, id: 'project-2', sector_id: 'agriculture', name_ar: 'مشروع ثان', name_en: 'Second project' };
  const result = computeGlobalSummary(
    [project, second],
    [...transactions, { ...transactions[0], id: 'tx-3', project_id: second.id, amount: 200, amount_egp: 200 }],
    obligations,
  );
  assert.equal(result.total_income_egp, 1200);
  assert.equal(result.total_expense_egp, 250);
  assert.equal(result.gross_profit_egp, 950);
  assert.equal(result.cash_exposure_egp, 200);
  assert.equal(result.by_sector.agriculture.gross_profit_egp, 200);
});

test('obligation settlement validates boundaries and supports partial then final settlement', () => {
  obligationsStore.reset();
  settlementsStore.reset();
  const created = obligationsStore.create({ partner_id: 'partner-1', direction: 'payable', amount: 100, currency: 'EGP', amount_egp: 100, status: 'open' });
  const input = { currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' };
  assert.throws(() => recordSettlement(created.id, { ...input, amount: 0 }));
  assert.throws(() => recordSettlement(created.id, { ...input, amount: -1 }));
  assert.throws(() => recordSettlement(created.id, { ...input, amount: Infinity }));
  assert.throws(() => recordSettlement(created.id, { ...input, amount: 101 }));
  recordSettlement(created.id, { ...input, amount: 40 });
  assert.equal(obligationsStore.getAll()[0].status, 'partial');
  assert.equal(obligationsStore.getAll()[0].amount_settled_egp, 40);
  recordSettlement(created.id, { ...input, amount: 60 });
  assert.equal(obligationsStore.getAll()[0].status, 'settled');
  assert.throws(() => recordSettlement(created.id, { ...input, amount: 1 }));
});

test('written-off obligations cannot be settled', () => {
  obligationsStore.reset();
  settlementsStore.reset();
  const created = obligationsStore.create({ partner_id: 'partner-1', direction: 'payable', amount: 50, currency: 'EGP', amount_egp: 50, status: 'written_off' });
  assert.throws(() => recordSettlement(created.id, { amount: 10, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' }));
});
