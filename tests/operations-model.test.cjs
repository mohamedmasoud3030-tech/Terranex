const test = require('node:test');
const assert = require('node:assert/strict');
const { resetWorkspace, awaitHydration, failOperation, clearFailure } = require('./helpers/setup.cjs');

const {
  EVENT_DEFINITIONS,
  computeOperationsOverview,
  eventTypesForSector,
  filterOperationalEvents,
  normalizeQuantityDelta,
  resolveOperationsContext,
  validateStockAdjustment,
} = require('./.compiled/features/operations/model.js');
const { operationsContextSearch } = require('./.compiled/features/operations/contracts.js');
const {
  operationalEventsHydration,
  operationalEventsStore,
} = require('./.compiled/features/events/storage.js');
const { computeAssetLiveQuantity } = require('./.compiled/features/events/hooks.js');

const projects = [
  { id: 'p-ag', sector_id: 'agriculture', name_ar: 'مزرعة', name_en: 'Farm' },
  { id: 'p-lv', sector_id: 'livestock', name_ar: 'قطيع', name_en: 'Herd' },
  { id: 'p-re', sector_id: 'real-estate', name_ar: 'عقار', name_en: 'Estate' },
];
const assets = [
  { id: 'a-ag', project_id: 'p-ag', sector_id: 'agriculture', name_ar: 'محصول', name_en: 'Crop', quantity: 10 },
  { id: 'a-lv', project_id: 'p-lv', sector_id: 'livestock', name_ar: 'مجموعة', name_en: 'Group', quantity: 5 },
  { id: 'a-re', project_id: 'p-re', sector_id: 'real-estate', name_ar: 'مبنى', name_en: 'Building' },
];
const events = [
  { id: 'e-ag', project_id: 'p-ag', asset_id: 'a-ag', type: 'harvest', event_date: '2026-07-10', quantity_delta: 4 },
  { id: 'e-lv', project_id: 'p-lv', asset_id: 'a-lv', type: 'death', event_date: '2026-07-11', quantity_delta: -1 },
];

test('event field matrix exposes only domain-backed sector event types', () => {
  assert.equal(eventTypesForSector('real-estate').length, 0);
  assert.ok(eventTypesForSector('agriculture').includes('harvest'));
  assert.ok(!eventTypesForSector('agriculture').includes('birth'));
  assert.ok(eventTypesForSector('livestock').includes('birth'));
  assert.ok(!eventTypesForSector('livestock').includes('irrigation'));
  assert.equal(EVENT_DEFINITIONS.weighing.weight, true);
  assert.equal(EVENT_DEFINITIONS.vaccination.cost, true);
});

test('quantity deltas follow the event matrix and reject wrong sign explicitly', () => {
  // Correct sign for positive-only event returns abs
  assert.equal(normalizeQuantityDelta('birth', 7), 7);
  // Correct sign for negative-only event returns -abs
  assert.equal(normalizeQuantityDelta('death', -3), -3);
  // Non-quantity events return undefined regardless of value
  assert.equal(normalizeQuantityDelta('weighing', 9), undefined);
  assert.equal(normalizeQuantityDelta('transfer', 0), undefined);
  // Wrong sign throws QuantitySignError instead of silently correcting
  assert.throws(() => normalizeQuantityDelta('birth', -7), /كمية موجبة/);
  assert.throws(() => normalizeQuantityDelta('death', 3), /كمية سالبة/);
});

test('balance regression applies the latest adjustment then only later events', () => {
  const balance = computeAssetLiveQuantity(
    10,
    [
      { ...events[0], id: 'before', event_date: '2026-07-01', quantity_delta: 5 },
      { ...events[0], id: 'after', event_date: '2026-07-20', quantity_delta: -2 },
    ],
    [{
      id: 'adj',
      project_id: 'p-ag',
      asset_id: 'a-ag',
      adjustment_date: '2026-07-15',
      quantity_before: 15,
      quantity_after: 12,
      value_egp_before: 100,
      value_egp_after: 90,
      reason: 'reconciliation',
      created_at: '2026-07-15',
    }],
  );
  assert.equal(balance.quantity, 10);
  assert.equal(balance.eventCount, 3);
});

test('stock adjustment validation guards live before balance and non-negative after values', () => {
  assert.deepEqual(validateStockAdjustment(12, {
    quantity_before: 12,
    quantity_after: 11,
    value_egp_before: 100,
    value_egp_after: 90,
    adjustment_date: '2026-07-29',
  }), []);
  assert.deepEqual(validateStockAdjustment(12, {
    quantity_before: 10,
    quantity_after: -1,
    value_egp_before: 100,
    value_egp_after: -5,
    adjustment_date: '',
  }), [
    'quantity_before_must_match_live_balance',
    'quantity_after_must_be_non_negative',
    'value_after_must_be_non_negative',
    'adjustment_date_required',
  ]);
});

test('context and filters reject mismatched entity relations and remain shareable', () => {
  assert.deepEqual(resolveOperationsContext(
    { sector: 'livestock', projectId: 'p-lv', assetId: 'a-ag' },
    projects,
    assets,
  ), { sector: 'agriculture', projectId: 'p-ag', assetId: 'a-ag' });
  assert.deepEqual(filterOperationalEvents(events, assets, {
    sector: 'agriculture',
    projectId: 'p-ag',
    dateFrom: '2026-07-01',
    dateTo: '2026-07-10',
  }).map((event) => event.id), ['e-ag']);
  assert.equal(
    operationsContextSearch({
      destination: 'operations',
      intent: 'open-context',
      sector: 'agriculture',
      projectId: 'p-ag',
      assetId: 'a-ag',
    }),
    'sector=agriculture&project=p-ag&asset=a-ag',
  );
});

test('operations overview is derived from current sources only', () => {
  const overview = computeOperationsOverview(
    projects,
    assets,
    events,
    [],
    [{ id: 'doc', project_id: 'p-ag' }],
    [{ id: 'tx', project_id: 'p-ag', operational_event_id: 'e-ag' }],
    'agriculture',
  );
  assert.equal(overview.projectCount, 1);
  assert.equal(overview.assetCount, 1);
  assert.equal(overview.eventCount, 1);
  assert.equal(overview.documentCount, 1);
  assert.equal(overview.linkedTransactionCount, 1);
});

test('failed operational event write is rejected by flush and rolled back', async () => {
  await resetWorkspace();
  await awaitHydration(operationalEventsHydration);
  failOperation('insert', 'operational_events', 'row-level security rejected event');
  operationalEventsStore.create({
    project_id: 'p-ag',
    asset_id: 'a-ag',
    type: 'harvest',
    event_date: '2026-07-29',
  });
  await assert.rejects(() => operationalEventsStore.flush(), /row-level security rejected event/);
  assert.equal(operationalEventsStore.getAll().length, 0);
  clearFailure('insert', 'operational_events');
});
