const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const migration = read('supabase/migrations/20260804000800_revoke_public_rpc_execute.sql');

test('sales invoice SECURITY DEFINER RPCs are anonymous-deny and authenticated-allow', () => {
  assert.match(
    migration,
    /revoke all on function public\.create_sales_invoice_atomic[\s\S]*from public, anon;/,
  );
  assert.match(
    migration,
    /grant execute on function public\.create_sales_invoice_atomic[\s\S]*to authenticated, service_role;/,
  );
  assert.match(
    migration,
    /revoke all on function public\.pay_sales_invoice[\s\S]*from public, anon;/,
  );
  assert.match(
    migration,
    /grant execute on function public\.pay_sales_invoice[\s\S]*to authenticated, service_role;/,
  );
});

test('financial helper functions cannot be called by public API roles', () => {
  for (const helper of [
    'terranex_assert_owner',
    'terranex_lock_financial_request',
    'terranex_audit_check_idempotent',
    'terranex_audit_log',
  ]) {
    assert.match(
      migration,
      new RegExp(`revoke all on function public\\.${helper}[\\s\\S]*?from public, anon, authenticated;`),
      `${helper} must not remain externally executable`,
    );
  }
});

test('all trigger functions are dynamically removed from the PostgREST RPC surface', () => {
  assert.match(migration, /p\.prorettype = 'pg_catalog\.trigger'::regtype/);
  assert.match(
    migration,
    /revoke all on function %I\.%I\(%s\) from public, anon, authenticated/,
  );
});

test('security hardening has a deliberate non-reopening rollback', () => {
  const rollback = read('supabase/rollback/20260804000800_revoke_public_rpc_execute.down.sql');
  assert.doesNotMatch(rollback, /grant execute[\s\S]*to public/i);
  assert.match(rollback, /intentionally not reversed/i);
});
