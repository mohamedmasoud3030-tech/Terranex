const test = require('node:test');
const assert = require('node:assert/strict');
const { resetWorkspace, failRpc, failRpcWithEmptyPayload, calls } = require('./helpers/setup.cjs');

const guards = require('./.compiled/core/lib/deletionGuards.js');
const { runAppStorageMigrations } = require('./.compiled/core/storage/migrations.js');

function set(key, value) { localStorage.setItem(key, JSON.stringify(value)); }
function get(key) { return JSON.parse(localStorage.getItem(key) || 'null'); }

// ---------------------------------------------------------------------------
// Deletion guards. These are now Supabase RPC calls (`client.rpc(...)`), not
// localStorage scans, so every one of them is async and the blocking rows must
// live in the database — not in `localStorage`.
// ---------------------------------------------------------------------------

test('project deletion is blocked by linked operational records', async () => {
  await resetWorkspace({ transactions: [{ id: 'tx-1', project_id: 'project-1' }] });
  const result = await guards.guardProjectDeletion('project-1');
  assert.equal(result.canDelete, false);
  assert.match(result.message_ar, /معاملات: 1/);
});

test('project deletion remains allowed when no linked records exist', async () => {
  await resetWorkspace();
  const result = await guards.guardProjectDeletion('project-1');
  assert.equal(result.canDelete, true);
});

test('partner, asset, and document guards block linked entities', async () => {
  await resetWorkspace({
    obligations: [{ id: 'obl-1', partner_id: 'partner-1', document_id: 'doc-1' }],
    transactions: [{ id: 'tx-1', asset_id: 'asset-1' }],
  });
  assert.equal((await guards.guardPartnerDeletion('partner-1')).canDelete, false);
  assert.equal((await guards.guardAssetDeletion('asset-1')).canDelete, false);
  assert.equal((await guards.guardDocumentDeletion('doc-1')).canDelete, false);
});

test('guards send the exact RPC name and parameter the Postgres functions expect', async () => {
  await resetWorkspace();
  await guards.guardProjectDeletion('project-9');
  await guards.guardPartnerDeletion('partner-9');
  await guards.guardAssetDeletion('asset-9');
  await guards.guardDocumentDeletion('document-9');
  await guards.guardTransactionDeletion('transaction-9');

  assert.deepEqual(calls.rpc, [
    { fn: 'guard_project_deletion', params: { p_project_id: 'project-9' } },
    { fn: 'guard_partner_deletion', params: { p_partner_id: 'partner-9' } },
    { fn: 'guard_asset_deletion', params: { p_asset_id: 'asset-9' } },
    { fn: 'guard_document_deletion', params: { p_document_id: 'document-9' } },
    { fn: 'guard_transaction_deletion', params: { p_transaction_id: 'transaction-9' } },
  ]);
});

test('guards fail closed when the RPC errors instead of allowing the delete', async () => {
  await resetWorkspace();
  failRpc('guard_project_deletion', 'Could not find the function public.guard_project_deletion');
  const result = await guards.guardProjectDeletion('project-1');
  assert.equal(result.canDelete, false, 'فشل الـ RPC يجب ألا يسمح بالحذف أبداً.');
  assert.match(result.message_ar, /تعذر التحقق من الروابط التشغيلية/);
});

test('guards fail closed when the RPC returns an empty or malformed payload', async () => {
  await resetWorkspace();
  failRpcWithEmptyPayload('guard_document_deletion');
  const result = await guards.guardDocumentDeletion('doc-1');
  assert.equal(result.canDelete, false);
  assert.match(result.message_ar, /تعذر التحقق من الروابط التشغيلية/);
});

// ---------------------------------------------------------------------------
// Legacy localStorage migrations. These intentionally still operate on
// localStorage: they exist to drain pre-Supabase browser data. They are NOT
// part of the Supabase path and must keep working unchanged.
// ---------------------------------------------------------------------------

test('legacy migration converts safe records once without duplication', async () => {
  await resetWorkspace();
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

test('legacy migration preserves unmappable records for audit review', async () => {
  await resetWorkspace();
  set('terranex.financialRecords.v1', [
    { id: 'unsafe-1', date: '2026-01-01', type: 'income', title: 'سجل بلا مشروع', amount: 10, currency: 'EGP' },
  ]);
  runAppStorageMigrations();
  const audit = get('terranex.legacyFinancialRecords.audit.v1');
  assert.equal(audit.length, 1);
  assert.equal(get('terranex.financialRecords.v1').length, 1);
});

test('legacy localStorage migration never writes to Supabase', async () => {
  await resetWorkspace();
  const insertsBefore = calls.insert.length;
  set('terranex.financialRecords.v1', [
    { id: 'income-2', date: '2026-01-01', type: 'income', title: 'بيع', amount: 100, currency: 'EGP', project_id: 'project-1' },
  ]);
  runAppStorageMigrations();
  assert.equal(calls.insert.length, insertsBefore, 'ترحيل البيانات القديمة محلي فقط في هذه المرحلة.');
});
