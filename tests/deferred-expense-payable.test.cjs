const test = require('node:test');
const assert = require('node:assert/strict');
const { resetWorkspace, awaitHydration } = require('./helpers/setup.cjs');

const { obligationsStore, obligationsHydration } = require('./.compiled/features/obligations/storage.js');
const { transactionsStore, transactionsHydration } = require('./.compiled/features/transactions/storage.js');
const { documentsStore, documentsHydration } = require('./.compiled/features/documents/storage.js');
const { projectsHydration } = require('./.compiled/features/projects/storage.js');
const { partnersHydration } = require('./.compiled/features/partners/storage.js');
const { settlementsHydration } = require('./.compiled/features/settlements/storage.js');
const { settlementAllocationsHydration } = require('./.compiled/features/settlement-allocations/storage.js');
const {
  createTransactionWithOptionalPayable,
  updateTransactionWithLinkedPayable,
} = require('./.compiled/features/transactions/deferredExpenseWorkflow.js');

const SEED = {
  projects: [{ id: 'project-1', name_ar: 'مشروع أول', created_at: '2026-01-01T00:00:00.000Z' }],
  partners: [{ id: 'partner-1', name_ar: 'طرف أول', created_at: '2026-01-01T00:00:00.000Z' }],
  documents: [
    { id: 'document-1', project_id: 'project-1', type: 'invoice', title_ar: 'فاتورة أولى', created_at: '2026-01-01T00:00:00.000Z' },
    { id: 'document-2', project_id: 'project-1', type: 'invoice', title_ar: 'فاتورة معدلة', created_at: '2026-01-02T00:00:00.000Z' },
  ],
  obligations: [],
  operational_events: [],
};

function input(overrides = {}) {
  return {
    project_id: 'project-1', partner_id: 'partner-1', document_id: 'document-1',
    direction: 'expense', category: 'feed', amount: 250, currency: 'EGP',
    fx_rate: 1, amount_egp: 250, transaction_date: '2026-01-01', ...overrides,
  };
}

function documentById(id) {
  return documentsStore.getAll().find((document) => document.id === id);
}

function obligationByTransactionId(id) {
  return obligationsStore.getAll().find((obligation) => obligation.source_transaction_id === id);
}

async function reset() {
  await resetWorkspace(SEED);
  await awaitHydration(
    transactionsHydration, obligationsHydration, documentsHydration,
    projectsHydration, partnersHydration, settlementsHydration, settlementAllocationsHydration,
  );
}

test('deferred expense workflow creates payable obligation linked to transaction and invoice', async () => {
  await reset();
  const created = createTransactionWithOptionalPayable(input({ create_payable_obligation: true, payable_due_date: '2026-02-15' }));
  const obligations = obligationsStore.getAll();
  assert.equal(obligations.length, 1);
  assert.equal(obligations[0].direction, 'payable');
  assert.equal(obligations[0].amount_egp, 250);
  assert.equal(obligations[0].due_date, '2026-02-15');
  assert.equal(obligations[0].source_transaction_id, created.id);
  assert.equal(obligations[0].document_id, 'document-1');
  assert.equal(documentById('document-1').transaction_id, created.id);
});

test('deferred expense validation rejects invalid requests before persistence', async () => {
  await reset();
  assert.throws(() => createTransactionWithOptionalPayable(input({ direction: 'income', create_payable_obligation: true, payable_due_date: '2026-02-15' })), /مصروف/);
  assert.throws(() => createTransactionWithOptionalPayable(input({ create_payable_obligation: true })), /تاريخ استحقاق/);
  assert.equal(transactionsStore.getAll().length, 0);
  assert.equal(obligationsStore.getAll().length, 0);
  assert.equal(documentById('document-1').transaction_id, undefined);
});

test('transaction storage remains obligation-agnostic when called directly', async () => {
  await reset();
  const created = transactionsStore.create(input());
  assert.equal(transactionsStore.getAll().length, 1);
  assert.equal(obligationsStore.getAll().length, 0);
  assert.equal(documentById('document-1').transaction_id, created.id);
});

test('updating deferred expense keeps linked payable amount and invoice synchronized', async () => {
  await reset();
  const created = createTransactionWithOptionalPayable(input({ create_payable_obligation: true, payable_due_date: '2026-02-15' }));
  const updated = updateTransactionWithLinkedPayable(created.id, { amount: 400, document_id: 'document-2', notes: 'قيمة معدلة' });
  const payable = obligationByTransactionId(created.id);

  assert.equal(updated.amount_egp, 400);
  assert.equal(updated.document_id, 'document-2');
  assert.equal(payable.amount, 400);
  assert.equal(payable.amount_egp, 400);
  assert.equal(payable.document_id, 'document-2');
  assert.equal(payable.notes, 'قيمة معدلة');
  assert.equal(documentById('document-1').transaction_id, undefined);
  assert.equal(documentById('document-2').transaction_id, created.id);
});

test('updating deferred expense cannot reduce payable below amount already settled', async () => {
  await reset();
  const created = createTransactionWithOptionalPayable(input({ create_payable_obligation: true, payable_due_date: '2026-02-15' }));
  const payable = obligationByTransactionId(created.id);
  obligationsStore.settle(payable.id, 200);

  assert.throws(() => updateTransactionWithLinkedPayable(created.id, { amount: 150 }), /المبلغ المسدد/);
  assert.equal(transactionsStore.getById(created.id).amount_egp, 250);
  assert.equal(obligationByTransactionId(created.id).amount_egp, 250);
  assert.equal(obligationByTransactionId(created.id).amount_settled_egp, 200);
});

test('deferred expense state does not bleed between tests', async () => {
  await reset();
  assert.equal(transactionsStore.getAll().length, 0);
  assert.equal(obligationsStore.getAll().length, 0);
  assert.equal(documentById('document-1').transaction_id, undefined);
});
