const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const documentPath = path.join(
  root,
  'docs',
  'security',
  'AUTHENTICATED_SECURITY_DEFINER_ALLOWLIST.md',
);
const document = fs.readFileSync(documentPath, 'utf8');

const expected = [
  'approve_distribution_atomic',
  'change_ownership_atomic',
  'create_journal_entry_atomic',
  'create_purchase_invoice_atomic',
  'create_sales_invoice_atomic',
  'delete_transaction_atomic',
  'enqueue_odoo_sync',
  'get_ownership_as_of',
  'pay_distribution_allocation_atomic',
  'pay_purchase_invoice',
  'pay_sales_invoice',
  'post_journal_entry',
  'receive_purchase_invoice_with_stock',
  'record_distribution_atomic',
  'record_partner_capital_movement_atomic',
  'record_partner_ledger_entry_atomic',
  'record_settlement_atomic',
  'record_stock_adjustment_atomic',
  'record_transaction_atomic',
  'reverse_partner_ledger_entry_atomic',
  'reverse_settlement_atomic',
  'set_bank_transaction_reviewed',
  'terranex_assert_owner',
  'update_transaction_atomic',
  'void_journal_entry',
].sort();

function documentedAllowlist() {
  const section = document.match(/## Exact allowlist([\s\S]*?)## Explicitly forbidden from the allowlist/)?.[1];
  assert.ok(section, 'exact allowlist section must exist');
  return [...section.matchAll(/^- `([^`]+)`/gm)]
    .map((match) => match[1])
    .sort();
}

test('security documentation contains the exact reviewed elevated RPC boundary', () => {
  assert.deepEqual(documentedAllowlist(), expected);
  assert.equal(expected.length, 25);
});

test('security documentation preserves the anonymous-deny and trigger-deny invariants', () => {
  assert.match(document, /deny `PUBLIC` and `anon` execution/);
  assert.match(document, /every function returning `trigger`/);
  assert.match(document, /pin `search_path` explicitly/);
});

test('internal locking and audit helpers are explicitly forbidden', () => {
  for (const helper of [
    'terranex_lock_financial_request',
    'terranex_audit_check_idempotent',
    'terranex_audit_log',
  ]) {
    assert.match(document, new RegExp(`- \\`${helper}\\``));
    assert.ok(!expected.includes(helper));
  }
});
