const test = require('node:test');
const assert = require('node:assert/strict');
const { resetWorkspace, awaitHydration, failOperation } = require('./helpers/setup.cjs');

const { obligationsStore, obligationsHydration } = require('./.compiled/features/obligations/storage.js');
const { documentsStore, documentsHydration } = require('./.compiled/features/documents/storage.js');
const { settlementsStore, settlementsHydration } = require('./.compiled/features/settlements/storage.js');
const { settlementAllocationsHydration } = require('./.compiled/features/settlement-allocations/storage.js');
const { recordSettlement, reverseSettlement } = require('./.compiled/features/settlements/workflow.js');

async function resetStores(seed = {}) {
  await resetWorkspace(seed);
  await awaitHydration(
    obligationsHydration, documentsHydration, settlementsHydration, settlementAllocationsHydration,
  );
}

function makeObligation(overrides = {}) {
  return obligationsStore.create({
    project_id: 'project-1', partner_id: 'partner-1', direction: 'payable',
    amount: 100, currency: 'EGP', amount_egp: 100, status: 'open', ...overrides,
  });
}

test('settlement records drive obligation balance and status', async () => {
  await resetStores();
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

test('reversal requires a reason and preserves timeline history', async () => {
  await resetStores();
  const obligation = makeObligation();
  const settlement = recordSettlement(obligation.id, { amount: 100, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' });
  assert.throws(() => reverseSettlement(settlement.id, ''));
  const reversed = reverseSettlement(settlement.id, 'إلغاء سند خاطئ');
  assert.equal(reversed.status, 'reversed');
  assert.equal(obligationsStore.getById(obligation.id).status, 'open');
  assert.equal(obligationsStore.getById(obligation.id).amount_settled_egp, 0);
  assert.equal(settlementsStore.getByObligation(obligation.id).length, 1);
});

test('written-off and disputed obligations cannot receive settlements', async () => {
  await resetStores();
  const input = { amount: 10, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' };
  assert.throws(() => recordSettlement(makeObligation({ status: 'written_off' }).id, input));
  assert.throws(() => recordSettlement(makeObligation({ status: 'disputed' }).id, input));
});

test('receipt must match settlement and remains protected from deletion', async () => {
  await resetStores();
  const obligation = makeObligation();
  const receipt = documentsStore.create({ project_id: 'project-1', partner_id: 'partner-1', type: 'receipt', title_ar: 'إيصال دفعة' });
  const invoice = documentsStore.create({ project_id: 'project-1', partner_id: 'partner-1', type: 'invoice', title_ar: 'فاتورة' });
  assert.throws(() => recordSettlement(obligation.id, { amount: 10, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash', receipt_document_id: invoice.id }));
  recordSettlement(obligation.id, { amount: 10, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash', receipt_document_id: receipt.id });

  // The receipt guard is a server-side RPC over persisted rows, so the write
  // has to reach the fake DB before the guard can see it.
  await settlementsHydration.flush();
  await assert.rejects(() => documentsStore.remove(receipt.id), /تسويات: 1/);
});

test('obligations with settlement history cannot be deleted', async () => {
  await resetStores();
  const obligation = makeObligation();
  recordSettlement(obligation.id, { amount: 10, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' });
  assert.throws(() => obligationsStore.remove(obligation.id));
});

test('a rejected settlement write is not reported as a local success', async () => {
  await resetStores();
  const obligation = makeObligation();
  await obligationsHydration.flush();

  failOperation('insert', 'settlements', 'new row violates row-level security policy');
  recordSettlement(obligation.id, { amount: 25, currency: 'EGP', fx_rate: 1, settlement_date: '2026-06-01', payment_method: 'cash' });

  await assert.rejects(() => settlementsHydration.flush(), /row-level security/);
  assert.equal(settlementsStore.getAll().length, 0, 'يجب التراجع عن التسوية بعد رفض Supabase.');
});

test('settlement state does not bleed between tests', async () => {
  await resetStores();
  assert.equal(settlementsStore.getAll().length, 0);
  assert.equal(obligationsStore.getAll().length, 0);
  assert.equal(documentsStore.getAll().length, 0);
});
