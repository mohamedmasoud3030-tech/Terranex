const test = require('node:test');
const assert = require('node:assert/strict');
require('./helpers/setup.cjs');

const {
  computeFinanceOverview,
  filterObligations,
  filterTransactions,
} = require('./.compiled/features/finance/hubModel.js');
const { financeContextSearch } = require('./.compiled/features/finance/contracts.js');
const { FINANCE_ATOMICITY_NOTICE } = require('./.compiled/features/finance/financeWriteBoundary.js');

const project = {
  id: 'p1', sector_id: 'real-estate', name_ar: 'مشروع', name_en: 'Project',
  status: 'active', start_date: '2026-01-01', base_currency: 'EGP',
  created_at: '2026-01-01', updated_at: '2026-01-01',
};
const transactions = [
  { id: 't1', project_id: 'p1', asset_id: 'a1', partner_id: 'party1', operational_event_id: 'event1', direction: 'income', category: 'sale', amount: 1000, currency: 'EGP', fx_rate: 1, amount_egp: 1000, transaction_date: '2026-07-01' },
  { id: 't2', project_id: 'p1', partner_id: 'party2', direction: 'expense', category: 'maintenance', amount: 200, currency: 'EGP', fx_rate: 1, amount_egp: 200, transaction_date: '2026-07-20' },
];
const obligations = [
  { id: 'o1', project_id: 'p1', partner_id: 'party1', direction: 'receivable', amount: 500, amount_egp: 500, amount_settled_egp: 100, currency: 'EGP', status: 'partial', due_date: '2026-07-01' },
  { id: 'o2', project_id: 'p1', partner_id: 'party2', direction: 'payable', amount: 300, amount_egp: 300, amount_settled_egp: 0, currency: 'EGP', status: 'open', due_date: '2026-08-15' },
];

test('finance filters preserve project, asset, partner, event, date, direction, and category context', () => {
  assert.deepEqual(filterTransactions(transactions, {
    projectId: 'p1',
    assetId: 'a1',
    partnerId: 'party1',
    eventId: 'event1',
    direction: 'income',
    category: 'sale',
    dateFrom: '2026-07-01',
    dateTo: '2026-07-10',
  }).map((item) => item.id), ['t1']);
});

test('obligation direction, status, aging, and party remain filters in one workspace', () => {
  assert.deepEqual(filterObligations(obligations, {
    projectId: 'p1',
    partnerId: 'party1',
    direction: 'receivable',
    status: 'partial',
    aging: 'overdue',
    asOf: '2026-07-29',
  }).map((item) => item.id), ['o1']);
  assert.deepEqual(filterObligations(obligations, {
    direction: 'payable',
    status: 'open',
    aging: 'not-due',
    asOf: '2026-07-29',
  }).map((item) => item.id), ['o2']);
});

test('finance overview reuses canonical profitability and aging sources', () => {
  const result = computeFinanceOverview([project], transactions, obligations, '2026-07-29');
  assert.equal(result.incomeEgp, 1000);
  assert.equal(result.expenseEgp, 200);
  assert.equal(result.receivablesEgp, 400);
  assert.equal(result.payablesEgp, 300);
  assert.equal(result.cashExposureEgp, 100);
  assert.equal(result.actionable.length, 2);
  assert.equal(result.aging.rows.length, 2);
});

test('typed finance handoff is shareable and atomicity limitation is explicit', () => {
  assert.equal(
    financeContextSearch({
      projectId: 'p1',
      assetId: 'a1',
      partnerId: 'party1',
      eventId: 'event1',
      obligationId: 'o1',
    }),
    'project=p1&asset=a1&partner=party1&event=event1&obligation=o1',
  );
  assert.match(FINANCE_ATOMICITY_NOTICE.en, /not a database transaction/);
  assert.match(FINANCE_ATOMICITY_NOTICE.ar, /ليست معاملة قاعدة بيانات ذرية/);
});
