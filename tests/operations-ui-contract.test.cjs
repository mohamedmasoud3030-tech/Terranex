const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

test('operations hub uses contextual surfaces and atomic stock correction routing', () => {
  const hub = read('src/features/operations/OperationsHub.tsx');
  const context = read('src/features/operations/useOperationsContext.ts');
  const stockWorkflow = read('src/features/events/stockAdjustmentWorkflow.ts');
  assert.match(hub, /AdaptiveFormSurface/);
  assert.match(hub, /EntityInspectorDrawer/);
  assert.match(hub, /ConfirmDialog/);
  assert.match(hub, /operationalEventsStore\.flush/);
  assert.match(hub, /recordStockAdjustmentAtomic/);
  assert.doesNotMatch(hub, /stockAdjustmentsStore\.flush/);
  assert.match(stockWorkflow, /record_stock_adjustment_atomic|P1B_ATOMIC_RPC_NAMES\[5\]/);
  assert.match(stockWorkflow, /invokeFinanceRpc/);
  assert.match(context, /URLSearchParams|searchParams/);
  assert.doesNotMatch(hub, /router\.navigate|navigation\.ts|router\.tsx/);
});

test('events stay mobile-first, sector-composed, and free of sector tabs', () => {
  const workspace = read('src/features/operations/EventsWorkspace.tsx');
  const eventForm = read('src/features/operations/EventForm.tsx');
  const balances = read('src/features/operations/AssetBalancesWorkspace.tsx');
  assert.match(workspace, /min-h-11/);
  assert.match(workspace, /sm:flex-row/);
  assert.match(eventForm, /EVENT_DEFINITIONS/);
  assert.match(eventForm, /eventTypesForSector/);
  assert.match(balances, /sm:grid-cols-2/);
  assert.match(balances, /xl:grid-cols-3/);
  assert.doesNotMatch(workspace, /role=["']tab/);
  assert.doesNotMatch(workspace, /Tabs/);
});

test('operations data surfaces load errors and retries for every hydrated store', () => {
  const source = read('src/features/operations/useOperationsData.ts');
  // Every store whose rows the hub renders must have its load error consulted,
  // otherwise a failed hydration is silently shown as an empty (but "ready") hub.
  const stores = [
    'projectsHydration',
    'assetsHydration',
    'operationalEventsHydration',
    'stockAdjustmentsHydration',
    'documentsHydration',
    'transactionsHydration',
    'obligationsHydration',
    'partnersHydration',
    'projectPartnersHydration',
  ];
  for (const store of stores) {
    assert.match(source, new RegExp(`${store}\\.getLoadError\\(\\)`), `${store} load error must be checked`);
    assert.match(source, new RegExp(`${store}\\.rehydrate\\(\\)`), `${store} must be rehydrated on retry`);
  }
});
