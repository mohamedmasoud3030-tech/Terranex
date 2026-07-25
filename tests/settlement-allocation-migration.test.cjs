const test = require('node:test');
const assert = require('node:assert/strict');
const { resetWorkspace, calls } = require('./helpers/setup.cjs');

const { createTerranexBackup } = require('./.compiled/core/storage/backup.js');
const {
  migrateLegacySettlementBalances,
  resetLegacySettlementMigration,
  SETTLEMENTS_KEY,
} = require('./.compiled/features/settlements/migration.js');
const {
  migrateLegacySettlementAllocations,
  resetLegacySettlementAllocationMigration,
  SETTLEMENT_ALLOCATIONS_KEY,
  SETTLEMENT_ALLOCATIONS_AUDIT_KEY,
} = require('./.compiled/features/settlement-allocations/migration.js');

const OBLIGATIONS_KEY = 'terranex.obligations.v1';

/**
 * IMPORTANT CONTEXT — these migrations are localStorage-only on purpose.
 *
 * Before the Supabase move, `settlementAllocationsStore.getAll()` implicitly
 * ran `migrateLegacySettlementAllocations()` on every read, so the old test
 * asserted the migration through the store. The Supabase-backed store reads
 * Postgres and never touches localStorage, so asserting the migration through
 * the store now measures nothing.
 *
 * These migrations still matter: they drain leftover pre-Supabase browser data
 * so it can be backed up and re-imported. They are tested directly, against
 * localStorage, and are explicitly asserted NOT to write to Supabase — moving
 * that data server-side is Phase 2 work.
 */

const LEGACY_OBLIGATION = {
  id: 'obl-legacy',
  project_id: 'project-1',
  partner_id: 'partner-1',
  direction: 'payable',
  amount: 25,
  currency: 'EGP',
  amount_egp: 25,
  amount_settled_egp: 25,
  status: 'settled',
  created_at: '2026-01-01T00:00:00.000Z',
  updated_at: '2026-01-01T00:00:00.000Z',
};

const LEGACY_SETTLEMENT = {
  id: 'set-legacy',
  obligation_id: 'obl-legacy',
  amount: 25,
  currency: 'EGP',
  fx_rate: 1,
  amount_egp: 25,
  settlement_date: '2026-01-01',
  payment_method: 'unknown',
  status: 'active',
  origin: 'legacy_balance_migration',
  created_at: '2026-01-01T00:00:00.000Z',
  updated_at: '2026-01-01T00:00:00.000Z',
};

function read(key) { return JSON.parse(localStorage.getItem(key) || 'null'); }
function write(key, value) { localStorage.setItem(key, JSON.stringify(value)); }

async function reset() {
  await resetWorkspace();
  resetLegacySettlementMigration();
  resetLegacySettlementAllocationMigration();
}

test('legacy settlement records migrate once to allocation records and enter backups', async () => {
  await reset();
  write(OBLIGATIONS_KEY, [LEGACY_OBLIGATION]);
  write(SETTLEMENTS_KEY, [LEGACY_SETTLEMENT]);

  migrateLegacySettlementAllocations();
  const first = read(SETTLEMENT_ALLOCATIONS_KEY);

  // Second run must be a no-op — the migration is keyed and idempotent.
  migrateLegacySettlementAllocations();
  const second = read(SETTLEMENT_ALLOCATIONS_KEY);

  assert.equal(first.length, 1);
  assert.equal(second.length, 1);
  assert.equal(first[0].settlement_id, 'set-legacy');
  assert.equal(first[0].obligation_id, 'obl-legacy');
  assert.equal(first[0].allocated_amount_egp, 25);
  assert.equal(first[0].created_at, '2026-01-01T00:00:00.000Z');

  const backup = createTerranexBackup();
  assert.ok(backup.records[SETTLEMENT_ALLOCATIONS_KEY]);
});

test('legacy allocation migration preserves orphaned settlements for audit instead of inventing links', async () => {
  await reset();
  write(OBLIGATIONS_KEY, []);
  write(SETTLEMENTS_KEY, [LEGACY_SETTLEMENT]);

  migrateLegacySettlementAllocations();

  assert.equal(read(SETTLEMENT_ALLOCATIONS_KEY), null, 'لا يجوز اختلاق توزيع لالتزام غير موجود.');
  const audit = read(SETTLEMENT_ALLOCATIONS_AUDIT_KEY);
  assert.equal(audit.length, 1);
  assert.equal(audit[0].record.id, 'set-legacy');
});

test('legacy running balances migrate once to explicit settlement records', async () => {
  await reset();
  write(OBLIGATIONS_KEY, [{
    id: 'obl-running', partner_id: 'partner-1', direction: 'payable',
    amount: 100, currency: 'EGP', amount_egp: 100, status: 'partial',
    amount_settled_egp: 35,
    created_at: '2026-01-01T00:00:00.000Z', updated_at: '2026-01-02T00:00:00.000Z',
  }]);
  write(SETTLEMENTS_KEY, []);

  migrateLegacySettlementBalances();
  const migrated = read(SETTLEMENTS_KEY).filter((item) => item.obligation_id === 'obl-running');

  assert.equal(migrated.length, 1);
  assert.equal(migrated[0].amount_egp, 35);
  assert.equal(migrated[0].origin, 'legacy_balance_migration');

  // Re-running must not double-count the balance.
  migrateLegacySettlementBalances();
  assert.equal(read(SETTLEMENTS_KEY).filter((item) => item.obligation_id === 'obl-running').length, 1);
});

test('legacy migrations never write to Supabase in this phase', async () => {
  await reset();
  write(OBLIGATIONS_KEY, [LEGACY_OBLIGATION]);
  write(SETTLEMENTS_KEY, [LEGACY_SETTLEMENT]);
  const before = calls.insert.length + calls.update.length + calls.delete.length;

  migrateLegacySettlementBalances();
  migrateLegacySettlementAllocations();

  const after = calls.insert.length + calls.update.length + calls.delete.length;
  assert.equal(after, before, 'ترحيل البيانات القديمة إلى Supabase من نطاق المرحلة الثانية.');
});
