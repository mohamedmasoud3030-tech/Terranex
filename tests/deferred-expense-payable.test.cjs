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
const { obligationsStore } = require('./.compiled/features/obligations/storage.js');
const { transactionsStore } = require('./.compiled/features/transactions/storage.js');
const {
  createTransactionWithOptionalPayable,
  updateTransactionWithLinkedPayable,
} = require('./.compiled/features/transactions/deferredExpenseWorkflow.js');

const PROJECTS_KEY = 'terranex.projects.v1';
const PARTNERS_KEY = 'terranex.partners.v1';
const DOCUMENTS_KEY = 'terranex.documents.v1';
const OBLIGATIONS_KEY = 'terranex.obligations.v1';
const EVENTS_KEY = 'terranex.operationalEvents.v1';

function read(key) { return JSON.parse(global.localStorage.getItem(key) || '[]'); }
function documentById(id) { return read(DOCUMENTS_KEY).find((document) => document.id === id); }
function obligationByTransactionId(id) { return read(OBLIGATIONS_KEY).find((obligation) => obligation.source_transaction_id === id); }
function input(overrides = {}) {
  return {
    project_id: 'project-1', partner_id: 'partner-1', document_id: 'document-1',
    direction: 'expense', category: 'feed', amount: 250, currency: 'EGP',
    fx_rate: 1, amount_egp: 250, transaction_date: '2026-01-01', ...overrides,
  };
}
function resetWorkspace() {
  global.localStorage.clear();
  global.localStorage.setItem(PROJECTS_KEY, JSON.stringify([{ id: 'project-1', name_ar: 'مشروع أول' }]));
  global.localStorage.setItem(PARTNERS_KEY, JSON.stringify([{ id: 'partner-1', name_ar: 'طرف أول' }]));
  global.localStorage.setItem(DOCUMENTS_KEY, JSON.stringify([
    { id: 'document-1', project_id: 'project-1', type: 'invoice', title_ar: 'فاتورة أولى', created_at: '2026-01-01T00:00:00.000Z' },
    { id: 'document-2', project_id: 'project-1', type: 'invoice', title_ar: 'فاتورة معدلة', created_at: '2026-01-02T00:00:00.000Z' },
  ]));
  global.localStorage.setItem(OBLIGATIONS_KEY, '[]');
  global.localStorage.setItem(EVENTS_KEY, '[]');
  transactionsStore.reset();
  obligationsStore.reset();
}

test('deferred expense workflow creates payable obligation linked to transaction and invoice', () => {
  resetWorkspace();
  const created = createTransactionWithOptionalPayable(input({ create_payable_obligation: true, payable_due_date: '2026-02-15' }));
  const obligations = read(OBLIGATIONS_KEY);
  assert.equal(obligations.length, 1);
  assert.equal(obligations[0].direction, 'payable');
  assert.equal(obligations[0].amount_egp, 250);
  assert.equal(obligations[0].due_date, '2026-02-15');
  assert.equal(obligations[0].source_transaction_id, created.id);
  assert.equal(obligations[0].document_id, 'document-1');
  assert.equal(documentById('document-1').transaction_id, created.id);
});

test('deferred expense validation rejects invalid requests before persistence', () => {
  resetWorkspace();
  assert.throws(() => createTransactionWithOptionalPayable(input({ direction: 'income', create_payable_obligation: true, payable_due_date: '2026-02-15' })), /مصروف/);
  assert.throws(() => createTransactionWithOptionalPayable(input({ create_payable_obligation: true })), /تاريخ استحقاق/);
  assert.equal(transactionsStore.getAll().length, 0);
  assert.equal(read(OBLIGATIONS_KEY).length, 0);
  assert.equal(documentById('document-1').transaction_id, undefined);
});

test('transaction storage remains obligation-agnostic when called directly', () => {
  resetWorkspace();
  const created = transactionsStore.create(input());
  assert.equal(transactionsStore.getAll().length, 1);
  assert.equal(read(OBLIGATIONS_KEY).length, 0);
  assert.equal(documentById('document-1').transaction_id, created.id);
});

test('updating deferred expense keeps linked payable amount and invoice synchronized', () => {
  resetWorkspace();
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

test('updating deferred expense cannot reduce payable below amount already settled', () => {
  resetWorkspace();
  const created = createTransactionWithOptionalPayable(input({ create_payable_obligation: true, payable_due_date: '2026-02-15' }));
  const payable = obligationByTransactionId(created.id);
  obligationsStore.settle(payable.id, 200);

  assert.throws(() => updateTransactionWithLinkedPayable(created.id, { amount: 150 }), /المبلغ المسدد/);
  assert.equal(transactionsStore.getById(created.id).amount_egp, 250);
  assert.equal(obligationByTransactionId(created.id).amount_egp, 250);
  assert.equal(obligationByTransactionId(created.id).amount_settled_egp, 200);
});
