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

const PROJECTS_KEY = 'terranex.projects.v1';
const PARTNERS_KEY = 'terranex.partners.v1';
const DOCUMENTS_KEY = 'terranex.documents.v1';
const OBLIGATIONS_KEY = 'terranex.obligations.v1';
const EVENTS_KEY = 'terranex.operationalEvents.v1';

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

function readDocuments() {
  return JSON.parse(global.localStorage.getItem(DOCUMENTS_KEY) || '[]');
}

function documentById(id) {
  return readDocuments().find((document) => document.id === id);
}

function resetWorkspace() {
  global.localStorage.clear();
  global.localStorage.setItem(PROJECTS_KEY, JSON.stringify([
    { id: 'project-1', name_ar: 'مشروع أول' },
    { id: 'project-2', name_ar: 'مشروع ثان' },
  ]));
  global.localStorage.setItem(PARTNERS_KEY, JSON.stringify([
    { id: 'partner-1', name_ar: 'شريك أول' },
    { id: 'partner-2', name_ar: 'شريك ثان' },
  ]));
  global.localStorage.setItem(DOCUMENTS_KEY, JSON.stringify([
    { id: 'document-1', project_id: 'project-1', type: 'contract', title_ar: 'عقد أول', created_at: '2026-01-01T00:00:00.000Z' },
    { id: 'document-2', project_id: 'project-1', type: 'receipt', title_ar: 'إيصال ثان', created_at: '2026-01-02T00:00:00.000Z' },
    { id: 'document-other-project', project_id: 'project-2', type: 'contract', title_ar: 'عقد مشروع آخر', created_at: '2026-01-03T00:00:00.000Z' },
  ]));
  global.localStorage.setItem(OBLIGATIONS_KEY, '[]');
  global.localStorage.setItem(EVENTS_KEY, '[]');
  transactionsStore.reset();
}

test('transaction storage requires real project, partner, and supporting document references', () => {
  resetWorkspace();
  assert.throws(() => transactionsStore.create(input({ project_id: '' })), /مشروع/);
  assert.throws(() => transactionsStore.create(input({ partner_id: undefined })), /طرف أو شريك/);
  assert.throws(() => transactionsStore.create(input({ document_id: undefined })), /وثيقة داعمة/);
  assert.throws(() => transactionsStore.create(input({ project_id: 'missing-project' })), /المشروع.*غير موجود/);
  assert.throws(() => transactionsStore.create(input({ partner_id: 'missing-partner' })), /الشريك.*غير موجود/);
  assert.throws(() => transactionsStore.create(input({ document_id: 'missing-document' })), /الوثيقة.*غير موجودة/);
});

test('transaction storage rejects cross-project documents and already-bound documents', () => {
  resetWorkspace();
  assert.throws(() => transactionsStore.create(input({ document_id: 'document-other-project' })), /نفس مشروع/);
  const created = transactionsStore.create(input());
  assert.throws(() => transactionsStore.create(input({ document_id: 'document-1' })), /مرتبطة بمعاملة أخرى/);
  assert.equal(documentById('document-1').transaction_id, created.id);
});

test('transaction storage rejects invalid amount and foreign exchange rate', () => {
  resetWorkspace();
  assert.throws(() => transactionsStore.create(input({ amount: 0 })), /أكبر من صفر/);
  assert.throws(() => transactionsStore.create(input({ amount: Infinity })), /أكبر من صفر/);
  assert.throws(() => transactionsStore.create(input({ currency: 'USD', fx_rate: 0 })), /سعر الصرف/);
  assert.throws(() => transactionsStore.create(input({ currency: 'USD', fx_rate: Infinity })), /سعر الصرف/);
});

test('EGP transactions force rate one and recompute stored EGP amount', () => {
  resetWorkspace();
  const created = transactionsStore.create(input({ amount: 125, fx_rate: 88, amount_egp: 9999 }));
  assert.equal(created.fx_rate, 1);
  assert.equal(created.amount_egp, 125);
});

test('foreign transactions recompute stored EGP amount from amount and exchange rate', () => {
  resetWorkspace();
  const created = transactionsStore.create(input({ amount: 10, currency: 'USD', fx_rate: 50, amount_egp: 1 }));
  assert.equal(created.fx_rate, 50);
  assert.equal(created.amount_egp, 500);
});

test('updates normalize values and move the reverse document link atomically', () => {
  resetWorkspace();
  const created = transactionsStore.create(input({ amount: 10, currency: 'USD', fx_rate: 50, amount_egp: 1 }));
  transactionsStore.update(created.id, { currency: 'EGP', amount: 200, fx_rate: 30, amount_egp: 9999, document_id: 'document-2' });
  const updated = transactionsStore.getAll()[0];
  assert.equal(updated.fx_rate, 1);
  assert.equal(updated.amount_egp, 200);
  assert.equal(updated.document_id, 'document-2');
  assert.equal(documentById('document-1').transaction_id, undefined);
  assert.equal(documentById('document-2').transaction_id, created.id);
});

test('removing an unlinked transaction releases its supporting document', () => {
  resetWorkspace();
  const created = transactionsStore.create(input());
  transactionsStore.remove(created.id);
  assert.equal(transactionsStore.getAll().length, 0);
  assert.equal(documentById('document-1').transaction_id, undefined);
});

test('removing a transaction is blocked when obligations or operational events depend on it', () => {
  resetWorkspace();
  const created = transactionsStore.create(input());
  global.localStorage.setItem(OBLIGATIONS_KEY, JSON.stringify([{ id: 'obligation-1', source_transaction_id: created.id }]));
  assert.throws(() => transactionsStore.remove(created.id), /التزامات: 1/);
  assert.equal(documentById('document-1').transaction_id, created.id);

  global.localStorage.setItem(OBLIGATIONS_KEY, '[]');
  global.localStorage.setItem(EVENTS_KEY, JSON.stringify([{ id: 'event-1', linked_transaction_id: created.id }]));
  assert.throws(() => transactionsStore.remove(created.id), /أحداث تشغيلية: 1/);
  assert.equal(documentById('document-1').transaction_id, created.id);
});
