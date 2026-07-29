const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildPortfolioOverview,
  filterAssets,
  filterPartners,
  filterProjects,
  validateEquityAddition,
} = require('./.compiled/features/portfolio/model.js');
const {
  assetHandoff,
  partnerHandoff,
  projectHandoff,
} = require('./.compiled/features/portfolio/contracts.js');

const projects = [
  {
    id: 'project-1',
    sector_id: 'real-estate',
    name_ar: 'أرض المرسى',
    name_en: 'Marina Land',
    status: 'active',
    start_date: '2026-01-01',
    base_currency: 'EGP',
    created_at: '2026-01-01',
    updated_at: '2026-01-01',
  },
  {
    id: 'project-2',
    sector_id: 'livestock',
    name_ar: 'قطيع الشمال',
    name_en: 'North Herd',
    status: 'on_hold',
    start_date: '2026-02-01',
    base_currency: 'OMR',
    created_at: '2026-02-01',
    updated_at: '2026-02-01',
  },
];

const assets = [
  {
    id: 'asset-1',
    project_id: 'project-1',
    sector_id: 'real-estate',
    type: 'land',
    name_ar: 'قطعة أ',
    name_en: 'Plot A',
    acquisition_date: '2026-01-01',
    acquisition_cost: 100,
    acquisition_currency: 'EGP',
    acquisition_cost_egp: 100,
    status: 'owned',
    created_at: '2026-01-01',
  },
  {
    id: 'asset-orphan',
    project_id: 'missing-project',
    sector_id: 'livestock',
    type: 'herd',
    name_ar: 'قطيع غير مربوط',
    name_en: 'Unlinked herd',
    acquisition_date: '2026-02-01',
    acquisition_cost: 50,
    acquisition_currency: 'OMR',
    acquisition_cost_egp: 5000,
    status: 'leased',
    created_at: '2026-02-01',
  },
];

const partners = [
  { id: 'partner-1', name_ar: 'محمد', name_en: 'Mohamed', category: 'equity_partner', created_at: '2026-01-01' },
  { id: 'partner-2', name_ar: 'مورد', name_en: 'Supplier', category: 'counterparty', counterparty_role: 'supplier', created_at: '2026-01-01' },
  { id: 'partner-unlinked', name_ar: 'شريك غير مربوط', category: 'equity_partner', created_at: '2026-01-01' },
];

const links = [
  { id: 'link-1', project_id: 'project-1', partner_id: 'partner-1', equity_pct: 60, effective_from: '2026-01-01' },
  { id: 'link-ended', project_id: 'project-1', partner_id: 'partner-2', equity_pct: 90, effective_from: '2025-01-01', effective_to: '2025-12-31' },
];

test('portfolio filters preserve project, sector, type, status, category, and bilingual search context', () => {
  assert.deepEqual(filterProjects(projects, { query: 'marina', sector: 'real-estate', status: 'active' }).map((item) => item.id), ['project-1']);
  assert.deepEqual(filterProjects(projects, { query: 'الشمال', sector: 'all', status: 'all' }).map((item) => item.id), ['project-2']);
  assert.deepEqual(filterAssets(assets, { projectId: 'project-1', sector: 'real-estate', type: 'land', status: 'owned' }).map((item) => item.id), ['asset-1']);
  assert.deepEqual(filterPartners(partners, { query: 'supplier', category: 'counterparty' }).map((item) => item.id), ['partner-2']);
});

test('portfolio overview uses real records and surfaces missing relations without inventing data', () => {
  const result = buildPortfolioOverview(projects, assets, partners, links);
  assert.equal(result.projectCount, 2);
  assert.equal(result.activeProjectCount, 1);
  assert.deepEqual(result.projectBySector, { 'real-estate': 1, agriculture: 0, livestock: 1 });
  assert.equal(result.activeAssetCount, 2);
  assert.equal(result.partnerCount, 3);
  assert.equal(result.missingRelationCount, 2);
  assert.deepEqual(
    result.attention.map((item) => `${item.entity}:${item.reason}`).sort(),
    ['asset:missing-project', 'partner:unlinked-equity-partner', 'project:on-hold'],
  );
});

test('equity validation counts only active links and prevents totals above 100 percent', () => {
  assert.deepEqual(validateEquityAddition(links, 'project-1', 40), {
    allocated: 60,
    remaining: 40,
    valid: true,
  });
  assert.equal(validateEquityAddition(links, 'project-1', 40.01).valid, false);
  assert.equal(validateEquityAddition(links, 'project-1', 0).valid, false);
});

test('typed portfolio handoffs preserve prefilled context without silent financial posting', () => {
  assert.deepEqual(projectHandoff('project-1', 'real-estate', 'create-transaction'), {
    target: 'finance',
    workspace: 'transactions',
    context: { projectId: 'project-1', sector: 'real-estate' },
    intent: 'create-transaction',
  });
  assert.deepEqual(assetHandoff('project-2', 'asset-herd', 'livestock', 'create-event'), {
    target: 'operations',
    workspace: 'events',
    context: { projectId: 'project-2', assetId: 'asset-herd', sector: 'livestock' },
    intent: 'create-event',
  });
  assert.deepEqual(partnerHandoff('partner-1', 'open-statement'), {
    target: 'intelligence',
    workspace: 'partner-statement',
    context: { partnerId: 'partner-1' },
    intent: 'open-statement',
  });
});
