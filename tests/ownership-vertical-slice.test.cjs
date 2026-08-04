const test = require('node:test');
const assert = require('node:assert/strict');

const {
  resetWorkspace,
  calls,
} = require('./helpers/setup.cjs');

const ownershipService = require('./.compiled/features/ownership/service.js');
const ownershipModel = require('./.compiled/features/ownership/model.js');
const ownershipStorage = require('./.compiled/features/ownership/storage.js');
const { computeProjectProfitability } = require('./.compiled/core/lib/profitability.js');

const project = {
  id: 'project-ownership-1',
  sector_id: 'real-estate',
  name_ar: 'مشروع الملكية',
  name_en: 'Ownership Project',
  status: 'active',
  start_date: '2026-01-01',
  base_currency: 'EGP',
  created_at: '2026-01-01T00:00:00.000Z',
  updated_at: '2026-01-01T00:00:00.000Z',
};
const partnerA = { id: 'partner-a', name_ar: 'الشريك أ', name_en: 'Partner A', category: 'equity_partner', created_at: '2026-01-01T00:00:00.000Z' };
const partnerB = { id: 'partner-b', name_ar: 'الشريك ب', name_en: 'Partner B', category: 'equity_partner', created_at: '2026-01-01T00:00:00.000Z' };

async function seedBase(extra = {}) {
  await resetWorkspace({
    projects: [project],
    partners: [partnerA, partnerB],
    project_partners: [],
    equity_change_events: [],
    partner_ledger_entries: [],
    distributions: [],
    distribution_allocations: [],
    transactions: [],
    obligations: [],
    ...extra,
  });
}

test('ownership RPC payloads use a stable caller request id and typed server params', () => {
  const payload = ownershipService.buildChangeOwnershipParams({
    requestId: '11111111-1111-4111-8111-111111111111',
    project_id: project.id,
    partner_id: partnerA.id,
    effective_date: '2026-02-01',
    new_pct: 60,
    change_type: 'entry',
    reason: 'تعاقد',
  });
  assert.equal(payload.p_request_id, '11111111-1111-4111-8111-111111111111');
  assert.equal(payload.p_project_id, project.id);
  assert.equal(payload.p_change_type, 'entry');
  assert.equal(payload.p_new_pct, 60);
});

test('ownership RPC success rehydrates stores and duplicate request id does not duplicate rows', async () => {
  await seedBase();
  const input = {
    requestId: '22222222-2222-4222-8222-222222222222',
    project_id: project.id,
    partner_id: partnerA.id,
    effective_date: '2026-01-01',
    new_pct: 60,
    change_type: 'entry',
    reason: 'initial entry',
  };

  const first = await ownershipService.changeOwnership(input);
  const second = await ownershipService.changeOwnership(input);

  assert.equal(first.equity_change_event_id, second.equity_change_event_id);
  assert.equal(ownershipStorage.equityChangeEventsStorage.getAll().length, 1);
  assert.equal(ownershipStorage.partnerLedgerEntriesStorage.getAll().length, 0);
  assert.equal(calls.rpc.filter((call) => call.fn === 'change_ownership_atomic').length, 2);
});

test('ownership RPC failure rehydrates authoritative state and translates the validation error', async () => {
  await seedBase({
    project_partners: [{ id: 'pp-existing', project_id: project.id, partner_id: partnerA.id, equity_pct: 80, effective_from: '2026-01-01' }],
  });

  await assert.rejects(
    ownershipService.changeOwnership({
      requestId: '33333333-3333-4333-8333-333333333333',
      project_id: project.id,
      partner_id: partnerB.id,
      effective_date: '2026-01-02',
      new_pct: 30,
      change_type: 'entry',
      reason: 'too much',
    }),
    (error) => error.kind === 'validation' && /100%/.test(error.message_ar),
  );
  assert.deepEqual(
    ownershipStorage.equityChangeEventsStorage.getAll(),
    [],
    'failed RPC must not leave optimistic history in the store',
  );
  assert.equal(ownershipModel.summarizeOwnership(ownershipModel.getOwnershipRowsAsOf(
    [{ id: 'pp-existing', project_id: project.id, partner_id: partnerA.id, equity_pct: 80, effective_from: '2026-01-01' }],
    project.id,
    '2026-01-02',
  )).assigned_pct, 80);
});

test('distribution RPC freezes allocations and creates partner entitlement ledger rows', async () => {
  await seedBase({
    project_partners: [
      { id: 'pp-a', project_id: project.id, partner_id: partnerA.id, equity_pct: 60, effective_from: '2026-01-01' },
      { id: 'pp-b', project_id: project.id, partner_id: partnerB.id, equity_pct: 40, effective_from: '2026-01-01' },
    ],
  });

  const result = await ownershipService.createProfitDistribution({
    requestId: '44444444-4444-4444-8444-444444444444',
    project_id: project.id,
    distribution_date: '2026-04-01',
    ownership_as_of_date: '2026-02-01',
    total_amount: 1000,
    currency: 'EGP',
    fx_rate: 1,
    notes: 'quarterly',
  });

  const allocations = ownershipStorage.distributionAllocationsStorage.getByDistribution(result.distribution_id);
  assert.equal(allocations.reduce((sum, item) => sum + item.allocated_amount, 0), 1000);
  assert.deepEqual(allocations.map((item) => item.equity_pct_snapshot).sort((a, b) => b - a), [60, 40]);
  assert.equal(ownershipStorage.partnerLedgerEntriesStorage.getAll().filter((entry) => entry.entry_type === 'distribution_entitlement').length, 2);
});

test('profitability slices partner entitlement by transaction date and keeps distributions separate from expenses', () => {
  const projectPartners = [
    { id: 'pp-a-1', project_id: project.id, partner_id: partnerA.id, equity_pct: 100, effective_from: '2026-01-01', effective_to: '2026-06-30' },
    { id: 'pp-a-2', project_id: project.id, partner_id: partnerA.id, equity_pct: 50, effective_from: '2026-07-01' },
    { id: 'pp-b-1', project_id: project.id, partner_id: partnerB.id, equity_pct: 50, effective_from: '2026-07-01' },
  ];
  const transactions = [
    { id: 't-jan', project_id: project.id, direction: 'income', category: 'sale', amount: 100, currency: 'EGP', fx_rate: 1, amount_egp: 100, transaction_date: '2026-02-01', created_at: '', updated_at: '' },
    { id: 't-aug', project_id: project.id, direction: 'income', category: 'sale', amount: 100, currency: 'EGP', fx_rate: 1, amount_egp: 100, transaction_date: '2026-08-01', created_at: '', updated_at: '' },
  ];
  const distributions = [{ id: 'dist-1', project_id: project.id, distribution_date: '2026-09-01', ownership_as_of_date: '2026-08-01', total_amount: 80, currency: 'EGP', fx_rate: 1, total_amount_egp: 80, status: 'approved', created_by: 'u', created_at: '' }];

  const report = computeProjectProfitability(project, transactions, [], projectPartners, [partnerA, partnerB], {
    as_of_date: '2026-09-30',
    distributions,
    distributionAllocations: [],
    partnerLedgerEntries: [],
  });

  assert.equal(report.total_expense_egp, 0, 'distribution must not reduce operational expenses');
  assert.equal(report.distributed_profit_egp, 80);
  assert.equal(report.undistributed_profit_egp, 120);
  assert.equal(report.partner_splits.find((split) => split.partner_id === partnerA.id).share_egp, 150);
  assert.equal(report.partner_splits.find((split) => split.partner_id === partnerB.id).share_egp, 50);
});

test('production portfolio/project screens use the ownership RPC boundary instead of direct project_partner writes', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const root = path.resolve(__dirname, '..');
  const portfolio = fs.readFileSync(path.join(root, 'src/features/portfolio/PortfolioHub.tsx'), 'utf8');
  const projectDetail = fs.readFileSync(path.join(root, 'src/features/projects/ProjectDetailPage.tsx'), 'utf8');

  assert.match(portfolio, /changeOwnership/);
  assert.match(projectDetail, /changeOwnership/);
  assert.doesNotMatch(portfolio, /projectPartnersStore\.create/);
  assert.doesNotMatch(projectDetail, /projectPartnersStore\.create/);
});
