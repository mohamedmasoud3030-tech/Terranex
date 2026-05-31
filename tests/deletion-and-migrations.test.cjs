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
const guards = require('./.compiled/core/lib/deletionGuards.js');
const { runAppStorageMigrations } = require('./.compiled/core/storage/migrations.js');

function set(key, value) { localStorage.setItem(key, JSON.stringify(value)); }
function get(key) { return JSON.parse(localStorage.getItem(key) || 'null'); }

test('project deletion is blocked by linked operational records', () => {
  localStorage.clear();
  set('terranex.transactions.v2', [{ id: 'tx-1', project_id: 'project-1' }]);
  const result = guards.guardProjectDeletion('project-1');
  assert.equal(result.canDelete, false);
  assert.match(result.message_ar, /معاملات: 1/);
});

test('project deletion remains allowed when no linked records exist', () => {
  localStorage.clear();
  const result = guards.guardProjectDeletion('project-1');
  assert.equal(result.canDelete, true);
});

test('partner, asset, and document guards block linked entities', () => {
  localStorage.clear();
  set('terranex.obligations.v1', [{ id: 'obl-1', partner_id: 'partner-1', document_id: 'doc-1' }]);
  set('terranex.transactions.v2', [{ id: 'tx-1', asset_id: 'asset-1' }]);
  assert.equal(guards.guardPartnerDeletion('partner-1').canDelete, false);
  assert.equal(guards.guardAssetDeletion('asset-1').canDelete, false);
  assert.equal(guards.guardDocumentDeletion('doc-1').canDelete, false);
});

test('legacy migration converts safe records once without duplication', () => {
  localStorage.clear();
  set('terranex.financialRecords.v1', [
    { id: 'income-1', date: '2026-01-01', type: 'income', title: 'بيع', amount: 100, currency: 'EGP', project_id: 'project-1' },
    { id: 'payable-1', date: '2026-01-02', type: 'payable', title: 'فاتورة', amount: 50, currency: 'EGP', partner_id: 'partner-1' },
  ]);
  runAppStorageMigrations();
  runAppStorageMigrations();
  assert.equal(get('terranex.transactions.v2').length, 1);
  assert.equal(get('terranex.obligations.v1').length, 1);
  assert.equal(get('terranex.financialRecords.v1'), null);
  assert.deepEqual(get('terranex.migrations.v1').completed, ['legacy-financial-records-to-ledger-v1']);
});

test('legacy migration preserves unmappable records for audit review', () => {
  localStorage.clear();
  set('terranex.financialRecords.v1', [
    { id: 'unsafe-1', date: '2026-01-01', type: 'income', title: 'سجل بلا مشروع', amount: 10, currency: 'EGP' },
  ]);
  runAppStorageMigrations();
  const audit = get('terranex.legacyFinancialRecords.audit.v1');
  assert.equal(audit.length, 1);
  assert.equal(get('terranex.financialRecords.v1').length, 1);
});
