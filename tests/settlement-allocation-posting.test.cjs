const test = require('node:test');
const assert = require('node:assert/strict');
const { resetWorkspace, awaitHydration, failOperation } = require('./helpers/setup.cjs');

const { obligationsStore, obligationsHydration } = require('./.compiled/features/obligations/storage.js');
const { settlementAllocationsStore, settlementAllocationsHydration } = require('./.compiled/features/settlement-allocations/storage.js');
const { settlementsStore, settlementsHydration } = require('./.compiled/features/settlements/storage.js');
const {
  recordSettlementWithAllocations,
  reverseSettlement,
} = require('./.compiled/features/settlements/workflow.js');

async function reset() {
  await resetWorkspace();
  await awaitHydration(obligationsHydration, settlementsHydration, settlementAllocationsHydration);
}

function obligation(overrides = {}) {
  return obligationsStore.create({
    project_id: 'project-1',
    partner_id: 'partner-1',
    direction: 'payable',
    amount: 100,
    currency: 'EGP',
    amount_egp: 100,
    status: 'open',
    ...overrides,
  });
}

test('one settlement allocates across obligations and reversal removes all active effects', async () => {
  await reset();
  const first = obligation();
  const second = obligation({ amount: 80, amount_egp: 80 });

  const settlement = recordSettlementWithAllocations({
    amount: 150,
    currency: 'EGP',
    fx_rate: 1,
    settlement_date: '2026-06-01',
    payment_method: 'bank_transfer',
    allocations: [
      { obligation_id: first.id, allocated_amount_egp: 100 },
      { obligation_id: second.id, allocated_amount_egp: 50 },
    ],
  });

  assert.equal(settlementAllocationsStore.getBySettlement(settlement.id).length, 2);
  assert.equal(settlementsStore.getByObligation(first.id).length, 1);
  assert.equal(settlementsStore.getByObligation(second.id).length, 1);
  assert.equal(obligationsStore.getById(first.id).amount_settled_egp, 100);
  assert.equal(obligationsStore.getById(first.id).status, 'settled');
  assert.equal(obligationsStore.getById(second.id).amount_settled_egp, 50);
  assert.equal(obligationsStore.getById(second.id).status, 'partial');

  reverseSettlement(settlement.id, 'إلغاء سند خاطئ');

  assert.equal(settlementAllocationsStore.getBySettlement(settlement.id).length, 2);
  assert.equal(settlementAllocationsStore.getActiveTotalByObligation(first.id, settlementsStore.getAll()), 0);
  assert.equal(settlementAllocationsStore.getActiveTotalByObligation(second.id, settlementsStore.getAll()), 0);
  assert.equal(obligationsStore.getById(first.id).status, 'open');
  assert.equal(obligationsStore.getById(second.id).amount_settled_egp, 0);
});

test('allocation plan must fully allocate payment and preserve common project and party context', async () => {
  await reset();
  const first = obligation();
  const second = obligation({ amount: 50, amount_egp: 50 });
  const otherProject = obligation({ project_id: 'project-2' });
  const otherPartner = obligation({ partner_id: 'partner-2' });

  const base = {
    amount: 100,
    currency: 'EGP',
    fx_rate: 1,
    settlement_date: '2026-06-01',
    payment_method: 'cash',
  };

  assert.throws(() => recordSettlementWithAllocations({
    ...base,
    allocations: [{ obligation_id: first.id, allocated_amount_egp: 90 }],
  }));
  assert.throws(() => recordSettlementWithAllocations({
    ...base,
    allocations: [
      { obligation_id: first.id, allocated_amount_egp: 50 },
      { obligation_id: otherProject.id, allocated_amount_egp: 50 },
    ],
  }));
  assert.throws(() => recordSettlementWithAllocations({
    ...base,
    allocations: [
      { obligation_id: second.id, allocated_amount_egp: 50 },
      { obligation_id: otherPartner.id, allocated_amount_egp: 50 },
    ],
  }));
  assert.equal(settlementsStore.getAll().length, 0);
});

test('allocation cannot exceed the remaining balance of a target obligation', async () => {
  await reset();
  const first = obligation();
  const second = obligation({ amount: 50, amount_egp: 50 });

  assert.throws(() => recordSettlementWithAllocations({
    amount: 160,
    currency: 'EGP',
    fx_rate: 1,
    settlement_date: '2026-06-01',
    payment_method: 'cash',
    allocations: [
      { obligation_id: first.id, allocated_amount_egp: 110 },
      { obligation_id: second.id, allocated_amount_egp: 50 },
    ],
  }));
  assert.equal(settlementAllocationsStore.getAll().length, 0);
});

test('a rejected allocation write does not leave the obligation looking settled', async () => {
  await reset();
  const target = obligation();
  await obligationsHydration.flush();

  failOperation('insert', 'settlement_allocations', 'new row violates row-level security policy');
  recordSettlementWithAllocations({
    amount: 100,
    currency: 'EGP',
    fx_rate: 1,
    settlement_date: '2026-06-01',
    payment_method: 'cash',
    allocations: [{ obligation_id: target.id, allocated_amount_egp: 100 }],
  });

  await assert.rejects(() => settlementAllocationsHydration.flush(), /row-level security/);
  assert.equal(settlementAllocationsStore.getAll().length, 0, 'التوزيع المرفوض يجب ألا يبقى في الذاكرة.');
});

test('allocation state does not bleed between tests', async () => {
  await reset();
  assert.equal(settlementAllocationsStore.getAll().length, 0);
  assert.equal(settlementsStore.getAll().length, 0);
  assert.equal(obligationsStore.getAll().length, 0);
});
