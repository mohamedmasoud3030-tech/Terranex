const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('purchase invoice client delegates create, receipt and payment to atomic RPCs', () => {
  const source = read('src/features/invoicing/purchaseStorage.ts');
  assert.match(source, /create_purchase_invoice_atomic/);
  assert.match(source, /receive_purchase_invoice_with_stock/);
  assert.match(source, /pay_purchase_invoice/);
  assert.doesNotMatch(source, /linkFinancialMovement|Math\.random|\.from\(LINES\)\.insert/);
  assert.match(source, /crypto\.randomUUID\(\)/);
});

test('manual voucher client never performs a second-phase bank ledger write', () => {
  const source = read('src/features/finance/journalStorage.ts');
  assert.match(source, /create_journal_entry_atomic/);
  assert.match(source, /post_journal_entry/);
  assert.match(source, /void_journal_entry/);
  assert.doesNotMatch(source, /linkFinancialMovement|Math\.random|bank_transactions.*insert/);
});

test('hardening migration rejects overpayment and records each purchase payment atomically', () => {
  const migration = read('supabase/migrations/20260802001700_purchase_voucher_hardening.sql');
  assert.match(migration, /مبلغ الدفعة يتجاوز المستحق/);
  assert.match(migration, /insert into bank_transactions\(/);
  assert.match(migration, /insert into purchase_invoice_payments\(/);
  assert.match(migration, /v_pay_id.*gen_random_uuid/);
  assert.match(migration, /'bill_payment',\s*v_pay_id/);
});

test('posted manual voucher cancellation creates a linked reversal and reverse bank movement', () => {
  const migration = read('supabase/migrations/20260802001700_purchase_voucher_hardening.sql');
  assert.match(migration, /reversal_of_entry_id/);
  assert.match(migration, /reversed_by_entry_id/);
  assert.match(migration, /'journal_reversal'/);
  assert.match(migration, /status = 'reversed'/);
});

test('bank UI describes the flag as manual review rather than statement reconciliation', () => {
  const page = read('src/features/banking/BankingPage.tsx');
  const storage = read('src/features/banking/storage.ts');
  assert.match(page, /تمت مراجعته يدويًا/);
  assert.doesNotMatch(page, /مطابق|إلغاء التسوية|title="تسوية"/);
  assert.match(storage, /set_bank_transaction_reviewed/);
});
