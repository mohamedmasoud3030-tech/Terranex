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
  assert.match(source, /approveProfitDistribution\(\{ distribution_id: approvalTarget\.id \}\)/);
  assert.match(source, /ConfirmDialog/);
  assert.match(source, /distribution\.status === 'approved' && allocation\.status === 'due'/);
  assert.match(source, /payDistributionAllocation\(\{/);
  assert.match(source, /allocation_id: paymentTarget\.allocation\.id/);
  assert.match(source, /AdaptiveFormSurface/);
});

test('distribution payment only offers active accounts matching the distribution currency', () => {
  const source = read('src/features/ownership/DistributionLifecyclePanel.tsx');

  assert.match(source, /listBankAccounts\(\)/);
  assert.match(source, /!account\.is_archived && account\.currency === paymentTarget\.distribution\.currency/);
  assert.match(source, /bank_account_id: bankAccountId/);
  assert.match(source, /payment_date: paymentDate/);
  assert.match(source, /No active.*account is available/);
});

test('distribution lifecycle exposes pending, validation and server failure states', () => {
  const source = read('src/features/ownership/DistributionLifecyclePanel.tsx');

  assert.match(source, /OwnershipServiceError/);
  assert.match(source, /FormErrorSummary/);
  assert.match(source, /role="alert"/);
  assert.match(source, /disabled=\{pending \|\| loadingAccounts\}/);
  assert.match(source, /جار تنفيذ العملية ذريًا/);
});
