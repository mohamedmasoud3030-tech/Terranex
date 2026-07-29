const test = require('node:test');
const assert = require('node:assert/strict');

const {
  BACKUP_COVERAGE,
  classifyDocumentExpiry,
  inspectOrphanReferences,
  inspectStore,
} = require('./.compiled/features/governance/dataHealth.js');

const empty = {
  projects: [],
  assets: [],
  partners: [],
  projectPartners: [],
  transactions: [],
  obligations: [],
  settlements: [],
  allocations: [],
  events: [],
  adjustments: [],
  documents: [],
};

test('data-health scan reports orphan relationships without mutating its snapshot', () => {
  const records = {
    ...empty,
    assets: [{ id: 'asset-1', project_id: 'missing-project' }],
    transactions: [{
      id: 'transaction-1',
      project_id: 'missing-project',
      asset_id: 'missing-asset',
      partner_id: 'missing-partner',
      document_id: 'missing-document',
    }],
    settlements: [{ id: 'settlement-1', obligation_id: 'missing-obligation' }],
    allocations: [{
      id: 'allocation-1',
      settlement_id: 'missing-settlement',
      obligation_id: 'missing-obligation',
    }],
  };
  const before = structuredClone(records);
  const findings = inspectOrphanReferences(records);

  assert.deepEqual(records, before);
  assert.deepEqual(findings.map((item) => item.code), [
    'allocation.obligation',
    'allocation.settlement',
    'asset.project',
    'settlement.obligation',
    'transaction.asset',
    'transaction.document',
    'transaction.partner',
    'transaction.project',
  ]);
  assert.ok(findings.every((item) => item.severity === 'error'));
});

test('store diagnostics expose hydration, early-read, and write failures honestly', () => {
  const diagnostic = inspectStore('transactions', {
    isLoaded: () => true,
    getLoadError: () => new Error('JWT expired'),
    getWriteError: () => new Error('RLS denied'),
    getReadsBeforeHydration: () => 3,
  });
  assert.deepEqual(diagnostic, {
    name: 'transactions',
    loaded: true,
    loadError: 'JWT expired',
    writeError: 'RLS denied',
    readsBeforeHydration: 3,
  });
});

test('expiry cues are deterministic at the 30-day boundary', () => {
  assert.equal(classifyDocumentExpiry(undefined, '2026-07-01'), 'undated');
  assert.equal(classifyDocumentExpiry('2026-06-30', '2026-07-01'), 'expired');
  assert.equal(classifyDocumentExpiry('2026-07-31', '2026-07-01'), 'expiring');
  assert.equal(classifyDocumentExpiry('2026-08-01', '2026-07-01'), 'current');
});

test('backup coverage never claims Supabase rows or complete workspace restore', () => {
  assert.equal(BACKUP_COVERAGE.localUploadedFiles, true);
  assert.equal(BACKUP_COVERAGE.supabaseDomainRows, false);
  assert.equal(BACKUP_COVERAGE.completeWorkspaceRestore, false);
});
