const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('Egypt-first migration uses a transactional owner-scoped Odoo outbox', () => {
  const source = read('supabase/migrations/20260804000100_odoo_egypt_bridge.sql');
  assert.match(source, /country set default 'EG'/);
  assert.match(source, /base_currency set default 'EGP'/);
  assert.match(source, /odoo_localization text not null default 'l10n_eg'/);
  assert.match(source, /create table if not exists odoo_sync_outbox/);
  assert.match(source, /after insert or update on partners/);
  assert.match(source, /after insert or update on projects/);
  assert.match(source, /force row level security/);
  assert.match(source, /claim_odoo_sync_batch/);
  assert.match(source, /for update skip locked/);
  assert.match(source, /grant execute on function claim_odoo_sync_batch.*service_role/s);
});

test('invoice events are limited to issue, receipt and void lifecycle changes', () => {
  const source = read('supabase/migrations/20260804000200_odoo_invoice_event_scope.sql');
  assert.match(source, /v_old_status = 'draft'/);
  assert.match(source, /sales_invoice.*v_status = 'issued'/s);
  assert.match(source, /purchase_invoice.*v_status = 'received'/s);
  assert.match(source, /partial\/paid changes belong to the payment bridge/);
});

test('Odoo API credentials exist only in the Edge Function environment', () => {
  const edge = read('supabase/functions/odoo-sync/index.ts');
  const envExample = read('.env.example');
  const browserHooks = read('src/core/odoo/hooks.ts');

  assert.match(edge, /env\('ODOO_API_KEY'\)/);
  assert.match(edge, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(edge, /auth\.getUser\(\)/);
  assert.match(edge, /p_owner_id: userData\.user\.id/);
  assert.doesNotMatch(edge, /VITE_ODOO/);
  assert.doesNotMatch(envExample, /VITE_ODOO_API_KEY/);
  assert.match(browserHooks, /functions\.invoke\('odoo-sync'/);
  assert.doesNotMatch(browserHooks, /createOdooClient|ODOO_API_KEY/);
});

test('company settings are Egypt-first and describe the honest bridge scope', () => {
  const source = read('src/features/settings/CompanySettingsForm.tsx');
  assert.match(source, /useState<CompanySettings\['country'\]>\('EG'\)/);
  assert.match(source, /useState<Currency>\('EGP'\)/);
  assert.match(source, /odoo_localization: 'l10n_eg'/);
  assert.match(source, /حسابات البنك ومدفوعات العملاء والموردين/);
  assert.match(source, /القيود التشغيلية والإرسال الإلكتروني الفعلي إلى ETA ما زالا خارج النطاق الحالي/);
});

test('sales and purchase invoice posting drains the durable outbox', () => {
  const sales = read('src/features/invoicing/storage.ts');
  const purchases = read('src/features/invoicing/purchaseStorage.ts');
  assert.match(sales, /issue_sales_invoice[\s\S]*requestOdooSync\(\)/);
  assert.match(purchases, /receive_purchase_invoice_with_stock[\s\S]*requestOdooSync\(\)/);
});

test('payments and bank accounts are queued transactionally and drained best-effort', () => {
  const migration = read('supabase/migrations/20260804000300_odoo_payments_banking.sql');
  const sales = read('src/features/invoicing/storage.ts');
  const purchases = read('src/features/invoicing/purchaseStorage.ts');
  const banking = read('src/features/banking/storage.ts');

  assert.match(migration, /'bank_account','sales_payment','purchase_payment'/);
  assert.match(migration, /after insert on invoice_payments/);
  assert.match(migration, /after insert on purchase_invoice_payments/);
  assert.match(migration, /after insert or update on bank_accounts/);
  assert.match(migration, /Payment audit rows remain[\s\S]*immutable/);
  assert.match(sales, /pay_sales_invoice[\s\S]*requestOdooSync\(\)/);
  assert.match(purchases, /pay_purchase_invoice[\s\S]*requestOdooSync\(\)/);
  assert.match(banking, /createBankAccount[\s\S]*requestOdooSync\(\)/);
  assert.match(banking, /updateBankAccount[\s\S]*requestOdooSync\(\)/);
  assert.match(banking, /archiveBankAccount[\s\S]*requestOdooSync\(\)/);
});

test('Odoo worker uses payment register to post and reconcile against mapped invoices', () => {
  const edge = read('supabase/functions/odoo-sync/index.ts');

  assert.match(edge, /account\.payment\.register/);
  assert.match(edge, /action_create_payments/);
  assert.match(edge, /active_model: 'account\.move'/);
  assert.match(edge, /default_journal_id: journalId/);
  assert.match(edge, /payment_difference_handling: 'open'/);
  assert.match(edge, /account\.journal/);
  assert.match(edge, /account\.payment/);
  assert.match(edge, /existing.*account\.payment/s);
  assert.doesNotMatch(edge, /VITE_ODOO/);
});

test('only explicit posted manual vouchers enter the Odoo outbox', () => {
  const migration = read('supabase/migrations/20260804000400_odoo_manual_journals.sql');
  const journal = read('src/features/finance/journalStorage.ts');

  assert.match(migration, /'journal_entry'/);
  assert.match(migration, /new\.status <> 'posted'/);
  assert.match(migration, /old\.status is not distinct from 'posted'/);
  assert.match(migration, /j\.status in \('posted','reversed'\)/);
  assert.match(migration, /Derived reporting[\s\S]*prevent duplicate accounting/);
  assert.match(migration, /available_at = 'infinity'::timestamptz/);
  assert.match(migration, /terranex_release_odoo_journal_reversals/);
  assert.match(journal, /post_journal_entry[\s\S]*requestOdooSync\(\)/);
  assert.match(journal, /void_journal_entry[\s\S]*requestOdooSync\(\)/);
});

test('manual journals resolve the Egyptian chart, FX, analytics and bank accounts before posting', () => {
  const edge = read('supabase/functions/odoo-sync/index.ts');
  const envExample = read('.env.example');

  assert.match(edge, /ODOO_MISC_JOURNAL_ID/);
  assert.match(edge, /account\.account/);
  assert.match(edge, /\['company_ids', 'in', \[companyId\]\]/);
  assert.match(edge, /default_account_id/);
  assert.match(edge, /move_type: 'entry'/);
  assert.match(edge, /amount_currency/);
  assert.match(edge, /analytic_distribution/);
  assert.match(edge, /Manual journal becomes unbalanced after EGP conversion/);
  assert.match(edge, /syncJournalEntryRecord[\s\S]*action_post/);
  assert.match(edge, /reversal_of_entry_id[\s\S]*syncJournalEntryRecord/);
  assert.match(envExample, /ODOO_MISC_JOURNAL_ID/);
});
