const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('project finance embeds the actionable distribution lifecycle instead of a status-only table', () => {
  const project = read('src/features/portfolio/ProjectWorkspaceView.tsx');

  assert.match(project, /DistributionLifecyclePanel/);
  assert.match(project, /distributions=\{projectDistributions\}/);
  assert.match(project, /allocations=\{distributionAllocations\}/);
  assert.doesNotMatch(project, /getDistributionPaidAmount/);
  assert.doesNotMatch(project, /<table[\s\S]*Project distributions/);
});

test('distribution lifecycle requires explicit approval before due allocation payment', () => {
  const source = read('src/features/ownership/DistributionLifecyclePanel.tsx');

  assert.match(source, /distribution\.status === 'draft'/);
  assert.match(source, /await import\('\.\/service'\)/);
  assert.match(source, /approveProfitDistribution/);
  assert.match(source, /approveDistributionOnServer\(approvalTarget\.id\)/);
  assert.match(source, /ConfirmDialog/);
  assert.match(source, /distribution\.status === 'approved' && allocation\.status === 'due'/);
  assert.match(source, /payAllocationOnServer\(\{/);
  assert.match(source, /allocation_id: paymentTarget\.allocation\.id/);
  assert.match(source, /AdaptiveFormSurface/);
});

test('distribution payment only offers active accounts matching the distribution currency', () => {
  const source = read('src/features/ownership/DistributionLifecyclePanel.tsx');

  assert.match(source, /await import\('\.\.\/banking\/storage'\)/);
  assert.match(source, /listBankAccounts\(\)/);
  assert.match(source, /!account\.is_archived && account\.currency === currency/);
  assert.match(source, /loadEligibleBankAccounts\(paymentTarget\.distribution\.currency\)/);
  assert.match(source, /bank_account_id: bankAccountId/);
  assert.match(source, /payment_date: paymentDate/);
  assert.match(source, /No active.*account is available/);
});

test('distribution lifecycle exposes pending, validation and server failure states', () => {
  const source = read('src/features/ownership/DistributionLifecyclePanel.tsx');

  assert.match(source, /'message_ar' in error/);
  assert.match(source, /setApprovalTarget\(null\);[\s\S]*setError\(readableError\(approvalError\)\)/);
  assert.match(source, /FormErrorSummary/);
  assert.match(source, /role="alert"/);
  assert.match(source, /disabled=\{pending \|\| loadingAccounts\}/);
  assert.match(source, /جار تنفيذ العملية ذريًا/);
});

test('project workspace remains import-safe until the user starts a server operation', () => {
  const source = read('src/features/ownership/DistributionLifecyclePanel.tsx');

  assert.doesNotMatch(source, /^import .*from '\.\/service';/m);
  assert.doesNotMatch(source, /^import .*from '\.\.\/banking\/storage';/m);
  assert.match(source, /async function approveDistributionOnServer/);
  assert.match(source, /async function payAllocationOnServer/);
  assert.match(source, /async function loadEligibleBankAccounts/);
});
