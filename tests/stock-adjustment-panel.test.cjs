const test = require('node:test');
const assert = require('node:assert/strict');
const React = require('react');
const { JSDOM } = require('jsdom');

const dom = new JSDOM('<!doctype html><html><body></body></html>', {
  url: 'https://terranex.test/assets',
});

for (const property of [
  'window',
  'document',
  'navigator',
  'HTMLElement',
  'HTMLInputElement',
  'HTMLButtonElement',
  'HTMLSelectElement',
  'Element',
  'Node',
  'NodeFilter',
  'Event',
  'CustomEvent',
  'KeyboardEvent',
  'MouseEvent',
  'FocusEvent',
  'MutationObserver',
  'getComputedStyle',
]) {
  globalThis[property] = dom.window[property];
}

globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.PointerEvent = dom.window.PointerEvent ?? dom.window.MouseEvent;
globalThis.requestAnimationFrame = (callback) => setTimeout(callback, 0);
globalThis.cancelAnimationFrame = (id) => clearTimeout(id);
globalThis.ResizeObserver = class {
  observe() {}
  unobserve() {}
  disconnect() {}
};

class MemoryStorage {
  constructor() { this.values = new Map(); }
  get length() { return this.values.size; }
  key(index) { return Array.from(this.values.keys())[index] ?? null; }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
  clear() { this.values.clear(); }
}
globalThis.localStorage = new MemoryStorage();

// Inject the fake client into the SOURCE module registry BEFORE any store module
// loads (the panel renders through the source graph, not tests/.compiled).
const {
  FakeSupabaseClient,
  seedFakeTable,
  failRpc,
  resetFakeSupabase,
} = require('./helpers/fakeSupabase.cjs');

const fake = new FakeSupabaseClient();

// حقن العميل الوهمي أولاً قبل أي تحميل لمخزن (المخازن تُنشأ وتُحمّل عند استيراد الوحدة).
const { setSupabaseClient, rehydrateAllStores } = require('../src/core/storage/supabaseStore.ts');
setSupabaseClient(fake);
const { operationalEventsReady, stockAdjustmentsReady } = require('../src/features/events/storage.ts');

const ASSET = {
  id: 'asset-1',
  project_id: 'project-1',
  sector_id: 'livestock',
  type: 'herd',
  name_ar: 'قطيع الأغنام',
  name_en: 'Sheep herd',
  acquisition_date: '2026-01-01',
  acquisition_cost: 1000,
  acquisition_currency: 'EGP',
  acquisition_cost_egp: 1000,
  current_value_egp: 1000,
  status: 'owned',
  quantity: 10,
  unit: 'رأس',
  created_at: '2026-01-01',
};

seedFakeTable('assets', [ASSET]);

const { StockAdjustmentPanel } = require('../src/features/assets/StockAdjustmentPanel.tsx');
const { cleanup, render, screen, waitFor, fireEvent } = require('@testing-library/react');
const userEvent = require('@testing-library/user-event').default;

test.afterEach(async () => {
  cleanup();
  resetFakeSupabase();
  seedFakeTable('assets', [ASSET]);
  await rehydrateAllStores();
});

async function openPanel() {
  await operationalEventsReady;
  await stockAdjustmentsReady;
  render(React.createElement(StockAdjustmentPanel, { asset: ASSET }));
  await userEvent.click(await screen.findByRole('button', { name: /تسوية كمية \/ قيمة/ }));
}

function fillFields(overrides = {}) {
  const values = { qtyBefore: '10', qtyAfter: '8', valBefore: '1000', valAfter: '800', ...overrides };
  const inputs = screen.getAllByPlaceholderText('0');
  fireEvent.change(inputs[0], { target: { value: values.qtyBefore } });
  fireEvent.change(inputs[1], { target: { value: values.qtyAfter } });
  fireEvent.change(inputs[2], { target: { value: values.valBefore } });
  fireEvent.change(inputs[3], { target: { value: values.valAfter } });
}

async function submit() {
  await userEvent.click(screen.getByRole('button', { name: 'تسجيل التسوية' }));
}

test('empty numeric field shows an error and keeps the panel open', async () => {
  await openPanel();
  fillFields({ qtyAfter: '' });
  await submit();

  assert.ok(await screen.findByText('هذا الحقل مطلوب، يرجى إدخال قيمة.'));
  // اللوحة ما زالت مفتوحة
  assert.ok(screen.getByText('تسوية جديدة'));
  assert.equal(screen.queryByRole('button', { name: /تسوية كمية \/ قيمة/ }), null);
});

test('negative value shows an error and keeps the panel open', async () => {
  await openPanel();
  fillFields({ qtyAfter: '-2' });
  await submit();

  assert.ok(await screen.findByText('القيمة لا يمكن أن تكون سالبة.'));
  // اللوحة ما زالت مفتوحة
  assert.ok(screen.getByText('تسوية جديدة'));
});

test('server failure shows a translated Arabic error and keeps the panel open', async () => {
  failRpc('record_stock_adjustment_atomic', 'stock adjustment cannot produce negative quantity or value');
  await openPanel();
  fillFields();
  await submit();

  assert.ok(await screen.findByText('لا يمكن أن ينتج عن التسوية كمية أو قيمة سالبة.'));
  // اللوحة ما زالت مفتوحة — لا تغلق عند الفشل
  assert.ok(screen.getByText('تسوية جديدة'));
});

test('valid adjustment closes the panel only after the server accepts it', async () => {
  await openPanel();
  fillFields();
  await submit();

  await waitFor(() => {
    assert.equal(screen.queryByText('تسوية جديدة'), null);
  });
  assert.ok(await screen.findByRole('button', { name: /تسوية كمية \/ قيمة/ }));
});
