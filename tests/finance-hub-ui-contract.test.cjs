const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('finance hub uses workspaces, contextual surfaces, inspectors, and guarded reversal', () => {
  const hub = read('src/features/finance/FinanceHub.tsx');
  assert.match(hub, /WorkspaceShell/);
  assert.match(hub, /AdaptiveFormSurface/);
  assert.match(hub, /EntityInspectorDrawer/);
  assert.match(hub, /ConfirmDialog/);
  assert.match(hub, /executeFinanceWrite/);
  assert.doesNotMatch(hub, /router\.navigate|role=["']tab|Tabs/);
});

test('settlement form keeps cash movement and allocations in one mobile-safe flow', () => {
  const form = read('src/features/finance/SettlementFlowForm.tsx');
  const workspaces = read('src/features/finance/FinanceWorkspaces.tsx');
  assert.match(form, /buildSettlementAllocationFormPlans/);
  assert.match(form, /getCompatibleSettleableObligations/);
  assert.match(form, /FINANCE_ATOMICITY_NOTICE/);
  assert.match(form, /min-h-11/);
  assert.match(workspaces, /sm:flex-row/);
  assert.match(workspaces, /settlement is cash movement|التسوية حركة نقدية/);
});

test('transaction form preserves asset and operational-event prefill', () => {
  const form = read('src/features/transactions/TransactionForm.tsx');
  assert.match(form, /asset_id: initial\?\.asset_id/);
  assert.match(form, /operational_event_id: initial\?\.operational_event_id/);
  assert.match(form, /hideActions/);
  assert.match(form, /formId/);
});
