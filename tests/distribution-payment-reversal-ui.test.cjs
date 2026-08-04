const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('paid distribution allocations expose the reversal action in the project lifecycle', () => {
  const panel = read('src/features/ownership/DistributionLifecyclePanel.tsx');

  assert.match(panel, /DistributionPaymentReversalAction/);
  assert.match(panel, /allocation\.status === 'paid'/);
  assert.match(panel, /distribution=\{distribution\}/);
  assert.match(panel, /allocation=\{allocation\}/);
  assert.match(panel, /partner=\{partner\}/);
});

test('reversal is fail-closed without the original ledger reference', () => {
  const source = read('src/features/ownership/DistributionPaymentReversalAction.tsx');

  assert.match(source, /if \(allocation\.status !== 'paid'\) return null/);
  assert.match(source, /const ledgerEntryId = allocation\.related_ledger_entry_id/);
  assert.match(source, /const canReverse = Boolean\(ledgerEntryId\) && !disabled/);
  assert.match(source, /disabled=\{!canReverse\}/);
  assert.match(source, /مرجع قيد الدفتر غير متاح؛ العكس مقفول/);
});

test('reversal requires a date and a non-empty audit reason', () => {
  const source = read('src/features/ownership/DistributionPaymentReversalAction.tsx');

  assert.match(source, /if \(!postingDate\)/);
  assert.match(source, /const normalizedReason = reason\.trim\(\)/);
  assert.match(source, /if \(!normalizedReason\)/);
  assert.match(source, /سبب العكس إلزامي لحماية مسار التدقيق/);
  assert.match(source, /required[\s\S]*minLength=\{3\}/);
});

test('reversal delegates to the atomic append-only service boundary', () => {
  const source = read('src/features/ownership/DistributionPaymentReversalAction.tsx');

  assert.match(source, /await import\('\.\/service'\)/);
  assert.match(source, /reversePartnerLedgerEntry/);
  assert.match(source, /entry_id: ledgerEntryId/);
  assert.match(source, /posting_date: postingDate/);
  assert.match(source, /reason: normalizedReason/);
  assert.match(source, /قيدًا عكسيًا وحركة نقدية مقابلة/);
  assert.match(source, /لن يُحذف السجل الأصلي/);
});

test('reversal UI remains import-safe and exposes pending and server error states', () => {
  const source = read('src/features/ownership/DistributionPaymentReversalAction.tsx');

  assert.doesNotMatch(source, /^import .*from '\.\/service';/m);
  assert.match(source, /FormErrorSummary/);
  assert.match(source, /pending=\{pending\}/);
  assert.match(source, /disabled=\{pending\}/);
  assert.match(source, /role="status"/);
  assert.match(source, /جار إنشاء القيد والحركة العكسية ذريًا/);
  assert.match(source, /setError\(readableError\(reversalError\)\)/);
});
