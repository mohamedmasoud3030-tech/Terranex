const test = require('node:test');
const assert = require('node:assert/strict');

const {
  computeInternalAccountBalances,
  projectInternalPostings,
  validateInternalPosting,
} = require('./.compiled/features/finance/internalPostingProjection.js');

function obligation(overrides = {}) {
  return {
    id: 'obl-1',
    project_id: 'project-1',
    partner_id: 'partner-1',
    direction: 'receivable',
    amount: 100,
    currency: 'EGP',
    amount_egp: 100,
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
    amount: 30,
    currency: 'EGP',
    fx_rate: 1,
    amount_egp: 30,
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
    allocated_amount_egp: 30,
    created_at: '2026-01-03T00:00:00.000Z',
    ...overrides,
  };
}

function balancesByAccount(postings) {
  return new Map(computeInternalAccountBalances(postings).map((item) => [item.account, item]));
}

function requireBalance(balances, account) {
  const balance = balances.get(account);
  if (!balance) throw new Error(`Missing balance for ${account}.`);
  return balance;
}

function requirePosting(postings, sourceType) {
  const posting = postings.find((item) => item.source_type === sourceType);
  if (!posting) throw new Error(`Missing ${sourceType} posting.`);
  return posting;
}

test('projection produces balanced postings for receivable, payable, and active allocations', () => {
  const receivable = obligation({ id: 'receivable', amount: 100, amount_egp: 100, amount_settled_egp: 30 });
  const payable = obligation({
    id: 'payable',
    direction: 'payable',
    amount: 70,
    amount_egp: 70,
    amount_settled_egp: 10,
    created_at: '2026-01-02T00:00:00.000Z',
  });
  const writtenOff = obligation({ id: 'written-off', amount: 20, amount_egp: 20, status: 'written_off' });
  const receivableSettlement = settlement({ id: 'set-receivable', obligation_id: receivable.id, amount: 30, amount_egp: 30 });
  const payableSettlement = settlement({ id: 'set-payable', obligation_id: payable.id, amount: 10, amount_egp: 10, settlement_date: '2026-01-04' });

  const projection = projectInternalPostings(
    [receivable, payable, writtenOff],
    [receivableSettlement, payableSettlement],
    [
      allocation({ id: 'alloc-receivable', settlement_id: receivableSettlement.id, obligation_id: receivable.id, allocated_amount_egp: 30 }),
      allocation({ id: 'alloc-payable', settlement_id: payableSettlement.id, obligation_id: payable.id, allocated_amount_egp: 10 }),
    ],
  );

  assert.equal(projection.postings.length, 4);
  assert.equal(projection.postings.some((item) => item.obligation_id === writtenOff.id), false);
  assert.deepEqual(projection.skipped_allocation_ids, []);
  for (const posting of projection.postings) validateInternalPosting(posting);

  const balances = new Map(projection.account_balances.map((item) => [item.account, item]));
  assert.equal(requireBalance(balances, 'trade_receivables').balance_egp, 70);
  assert.equal(requireBalance(balances, 'trade_payables').balance_egp, -60);
  assert.equal(requireBalance(balances, 'settlement_clearing').balance_egp, 20);
  assert.equal(requireBalance(balances, 'obligation_offset').balance_egp, -30);
  assert.equal([...balances.values()].reduce((sum, item) => sum + item.balance_egp, 0), 0);
});

test('reversed settlements are absent by default and audit-visible as balanced reversal pairs when requested', () => {
  const receivable = obligation({ id: 'receivable', amount_settled_egp: 0 });
  const reversedSettlement = settlement({
    id: 'set-reversed',
    obligation_id: receivable.id,
    amount: 25,
    amount_egp: 25,
    status: 'reversed',
    reversed_at: '2026-01-05T12:00:00.000Z',
    updated_at: '2026-01-05T12:00:00.000Z',
  });
  const reversedAllocation = allocation({
    id: 'alloc-reversed',
    settlement_id: reversedSettlement.id,
    obligation_id: receivable.id,
    allocated_amount_egp: 25,
  });

  const current = projectInternalPostings([receivable], [reversedSettlement], [reversedAllocation]);
  assert.equal(current.postings.length, 1);
  assert.equal(requireBalance(balancesByAccount(current.postings), 'trade_receivables').balance_egp, 100);

  const audit = projectInternalPostings(
    [receivable],
    [reversedSettlement],
    [reversedAllocation],
    { include_reversed: true },
  );
  assert.equal(audit.postings.length, 3);
  const original = requirePosting(audit.postings, 'settlement_allocation');
  const reversal = requirePosting(audit.postings, 'settlement_reversal');
  assert.equal(reversal.reversal_of_posting_id, original.id);
  assert.deepEqual(reversal.lines, original.lines.map((line) => ({
    account: line.account,
    debit_egp: line.credit_egp,
    credit_egp: line.debit_egp,
  })));
  const auditBalances = balancesByAccount(audit.postings);
  assert.equal(requireBalance(auditBalances, 'trade_receivables').balance_egp, 100);
  assert.equal(requireBalance(auditBalances, 'settlement_clearing').balance_egp, 0);
});

test('projection reports invalid allocation references without inventing links and rejects unbalanced postings', () => {
  const valid = obligation({ id: 'valid' });
  const writtenOff = obligation({ id: 'written-off', status: 'written_off' });
  const activeSettlement = settlement({ id: 'set-valid', obligation_id: valid.id });
  const projection = projectInternalPostings(
    [valid, writtenOff],
    [activeSettlement],
    [
      allocation({ id: 'missing-settlement', settlement_id: 'missing', obligation_id: valid.id }),
      allocation({ id: 'missing-obligation', settlement_id: activeSettlement.id, obligation_id: 'missing' }),
      allocation({ id: 'written-off-allocation', settlement_id: activeSettlement.id, obligation_id: writtenOff.id }),
    ],
  );

  assert.deepEqual(projection.skipped_allocation_ids, [
    'missing-obligation',
    'missing-settlement',
    'written-off-allocation',
  ]);
  assert.equal(projection.postings.length, 1);
  assert.throws(() => validateInternalPosting({
    id: 'invalid',
    source_type: 'obligation',
    source_id: 'source',
    posting_date: '2026-01-01',
    partner_id: 'partner-1',
    obligation_id: 'obl-1',
    lines: [
      { account: 'trade_receivables', debit_egp: 10, credit_egp: 0 },
      { account: 'obligation_offset', debit_egp: 0, credit_egp: 9 },
    ],
  }));
});
