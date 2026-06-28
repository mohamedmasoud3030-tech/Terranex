const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildSettlementAllocationFormPlans,
  getCompatibleSettleableObligations,
  getSettlementAllocationPlanTotal,
} = require('./.compiled/features/settlements/allocationForm.js');

function obligation(overrides = {}) {
  return {
    id: 'obl-1',
    project_id: 'project-1',
    partner_id: 'partner-1',
    direction: 'payable',
    amount: 100,
    currency: 'EGP',
    amount_egp: 100,
    amount_settled_egp: 0,
    status: 'open',
    created_at: '2026-06-01T00:00:00.000Z',
    updated_at: '2026-06-01T00:00:00.000Z',
    ...overrides,
  };
}

test('allocation form exposes only compatible and settleable obligations', () => {
  const anchor = obligation();
  const compatiblePartial = obligation({ id: 'obl-2', amount_settled_egp: 20, status: 'partial' });
  const wrongProject = obligation({ id: 'obl-3', project_id: 'project-2' });
  const wrongParty = obligation({ id: 'obl-4', partner_id: 'partner-2' });
  const wrongDirection = obligation({ id: 'obl-5', direction: 'receivable' });
  const disputed = obligation({ id: 'obl-6', status: 'disputed' });
  const settled = obligation({ id: 'obl-7', amount_settled_egp: 100, status: 'settled' });

  assert.deepEqual(
    getCompatibleSettleableObligations(anchor, [anchor, compatiblePartial, wrongProject, wrongParty, wrongDirection, disputed, settled]).map((item) => item.id),
    ['obl-1', 'obl-2'],
  );
});

test('allocation form validates remaining balances and derives the exact payment total', () => {
  const first = obligation();
  const second = obligation({ id: 'obl-2', amount: 50, amount_egp: 50, amount_settled_egp: 10, status: 'partial' });

  const plans = buildSettlementAllocationFormPlans([first, second], { 'obl-1': '25', 'obl-2': '40' });
  assert.deepEqual(plans, [
    { obligation_id: 'obl-1', allocated_amount_egp: 25 },
    { obligation_id: 'obl-2', allocated_amount_egp: 40 },
  ]);
  assert.equal(getSettlementAllocationPlanTotal(plans), 65);

  assert.throws(() => buildSettlementAllocationFormPlans([first, second], { 'obl-2': '40.01' }));
  assert.throws(() => buildSettlementAllocationFormPlans([first], { 'obl-1': '0' }));
});
