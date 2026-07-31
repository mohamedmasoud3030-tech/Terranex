const test = require('node:test');
const assert = require('node:assert/strict');
const { resetWorkspace, awaitHydration, failOperation, failRpc } = require('./helpers/setup.cjs');

const { transactionsStore, transactionsHydration } = require('./.compiled/features/transactions/storage.js');
const { documentsStore, documentsHydration } = require('./.compiled/features/documents/storage.js');
const { projectsHydration } = require('./.compiled/features/projects/storage.js');
const { partnersHydration } = require('./.compiled/features/partners/storage.js');

const SEED = {
  projects: [
    { id: 'project-1', name_ar: 'مشروع أول', created_at: '2026-01-01T00:00:00.000Z' },
    { id: 'project-2', name_ar: 'مشروع ثان', created_at: '2026-01-02T00:00:00.000Z' },
  ],
  partners: [
    { id: 'partner-1', name_ar: 'شريك أول', created_at: '2026-01-01T00:00:00.000Z' },
    { id: 'partner-2', name_ar: 'شريك ثان', created_at: '2026-01-02T00:00:00.000Z' },
  ],
  documents: [
    { id: 'document-1', project_id: 'project-1', type: 'contract', title_ar: 'عقد أول', created_at: '2026-01-01T00:00:00.000Z' },
    { id: 'document-2', project_id: 'project-1', type: 'receipt', title_ar: 'إيصال ثان', created_at: '2026-01-02T00:00:00.000Z' },
    { id: 'document-other-project', project_id: 'project-2', type: 'contract', title_ar: 'عقد مشروع آخر', created_at: '2026-01-03T00:00:00.000Z' },
  ],
  obligations: [],
  operational_events: [],
};

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

function documentById(id) {
  return documentsStore.getAll().find((document) => document.id === id);
}

async function reset(seed = SEED) {
  await resetWorkspace(seed);
  await awaitHydration(transactionsHydration, documentsHydration, projectsHydration, partnersHydration);
}

test('transaction storage requires real project, partner, and supporting document references', async () => {
  await reset();
  assert.throws(() => transactionsStore.create(input({ project_id: '' })), /مشروع/);
  assert.throws(() => transactionsStore.create(input({ partner_id: undefined })), /طرف أو شريك/);
  assert.throws(() => transactionsStore.create(input({ document_id: undefined })), /وثيقة داعمة/);
  assert.throws(() => transactionsStore.create(input({ project_id: 'missing-project' })), /المشروع.*غير موجود/);
  assert.throws(() => transactionsStore.create(input({ partner_id: 'missing-partner' })), /الشريك.*غير موجود/);
  assert.throws(() => transactionsStore.create(input({ document_id: 'missing-document' })), /الوثيقة.*غير موجودة/);
});

test('transaction storage rejects cross-project documents and already-bound documents', async () => {
  await reset();
  assert.throws(() => transactionsStore.create(input({ document_id: 'document-other-project' })), /نفس مشروع/);
  const created = transactionsStore.create(input());
  assert.throws(() => transactionsStore.create(input({ document_id: 'document-1' })), /مرتبطة بمعاملة أخرى/);
  assert.equal(documentById('document-1').transaction_id, created.id);
});

test('transaction storage rejects invalid amount and foreign exchange rate', async () => {
  await reset();
  assert.throws(() => transactionsStore.create(input({ amount: 0 })), /أكبر من صفر/);
  assert.throws(() => transactionsStore.create(input({ amount: Infinity })), /أكبر من صفر/);
  assert.throws(() => transactionsStore.create(input({ currency: 'USD', fx_rate: 0 })), /سعر الصرف/);
  assert.throws(() => transactionsStore.create(input({ currency: 'USD', fx_rate: Infinity })), /سعر الصرف/);
});

test('EGP transactions force rate one and recompute stored EGP amount', async () => {
  await reset();
  const created = transactionsStore.create(input({ amount: 125, fx_rate: 88, amount_egp: 9999 }));
  assert.equal(created.fx_rate, 1);
  assert.equal(created.amount_egp, 125);
});

test('foreign transactions recompute stored EGP amount from amount and exchange rate', async () => {
  await reset();
  const created = transactionsStore.create(input({ amount: 10, currency: 'USD', fx_rate: 50, amount_egp: 1 }));
  assert.equal(created.fx_rate, 50);
  assert.equal(created.amount_egp, 500);
});

test('foreign transactions with a fractional exchange rate round amount_egp to the nearest piaster', async () => {
  await reset();
  // 1234.56 * 47.35 = 58456.415999999997... in raw IEEE754 float — must round to 58456.42,
  // not the unrounded value, or downstream settlement equality checks against Postgres
  // `numeric` will never match. See core/lib/format.ts:toEgp.
  const created = transactionsStore.create(input({ amount: 1234.56, currency: 'USD', fx_rate: 47.35, amount_egp: 1 }));
  assert.equal(created.amount_egp, 58456.42);
});

test('updates normalize values and move the reverse document link atomically', async () => {
  await reset();
  const created = transactionsStore.create(input({ amount: 10, currency: 'USD', fx_rate: 50, amount_egp: 1 }));
  transactionsStore.update(created.id, { currency: 'EGP', amount: 200, fx_rate: 30, amount_egp: 9999, document_id: 'document-2' });
  const updated = transactionsStore.getAll()[0];
  assert.equal(updated.fx_rate, 1);
  assert.equal(updated.amount_egp, 200);
  assert.equal(updated.document_id, 'document-2');
  assert.equal(documentById('document-1').transaction_id, undefined);
  assert.equal(documentById('document-2').transaction_id, created.id);
});

test('removing an unlinked transaction releases its supporting document', async () => {
  await reset();
  const created = transactionsStore.create(input());
  await transactionsStore.remove(created.id);
  assert.equal(transactionsStore.getAll().length, 0);
  assert.equal(documentById('document-1').transaction_id, undefined);
});

test('removing a transaction is blocked when obligations or operational events depend on it', async () => {
  await reset();
  const created = transactionsStore.create(input());

  await resetWorkspaceKeepingTransaction(created);
  await assert.rejects(() => transactionsStore.remove(created.id), /التزامات: 1/);
  assert.equal(documentById('document-1').transaction_id, created.id);
});

/**
 * Re-seeds the workspace with a dependent obligation, keeping the transaction
 * and its bound document exactly as the previous step left them. The guard is
 * an RPC over server-side rows, so the blocker has to exist in the fake DB.
 */
async function resetWorkspaceKeepingTransaction(transaction) {
  const documents = documentsStore.getAll().map((document) => ({ ...document }));
  await reset({
    ...SEED,
    documents,
    transactions: [{ ...transaction }],
    obligations: [{ id: 'obligation-1', source_transaction_id: transaction.id }],
  });
}

test('removing a transaction is blocked by linked operational events', async () => {
  await reset();
  const created = transactionsStore.create(input());
  const documents = documentsStore.getAll().map((document) => ({ ...document }));

  await reset({
    ...SEED,
    documents,
    transactions: [{ ...created }],
    operational_events: [{ id: 'event-1', linked_transaction_id: created.id }],
  });

  await assert.rejects(() => transactionsStore.remove(created.id), /أحداث تشغيلية: 1/);
  assert.equal(documentById('document-1').transaction_id, created.id);
});

test('deletion guard fails closed when the Supabase RPC is unavailable', async () => {
  await reset();
  const created = transactionsStore.create(input());

  // Production today: guard_transaction_deletion does not exist server-side.
  failRpc('guard_transaction_deletion');

  await assert.rejects(() => transactionsStore.remove(created.id), /تعذر التحقق من الروابط التشغيلية/);
  assert.equal(transactionsStore.getAll().length, 1, 'المعاملة يجب أن تبقى عند فشل حارس الحذف.');
});

test('a rejected Supabase write does not leave a fake local success', async () => {
  await reset();
  failOperation('insert', 'transactions', 'new row violates row-level security policy');

  const created = transactionsStore.create(input());
  // The optimistic cache shows it immediately — that is the documented tradeoff.
  assert.equal(transactionsStore.getAll().length, 1);

  // ...but flushing must surface the failure, and the cache must roll back to
  // server truth instead of silently claiming the row was saved.
  await assert.rejects(() => transactionsHydration.flush(), /row-level security/);
  assert.equal(transactionsStore.getAll().length, 0, 'يجب التراجع عن الكتابة المتفائلة بعد رفض Supabase.');
  assert.equal(transactionsStore.getById(created.id), undefined);
});
