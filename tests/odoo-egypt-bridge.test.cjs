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
  assert.match(source, /ربط المدفوعات وETA الإلكتروني يأتي في المرحلة التالية/);
});

test('sales and purchase invoice posting drains the durable outbox', () => {
  const sales = read('src/features/invoicing/storage.ts');
  const purchases = read('src/features/invoicing/purchaseStorage.ts');
  assert.match(sales, /issue_sales_invoice[\s\S]*requestOdooSync\(\)/);
  assert.match(purchases, /receive_purchase_invoice_with_stock[\s\S]*requestOdooSync\(\)/);
  assert.match(sales, /Payment-to-Odoo posting is deliberately deferred/);
  assert.match(purchases, /Payment-to-Odoo posting is deliberately deferred/);
});
