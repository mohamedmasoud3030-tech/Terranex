// Tests verifying PR #65 security-hardening migration and client code.
// Mirrors the pattern of existing source-audit tests — parses SQL / TS source
// to prove the security guarantees are present.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

test('migration 0014 drops odoo_api_key column and keeps secrets out of the browser bundle', () => {
  const m = read('supabase/migrations/20260802001400_security_hardening.sql');
  assert.match(m, /alter table company_settings drop column if exists odoo_api_key/);

  // Browser source must never read VITE_ODOO_API_KEY at runtime
  const hooks = read('src/core/odoo/hooks.ts');
  const client = read('src/core/odoo/client.ts');
  assert.doesNotMatch(hooks, /VITE_ODOO_API_KEY|odoo_api_key/);
  assert.doesNotMatch(hooks, /createOdooClient\(/);
  assert.match(hooks, /server-side/);

  // readEnv is hard-disabled (returns null)
  assert.match(client, /function readEnv\(\): null/);

  // Settings form must not load or persist the API key field (comments about the
  // removal are fine — we assert there is no variable/state access or insert).
  const settings = read('src/features/settings/CompanySettingsForm.tsx');
  assert.doesNotMatch(settings, /setOdooApiKey\b/);
  assert.doesNotMatch(settings, /useState\([^)]*odooApiKey/);
  assert.doesNotMatch(settings, /odoo_api_key\s*:/);  // no column write
  assert.match(settings, /يُضبط على الخادم|server-side secret/); // notice present

  // .env.example no longer has a VITE_ODOO_API_KEY entry
  const env = read('.env.example');
  assert.doesNotMatch(env, /^VITE_ODOO_API_KEY=/m);
  assert.match(env, /set-on-server-only/);
});

test('migration 0014 fixes bank_account_balances alias (dep. → d.) and uses security_invoker', () => {
  const m = read('supabase/migrations/20260802001400_security_hardening.sql');
  assert.match(m, /security_invoker = on/);
  // No reference to `dep.` alias (the bug)
  assert.doesNotMatch(m, /dep\.total_in/);
  // View is now scoped by owner_id = auth.uid()
  assert.match(m, /b\.owner_id\s*=\s*auth\.uid\(\)/);
});

test('migration 0014 creates immutable invoice_payments audit table', () => {
  const m = read('supabase/migrations/20260802001400_security_hardening.sql');
  assert.match(m, /create table if not exists invoice_payments/);
  assert.match(m, /request_id text not null/);
  assert.match(m, /unique \(owner_id, request_id\)/);
  assert.match(m, /trg_invoice_payments_immutable/);
  assert.match(m, /سجل الدفعات غير قابل للتعديل/);
});

test('migration 0014 provides server-authoritative atomic create_sales_invoice_atomic', () => {
  const m = read('supabase/migrations/20260802001400_security_hardening.sql');
  assert.match(m, /create or replace function create_sales_invoice_atomic/);
  assert.match(m, /v_owner uuid := auth\.uid\(\)/);
  assert.match(m, /jsonb_array_length\(p_lines\)/);
  assert.match(m, /next_owner_seq/);
  // Server recalculates totals
  assert.match(m, /v_vat := round\(v_subtotal \* coalesce\(p_vat_rate, 0\) \/ 100, 3\)/);
  // Rejects empty lines
  assert.match(m, /بند واحد على الأقل/);
});

test('migration 0014 atomic pay_sales_invoice enforces idempotency, overpayment rejection and cross-owner checks', () => {
  const m = read('supabase/migrations/20260802001400_security_hardening.sql');
  // Idempotency guard
  assert.match(m, /تم استخدام معرّف العملية مسبقاً ببيانات مختلفة/);
  // Overpayment rejection
  assert.match(m, /مبلغ الدفعة يتجاوز المستحق/);
  // Cross-owner bank check
  assert.match(m, /الحساب البنكي لا يخص نفس المالك/);
  // Pay on draft rejected
  assert.match(m, /لا يمكن دفع فاتورة مسودة/);
  // Bank_tx inserted inside the same function
  assert.match(m, /insert into bank_transactions\(/);
  // Immutable audit row inserted
  assert.match(m, /insert into invoice_payments\(/);
});

test('migration 0014 installs immutability triggers for posted invoices, bank_tx, inventory movements', () => {
  const m = read('supabase/migrations/20260802001400_security_hardening.sql');
  assert.match(m, /trg_sales_invoices_immutable/);
  assert.match(m, /trg_sales_invoices_nodelete/);
  assert.match(m, /trg_bank_transactions_protect/);
  assert.match(m, /trg_inventory_movements_nodelete/);
  assert.match(m, /لا يمكن حذف حركة بنكية/);
  assert.match(m, /لا يمكن حذف حركة مخزن/);
});

test('migration 0014 derives owner_id on insert for invoice/inventory/bank lines (defence in depth)', () => {
  const m = read('supabase/migrations/20260802001400_security_hardening.sql');
  assert.match(m, /create or replace function trg_force_owner/);
  assert.match(m, /NEW\.owner_id := auth\.uid\(\)/);
  assert.match(m, /trg_sales_invoice_lines_owner/);
  assert.match(m, /trg_inventory_items_owner/);
  assert.match(m, /trg_inventory_movements_owner/);
  assert.match(m, /trg_bank_transactions_owner/);
});

test('client-side invoice storage uses the atomic create RPC and does NOT insert lines directly', () => {
  const s = read('src/features/invoicing/storage.ts');
  assert.match(s, /create_sales_invoice_atomic/);
  assert.match(s, /p_lines/);
  // No direct insert into sales_invoice_lines in create path
  const createFn = s.slice(s.indexOf('async function createInvoice'), s.indexOf('export async function issueInvoice'));
  assert.doesNotMatch(createFn, /\.from\('sales_invoice_lines'\)\s*\.insert/);
});

test('client-side payInvoice does NOT post its own bank_transaction (RPC does it atomically)', () => {
  const s = read('src/features/invoicing/storage.ts');
  // No linkFinancialMovement call in payInvoice — the SQL RPC posts the bank_tx
  const payFn = s.slice(s.indexOf('async function payInvoice'));
  assert.doesNotMatch(payFn, /linkFinancialMovement|recordManualBankTransaction|from\('bank_transactions'\)\.insert/);
  assert.match(payFn, /rpc\('pay_sales_invoice'/);
});

test('rollback for 0014 restores company_settings odoo_api_key and previous state', () => {
  const r = read('supabase/rollback/20260802001400_security_hardening.sql');
  assert.match(r, /add column if not exists odoo_api_key/);
  assert.match(r, /drop table if exists invoice_payments/);
  assert.match(r, /drop function if exists create_sales_invoice_atomic/);
});

test('SQL RLS test suite exists for invoices/banking/inventory two-owner isolation', () => {
  const t = read('supabase/tests/07_invoices_banking_inventory_rls.sql');
  assert.match(t, /alice@terranex\.test/);
  assert.match(t, /bob@terranex\.test/);
  assert.match(t, /odoo_api_key still present/); // negative assertion inside
  assert.match(t, /invoice_payments audit/i);
  assert.match(t, /bank_transactions row not created|bank_tx created/i);
  assert.match(t, /DELETE bank_transaction rejected/);
  assert.match(t, /overpayment/i);
  assert.match(t, /cross-owner/i);
});
