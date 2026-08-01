const test = require('node:test');
const assert = require('node:assert/strict');
require('./helpers/setup.cjs');

const {
  buildFilteredReportCsv,
  buildIntelligenceReport,
  filterReportRecords,
  reconcileIntelligenceReport,
  validateReportContext,
} = require('./.compiled/features/intelligence/reportModel.js');

const projects = [
  {
    id: 'project-real-estate',
    sector_id: 'real-estate',
    name_ar: 'العقار',
    name_en: 'Property',
    status: 'active',
    start_date: '2026-01-01',
    base_currency: 'EGP',
    created_at: '2026-01-01',
    updated_at: '2026-01-01',
  },
  {
    id: 'project-agriculture',
    sector_id: 'agriculture',
    name_ar: 'المزرعة',
    name_en: 'Farm',
    status: 'active',
    start_date: '2026-01-01',
    base_currency: 'EGP',
    created_at: '2026-01-01',
    updated_at: '2026-01-01',
  },
];

const partners = [
  { id: 'partner-1', name_ar: 'الشريك الأول', category: 'counterparty', created_at: '2026-01-01' },
  { id: 'partner-2', name_ar: 'الشريك الثاني', category: 'counterparty', created_at: '2026-01-01' },
];

function transaction(id, projectId, partnerId, direction, amount, date) {
  return {
    id,
    project_id: projectId,
    partner_id: partnerId,
    direction,
    category: direction === 'income' ? 'sale' : 'maintenance',
    amount,
    currency: 'EGP',
    fx_rate: 1,
    amount_egp: amount,
    transaction_date: date,
    created_at: `${date}T00:00:00.000Z`,
    updated_at: `${date}T00:00:00.000Z`,
  };
}

function obligation(id, projectId, partnerId, direction, amount, date) {
  return {
    id,
    project_id: projectId,
    partner_id: partnerId,
    direction,
    amount,
    currency: 'EGP',
    amount_egp: amount,
    due_date: date,
    status: 'partial',
    amount_settled_egp: 10,
    created_at: `${date}T00:00:00.000Z`,
    updated_at: `${date}T00:00:00.000Z`,
  };
}

const records = {
  projects,
  partners,
  projectPartners: [],
  assets: [
    {
      id: 'asset-real-estate',
      project_id: 'project-real-estate',
      sector_id: 'real-estate',
      type: 'building',
      name_ar: 'مبنى',
      name_en: 'Building',
      acquisition_date: '2026-01-01',
      acquisition_cost: 500,
      acquisition_currency: 'EGP',
      acquisition_cost_egp: 500,
      status: 'owned',
      created_at: '2026-01-01',
    },
    {
      id: 'asset-agriculture',
      project_id: 'project-agriculture',
      sector_id: 'agriculture',
      type: 'crop',
      name_ar: 'محصول',
      name_en: 'Crop',
      acquisition_date: '2026-01-01',
      acquisition_cost: 100,
      acquisition_currency: 'EGP',
      acquisition_cost_egp: 100,
      status: 'owned',
      quantity: 20,
      unit: 'طن',
      created_at: '2026-01-01',
    },
  ],
  transactions: [
    transaction('tx-income-real-estate', 'project-real-estate', 'partner-1', 'income', 1000, '2026-04-01'),
    transaction('tx-expense-real-estate', 'project-real-estate', 'partner-1', 'expense', 200, '2026-04-02'),
    transaction('tx-income-agriculture', 'project-agriculture', 'partner-2', 'income', 400, '2026-04-03'),
  ],
  obligations: [
    obligation('obligation-real-estate', 'project-real-estate', 'partner-1', 'receivable', 100, '2026-04-05'),
    obligation('obligation-agriculture', 'project-agriculture', 'partner-2', 'payable', 80, '2026-04-06'),
  ],
  settlements: [
    {
      id: 'settlement-active',
      obligation_id: 'obligation-real-estate',
      amount: 10,
      currency: 'EGP',
      fx_rate: 1,
      amount_egp: 10,
      settlement_date: '2026-04-07',
      payment_method: 'cash',
      status: 'active',
      origin: 'user',
      created_at: '2026-04-07T00:00:00.000Z',
      updated_at: '2026-04-07T00:00:00.000Z',
    },
    {
      id: 'settlement-reversed',
      obligation_id: 'obligation-real-estate',
      amount: 5,
      currency: 'EGP',
      fx_rate: 1,
      amount_egp: 5,
      settlement_date: '2026-04-08',
      payment_method: 'cash',
      status: 'reversed',
      origin: 'user',
      created_at: '2026-04-08T00:00:00.000Z',
      updated_at: '2026-04-08T00:00:00.000Z',
    },
  ],
  allocations: [
    {
      id: 'allocation-active',
      settlement_id: 'settlement-active',
      obligation_id: 'obligation-real-estate',
      allocated_amount_egp: 10,
      created_at: '2026-04-07T00:00:00.000Z',
    },
    {
      id: 'allocation-reversed',
      settlement_id: 'settlement-reversed',
      obligation_id: 'obligation-real-estate',
      allocated_amount_egp: 5,
      created_at: '2026-04-08T00:00:00.000Z',
    },
  ],
  events: [
    {
      id: 'event-agriculture',
      project_id: 'project-agriculture',
      asset_id: 'asset-agriculture',
      event_type: 'harvest',
      event_date: '2026-04-10',
      quantity_delta: 5,
      created_at: '2026-04-10',
    },
  ],
  adjustments: [],
  documents: [
    {
      id: 'document-real-estate',
      title_ar: 'عقد',
      document_type: 'contract',
      project_id: 'project-real-estate',
      partner_id: 'partner-1',
      issue_date: '2026-04-01',
      created_at: '2026-04-01',
      updated_at: '2026-04-01',
    },
  ],
};

test('one context filters projects, transactions, obligations, evidence, and settlement allocations', () => {
  const filtered = filterReportRecords(records, {
    sector: 'real-estate',
    partnerId: 'partner-1',
    dateFrom: '2026-04-01',
    dateTo: '2026-04-07',
    displayCurrency: 'EGP',
  });

  assert.deepEqual(filtered.projects.map((item) => item.id), ['project-real-estate']);
  assert.deepEqual(filtered.transactions.map((item) => item.id), [
    'tx-income-real-estate',
    'tx-expense-real-estate',
  ]);
  assert.deepEqual(filtered.obligations.map((item) => item.id), ['obligation-real-estate']);
  assert.deepEqual(filtered.documents.map((item) => item.id), ['document-real-estate']);
  assert.deepEqual(filtered.settlements.map((item) => item.id), ['settlement-active']);
  assert.deepEqual(filtered.allocations.map((item) => item.id), ['allocation-active']);
});

test('report context rejects an inverted date range before export', () => {
  assert.equal(
    validateReportContext({
      dateFrom: '2026-05-01',
      dateTo: '2026-04-30',
      displayCurrency: 'EGP',
    }),
    'The report start date must be on or before its end date.',
  );
  assert.equal(
    validateReportContext({
      dateFrom: '2026-04-01',
      dateTo: '2026-04-30',
      displayCurrency: 'EGP',
    }),
    undefined,
  );
});

test('executive, project, and sector reports reconcile from the canonical profitability engine', () => {
  const report = buildIntelligenceReport(
    records,
    { sector: 'all', displayCurrency: 'EGP' },
    '2026-04-30',
  );

  assert.equal(report.executive.total_income_egp, 1400);
  assert.equal(report.executive.total_expense_egp, 200);
  assert.deepEqual(reconcileIntelligenceReport(report), { income: true, expense: true });
  assert.equal(
    report.projects.reduce((sum, item) => sum + item.gross_profit_egp, 0),
    report.executive.gross_profit_egp,
  );
});

test('reconcile tolerates floating-point drift within a piaster fraction', () => {
  const drifted = {
    projects: [
      { total_income_egp: 0.1, total_expense_egp: 0 },
      { total_income_egp: 0.2, total_expense_egp: 0 },
    ],
    sectors: { 'real-estate': { total_income_egp: 0.3, total_expense_egp: 0 } },
    executive: { total_income_egp: 0.3, total_expense_egp: 0 },
  };
  // 0.1 + 0.2 === 0.30000000000000004, so strict === would report a false mismatch.
  assert.notEqual(0.1 + 0.2, 0.3);
  assert.deepEqual(reconcileIntelligenceReport(drifted), { income: true, expense: true });
});

test('obligation date filter includes rows at the end-of-day boundary of dateTo', () => {
  const boundaryRecords = {
    ...records,
    obligations: [
      {
        ...obligation('obligation-boundary', 'project-real-estate', 'partner-1', 'receivable', 50, '2026-04-07'),
        created_at: '2026-04-07T23:59:59.999Z',
      },
    ],
  };
  const filtered = filterReportRecords(boundaryRecords, {
    dateFrom: '2026-04-01',
    dateTo: '2026-04-07',
    displayCurrency: 'EGP',
  });
  assert.deepEqual(filtered.obligations.map((item) => item.id), ['obligation-boundary']);
});

test('statement is ordered and keeps reversed settlement evidence at zero active effect', () => {
  const report = buildIntelligenceReport(
    records,
    { sector: 'all', partnerId: 'partner-1', displayCurrency: 'EGP' },
    '2026-04-30',
  );
  const reversed = report.statement.entries.find(
    (item) => item.id === 'settlement-allocation:allocation-reversed',
  );

  assert.deepEqual(
    report.statement.entries.map((item) => item.entry_date),
    [...report.statement.entries.map((item) => item.entry_date)].sort(),
  );
  assert.equal(reversed.is_effective, false);
  assert.equal(reversed.debit_egp, 0);
  assert.equal(reversed.credit_egp, 0);
  assert.equal(report.statement.closing_balance_egp, 90);
});

test('asset position and CSV export use the same filtered report dataset', () => {
  const report = buildIntelligenceReport(
    records,
    { sector: 'agriculture', displayCurrency: 'EGP' },
    '2026-04-30',
  );
  const csv = buildFilteredReportCsv(report);

  assert.equal(report.assetPositions.length, 1);
  assert.equal(report.assetPositions[0].balance.quantity, 25);
  assert.match(csv, /income,400/);
  assert.doesNotMatch(csv, /income,1400/);
});
