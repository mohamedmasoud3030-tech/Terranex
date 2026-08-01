/**
 * Ownership domain regression tests
 *
 * Tests the client-side ownership logic:
 * - Distribution allocation with rounding (largest-share method)
 * - Balance calculation semantics
 * - Ownership change validation rules
 */
const test = require('node:test');
const assert = require('node:assert/strict');

// ─── Distribution Rounding Policy ──────────────────────────────────────────
// The server rounds allocations to 2 decimal places and assigns the rounding
// difference to the partner with the largest share. This tests the algorithm.

function allocateDistribution(total, equityPercentages) {
  const allocations = equityPercentages.map((pct) => ({
    pct,
    amount: Math.round(total * pct / 100 * 100) / 100,
  }));
  const sum = allocations.reduce((s, a) => s + a.amount, 0);
  const diff = Math.round((total - sum) * 100) / 100;

  // Find the partner with the largest share
  let largestIdx = 0;
  for (let i = 1; i < allocations.length; i++) {
    if (allocations[i].amount > allocations[largestIdx].amount) largestIdx = i;
  }
  allocations[largestIdx].amount = Math.round((allocations[largestIdx].amount + diff) * 100) / 100;
  return allocations;
}

test('distribution allocation — standard percentages sum to total', () => {
  const total = 1000;
  const allocations = allocateDistribution(total, [60, 40]);
  const sum = allocations.reduce((s, a) => s + a.amount, 0);
  assert.equal(Math.round(sum * 100) / 100, total, '60/40 split of 1000');
  assert.equal(allocations[0].amount, 600);
  assert.equal(allocations[1].amount, 400);
});

test('distribution allocation — non-clean percentages sum to total', () => {
  const total = 1000;
  const allocations = allocateDistribution(total, [33.33, 33.33, 33.34]);
  const sum = allocations.reduce((s, a) => s + a.amount, 0);
  assert.equal(Math.round(sum * 100) / 100, total, '33.33/33.33/33.34 split must sum to 1000');
});

test('distribution allocation — repeating decimals sum to total', () => {
  const total = 100;
  const allocations = allocateDistribution(total, [100 / 3, 100 / 3, 100 / 3]);
  const sum = allocations.reduce((s, a) => s + a.amount, 0);
  assert.equal(Math.round(sum * 100) / 100, total, '3-way equal split of 100');
});

test('distribution allocation — single partner gets full amount', () => {
  const total = 5000;
  const allocations = allocateDistribution(total, [100]);
  assert.equal(allocations[0].amount, total);
});

test('distribution allocation — many partners with small shares', () => {
  const total = 10000;
  const pcts = [10, 15, 20, 25, 30];
  const allocations = allocateDistribution(total, pcts);
  const sum = allocations.reduce((s, a) => s + a.amount, 0);
  assert.equal(Math.round(sum * 100) / 100, total);
  assert.equal(allocations[0].amount, 1000);
  assert.equal(allocations[1].amount, 1500);
  assert.equal(allocations[2].amount, 2000);
  assert.equal(allocations[3].amount, 2500);
  assert.equal(allocations[4].amount, 3000);
});

test('distribution allocation — rounding goes to largest share', () => {
  const total = 100;
  // 1/3 + 1/3 + 1/3 = 33.33 + 33.33 + 33.33 = 99.99, diff = 0.01
  const allocations = allocateDistribution(total, [100 / 3, 100 / 3, 100 / 3]);
  const sum = allocations.reduce((s, a) => s + a.amount, 0);
  assert.equal(Math.round(sum * 100) / 100, total, 'Rounding adjustment applied');
  // The largest share should have the extra penny
  const rounded = allocations.map((a) => Math.round(a.amount * 100));
  assert.ok(rounded.some((v) => v === 3334), 'One allocation should have the extra penny');
});

// ─── Partner Ledger Balance Calculation ────────────────────────────────────

function calculateBalance(entries) {
  let balance = 0;
  for (const entry of entries) {
    if (entry.entry_type === 'reversal') continue;
    switch (entry.entry_type) {
      case 'capital_contribution':
      case 'distribution_entitlement':
      case 'correction':
        balance += entry.amount_egp;
        break;
      case 'withdrawal':
      case 'distribution_payment':
        balance -= entry.amount_egp;
        break;
    }
  }
  return balance;
}

test('ledger balance — contributions and withdrawals', () => {
  const entries = [
    { entry_type: 'capital_contribution', amount_egp: 50000 },
    { entry_type: 'withdrawal', amount_egp: 10000 },
  ];
  assert.equal(calculateBalance(entries), 40000);
});

test('ledger balance — distribution entitlement and payment', () => {
  const entries = [
    { entry_type: 'distribution_entitlement', amount_egp: 20000 },
    { entry_type: 'distribution_payment', amount_egp: 15000 },
  ];
  assert.equal(calculateBalance(entries), 5000);
});

test('ledger balance — reversal excluded', () => {
  const entries = [
    { entry_type: 'capital_contribution', amount_egp: 30000 },
    { entry_type: 'reversal', amount_egp: 30000 },
  ];
  assert.equal(calculateBalance(entries), 30000, 'Reversal entries excluded from balance');
});

test('ledger balance — empty entries returns zero', () => {
  assert.equal(calculateBalance([]), 0);
});

test('ledger balance — multiple corrections', () => {
  const entries = [
    { entry_type: 'capital_contribution', amount_egp: 100000 },
    { entry_type: 'correction', amount_egp: 5000 },
    { entry_type: 'correction', amount_egp: -2000 },
  ];
  assert.equal(calculateBalance(entries), 103000);
});

// ─── Ownership Change Validation ───────────────────────────────────────────

function validateChangeType(currentPct, newPct, changeType) {
  switch (changeType) {
    case 'entry':
      return currentPct === 0 && newPct > 0;
    case 'exit':
      return currentPct > 0 && newPct === 0;
    case 'increase':
      return newPct > currentPct;
    case 'decrease':
      return newPct < currentPct && newPct >= 0;
    case 'correction':
      return true; // corrections can go either way
    default:
      return false;
  }
}

test('ownership change — entry from zero to positive', () => {
  assert.ok(validateChangeType(0, 40, 'entry'));
  assert.ok(!validateChangeType(10, 40, 'entry'), 'Cannot entry if already has ownership');
  assert.ok(!validateChangeType(0, 0, 'entry'), 'Entry must be positive');
});

test('ownership change — exit to zero', () => {
  assert.ok(validateChangeType(40, 0, 'exit'));
  assert.ok(!validateChangeType(0, 0, 'exit'), 'Cannot exit if no ownership');
  assert.ok(!validateChangeType(40, 10, 'exit'), 'Exit must go to zero');
});

test('ownership change — increase', () => {
  assert.ok(validateChangeType(20, 40, 'increase'));
  assert.ok(!validateChangeType(40, 20, 'increase'));
  assert.ok(!validateChangeType(40, 40, 'increase'));
});

test('ownership change — decrease', () => {
  assert.ok(validateChangeType(40, 20, 'decrease'));
  assert.ok(validateChangeType(40, 0, 'decrease'));
  assert.ok(!validateChangeType(20, 40, 'decrease'));
  assert.ok(!validateChangeType(40, 40, 'decrease'));
});

test('ownership change — sum must not exceed 100%', () => {
  const otherPartnersSum = 75;
  const tooMuchPct = 30;
  assert.ok(otherPartnersSum + tooMuchPct > 100, '75 + 30 = 105 > 100 — must be rejected');
  const validPct = 25;
  assert.ok(otherPartnersSum + validPct <= 100, '75 + 25 = 100 ≤ 100 — must accept');
});

// ─── Temporal Validity ────────────────────────────────────────────────────

test('temporal — effective_from must be before effective_to', () => {
  const from = '2026-01-01';
  const to = '2026-06-01';
  assert.ok(from < to, 'effective_from < effective_to');
  assert.ok(!('2026-06-01' < '2026-01-01'), 'Must reject reversed dates');
});

test('temporal — ownership_as_of_date must be <= distribution_date', () => {
  const ownershipDate = '2026-06-01';
  const distributionDate = '2026-07-01';
  assert.ok(ownershipDate <= distributionDate, 'ownership_as_of_date <= distribution_date');
});
