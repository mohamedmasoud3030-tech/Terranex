const test = require('node:test');
const assert = require('node:assert/strict');

const {
  validateFinanceSearch,
  validateGovernanceSearch,
  validateIntelligenceSearch,
  validateOperationsSearch,
  validatePortfolioSearch,
} = require('./.compiled/core/routing/hubSearch.js');
const {
  financeHandoffTarget,
  governanceHandoffTarget,
  intelligenceFinanceTarget,
  operationsHandoffTarget,
  portfolioHandoffTarget,
} = require('./.compiled/features/integration/handoffs.js');

test('canonical search validators retain known context and discard invalid workspace or sector values', () => {
  assert.deepEqual(
    validatePortfolioSearch({ workspace: 'projects', project: 'project-1', unknown: 'drop' }),
    { workspace: 'projects', project: 'project-1' },
  );
  assert.deepEqual(
    validateOperationsSearch({ workspace: 'events', sector: 'agriculture', asset: 'asset-1' }),
    { workspace: 'events', sector: 'agriculture', asset: 'asset-1' },
  );
  assert.deepEqual(
    validateOperationsSearch({ workspace: 'tabs-are-not-a-workspace', sector: 'mining' }),
    {},
  );
  assert.deepEqual(
    validateFinanceSearch({ workspace: 'settlements', obligation: 'obligation-1' }),
    { workspace: 'settlements', obligation: 'obligation-1' },
  );
  assert.deepEqual(
    validateIntelligenceSearch({ workspace: 'profitability', from: '2026-01-01', to: '2026-06-30' }),
    { workspace: 'profitability', from: '2026-01-01', to: '2026-06-30' },
  );
  assert.deepEqual(
    validateGovernanceSearch({ workspace: 'documents', type: 'contract', expiry: 'expiring' }),
    { workspace: 'documents', type: 'contract', expiry: 'expiring' },
  );
});

test('portfolio handoffs preserve project, asset, partner, workspace, and intent', () => {
  assert.deepEqual(
    portfolioHandoffTarget({
      target: 'finance',
      workspace: 'transactions',
      context: { projectId: 'project-1', assetId: 'asset-1', partnerId: 'partner-1' },
      intent: 'create-transaction',
    }),
    {
      to: '/finance',
      search: {
        workspace: 'transactions',
        project: 'project-1',
        asset: 'asset-1',
        partner: 'partner-1',
        sector: undefined,
        intent: 'create-transaction',
      },
    },
  );
  assert.equal(
    portfolioHandoffTarget({
      target: 'intelligence',
      workspace: 'partner-statement',
      context: { partnerId: 'partner-1' },
      intent: 'open-statement',
    }).search.workspace,
    'statement',
  );
});

test('operations and finance handoffs do not silently post and keep source identity', () => {
  assert.deepEqual(
    operationsHandoffTarget({
      destination: 'finance',
      intent: 'create-or-link-transaction',
      projectId: 'project-1',
      assetId: 'asset-1',
      eventId: 'event-1',
      eventType: 'harvest',
    }),
    {
      to: '/finance',
      search: {
        workspace: 'transactions',
        project: 'project-1',
        asset: 'asset-1',
        event: 'event-1',
        intent: 'create-or-link-transaction',
      },
    },
  );
  assert.deepEqual(
    financeHandoffTarget({
      destination: 'governance',
      intent: 'inspect-related',
      entityId: 'document-1',
      entityType: 'document',
    }),
    {
      to: '/governance',
      search: {
        workspace: 'documents',
        inspect: 'document-1',
        intent: 'inspect-related',
      },
    },
  );
});

test('governance findings and Intelligence drill-down map to the owning hub', () => {
  assert.equal(
    governanceHandoffTarget({
      destination: 'operations',
      entityId: 'event-1',
      relationship: 'asset',
    }).to,
    '/operations',
  );
  assert.deepEqual(
    intelligenceFinanceTarget({
      displayCurrency: 'EGP',
      projectId: 'project-1',
      partnerId: 'partner-1',
      dateFrom: '2026-01-01',
      dateTo: '2026-06-30',
    }),
    {
      to: '/finance',
      search: {
        workspace: 'obligations',
        project: 'project-1',
        asset: undefined,
        partner: 'partner-1',
        from: '2026-01-01',
        to: '2026-06-30',
      },
    },
  );
});
