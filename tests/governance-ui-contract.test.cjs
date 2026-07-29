const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relativePath) {
  return fs.readFileSync(path.join(process.cwd(), relativePath), 'utf8');
}

const hub = source('src/features/governance/GovernanceHub.tsx');
const backup = source('src/features/settings/BackupRestoreSection.tsx');
const rates = source('src/features/settings/ExchangeRateSection.tsx');
const health = source('src/features/governance/dataHealth.ts');

test('governance is one workspace hub and leaves final route assembly untouched', () => {
  assert.match(hub, /WorkspaceShell/);
  assert.match(hub, /documents.*settings.*exchange-rates.*data-health/s);
  assert.doesNotMatch(hub, /createRoute|createFileRoute|<Tabs|TabsList|TabsTrigger/);
});

test('document vault uses contextual surfaces, inspector relations, and persisted-write flushes', () => {
  assert.match(hub, /AdaptiveFormSurface/);
  assert.match(hub, /initialProjectId/);
  assert.match(hub, /initialPartnerId/);
  assert.match(hub, /EntityInspectorDrawer/);
  assert.match(hub, /documentsHydration\.flush\(\)/);
});

test('backup actions are disabled and explicitly exclude Supabase domain rows', () => {
  assert.match(backup, /does not include Supabase domain rows/);
  assert.match(backup, /disabled/);
  assert.match(backup, /backend job/);
  assert.doesNotMatch(backup, /createTerranexArchive|restoreTerranexArchive|clearTerranexArchiveData/);
});

test('data health remains read-only and exchange rates preserve historical transaction values', () => {
  assert.doesNotMatch(health, /\.create\(|\.update\(|\.remove\(|\.set\(/);
  assert.match(hub, /diagnostic-only/);
  assert.match(rates, /historical transactions are not recalculated/);
  assert.match(rates, /RATE_POLICY_CURRENCIES/);
  assert.match(rates, /addEventListener\('storage'/);
  assert.match(rates, /AdaptiveFormSurface/);
});

test('settings use real auth context without inventing roles and confirm sign-out', () => {
  assert.match(hub, /useAuth/);
  assert.match(hub, /No invented UI roles/);
  assert.match(hub, /ConfirmDialog/);
  assert.match(hub, /onConfirm=\{signOut\}/);
});
