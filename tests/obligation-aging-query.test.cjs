const test = require('node:test');
const assert = require('node:assert/strict');

const {
  queryObligationAging,
  queryPartnerStatement,
} = require('./.compiled/features/finance/obligationQueries.js');

function obligation(overrides = {}) {
  return {
    id: 'obl-1',
    project_id: 'project-1',
    partner_id: 'partner-1',
    direction: 'receivable',
    amount: 100,
    currency: 'EGP',
    amount_egp: 100,
    due_date: '2026-06-30',
    status: 'open',
    amount_settled_egp: 0,
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

function settlement(overrides = {}) {
  return {
    id: 'set-1',
    obligation_id: 'obl-1',
    amount: 10,
    currency: 'EGP',
    fx_rate: 1,
    amount_egp: 10,
    settlement_date: '2026-01-03',
    payment_method: 'cash',
    status: 'active',
    origin: 'user',
    created_at: '2026-01-03T00:00:00.000Z',
    updated_at: '2026-01-03T00:00:00.000Z',
    ...overrides,
  };
}

function allocation(overrides = {}) {
  return {
    id: 'alloc-1',
    settlement_id: 'set-1',
    obligation_id: 'obl-1',
    allocated_amount_egp: 10,
    created_at: '2026-01-03T00:00:00.000Z',
    ...overrides,
  };
}

test('aging query puts outstanding balances into deterministic due-date buckets', () => {
  const records = [
    obligation({ id: 'not-due', amount: 10, amount_egp: 10, due_date: '2026-07-01' }),
    obligation({ id: 'due-today', amount: 11, amount_egp: 11, due_date: '2026-06-30' }),
    obligation({ id: 'one-day', amount: 12, amount_egp: 12, due_date: '2026-06-29' }),
    obligation({ id: 'thirty-one', amount: 13, amount_egp: 13, due_date: '2026-05-30' }),
    obligation({ id: 'sixty-one', amount: 14, amount_egp: 14, due_date: '2026-04-30' }),
    obligation({ id: 'ninety-one', amount: 15, amount_egp: 15, due_date: '2026-03-31' }),
    obligation({ id: 'undated', amount: 16, amount_egp: 16, due_date: undefined }),
    obligation({ id: 'partial-payable', direction: 'payable', amount: 100, amount_egp: 100, amount_settled_egp: 40, status: 'partial', due_date: '2026-06-29' }),
    obligation({ id: 'disputed', amount: 50, amount_egp: 50, status: 'disputed', due_date: '2026-03-31' }),
    obligation({ id: 'settled', amount: 20, amount_egp: 20, amount_settled_egp: 20, status: 'settled' }),
    obligation({ id: 'written-off', amount: 20, amount_egp: 20, status: 'written_off' }),
  ];

  const result = queryObligationAging(records, { as_of: '2026-06-30' });

  assert.equal(result.rows.length, 9);
  assert.equal(result.totals.not_due_egp, 21);
  assert.equal(result.totals.overdue_1_30_egp, 72);
  assert.equal(result.totals.overdue_31_60_egp, 13);
  assert.equal(result.totals.overdue_61_90_egp, 14);
  assert.equal(result.totals.overdue_91_plus_egp, 65);
  assert.equal(result.totals.undated_egp, 16);
  assert.equal(result.totals.receivable_egp, 141);
  assert.equal(result.totals.payable_egp, 60);
  assert.equal(result.totals.outstanding_egp, 201);
  assert.equal(result.rows.find((item) => item.obligation_id === 'one-day').days_overdue, 1);
  assert.equal(result.rows.find((item) => item.obligation_id === 'due-today').bucket, 'not_due');
  assert.equal(result.by_partner.length, 1);

  const withoutDisputed = queryObligationAging(records, { as_of: '2026-06-30', include_disputed: false });
  assert.equal(withoutDisputed.rows.some((item) => item.obligation_id === 'disputed'), false);
  assert.throws(() => queryObligationAging(records, { as_of: '2026-02-30' }));
});

test('party statement derives debit and credit effects from active allocation records', () => {
  const receivable = obligation({ id: 'receivable', amount: 100, amount_egp: 100, amount_settled_egp: 40, status: 'partial', created_at: '2026-01-01T00:00:00.000Z' });
  const payable = obligation({ id: 'payable', direction: 'payable', amount: 60, amount_egp: 60, amount_settled_egp: 20, status: 'partial', created_at: '2026-01-02T00:00:00.000Z' });
  const otherPartner = obligation({ id: 'other', partner_id: 'partner-2', amount: 30, amount_egp: 30 });
  const writtenOff = obligation({ id: 'written-off', amount: 25, amount_egp: 25, status: 'written_off' });
  const settlements = [
    settlement({ id: 'set-receivable', obligation_id: receivable.id, amount: 40, amount_egp: 40, settlement_date: '2026-01-03' }),
    settlement({ id: 'set-payable', obligation_id: payable.id, amount: 20, amount_egp: 20, settlement_date: '2026-01-04' }),
    settlement({ id: 'set-reversed', obligation_id: receivable.id, amount: 10, amount_egp: 10, settlement_date: '2026-01-05', status: 'reversed' }),
    settlement({ id: 'set-other', obligation_id: otherPartner.id, amount: 30, amount_egp: 30, settlement_date: '2026-01-06' }),
  ];
  const allocations = [
    allocation({ id: 'alloc-receivable', settlement_id: 'set-receivable', obligation_id: receivable.id, allocated_amount_egp: 40 }),
    allocation({ id: 'alloc-payable', settlement_id: 'set-payable', obligation_id: payable.id, allocated_amount_egp: 20 }),
    allocation({ id: 'alloc-reversed', settlement_id: 'set-reversed', obligation_id: receivable.id, allocated_amount_egp: 10 }),
    allocation({ id: 'alloc-other', settlement_id: 'set-other', obligation_id: otherPartner.id, allocated_amount_egp: 30 }),
    allocation({ id: 'alloc-missing', settlement_id: 'missing-settlement', obligation_id: receivable.id, allocated_amount_egp: 10 }),
  ];

  const result = queryPartnerStatement(
    [receivable, payable, otherPartner, writtenOff],
    settlements,
    allocations,
    { partner_id: 'partner-1' },
  );

  assert.equal(result.entries.length, 4);
  assert.deepEqual(result.entries.map((entry) => entry.id), [
    'obligation:receivable',
    'obligation:payable',
    'settlement-allocation:alloc-receivable',
    'settlement-allocation:alloc-payable',
  ]);
  assert.equal(result.debit_total_egp, 120);
  assert.equal(result.credit_total_egp, 100);
  assert.equal(result.closing_balance_egp, 20);
  assert.equal(result.closing_direction, 'receivable');
  assert.equal(result.entries.at(-1).running_balance_egp, 20);

  const auditResult = queryPartnerStatement(
    [receivable, payable, otherPartner, writtenOff],
    settlements,
    allocations,
    { partner_id: 'partner-1', include_reversed: true },
  );
  const reversedRow = auditResult.entries.find((entry) => entry.id === 'settlement-allocation:alloc-reversed');
  assert.equal(auditResult.entries.length, 5);
  assert.equal(reversedRow.is_effective, false);
  assert.equal(reversedRow.debit_egp, 0);
  assert.equal(reversedRow.credit_egp, 0);
  assert.equal(auditResult.closing_balance_egp, 20);
});
