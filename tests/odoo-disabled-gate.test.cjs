const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

const workers = [
  {
    name: 'general Odoo worker',
    path: 'supabase/functions/odoo-sync/index.ts',
    claim: "service.rpc('claim_odoo_sync_batch'",
    client: 'new OdooServerClient()',
  },
  {
    name: 'investor Odoo worker',
    path: 'supabase/functions/odoo-investor-sync/index.ts',
    claim: "service.rpc('claim_odoo_investor_sync_batch'",
    client: 'new OdooClient()',
  },
];

for (const worker of workers) {
  test(`${worker.name} skips disabled owners before claiming rows or reading Odoo secrets`, () => {
    const source = read(worker.path);
    const settingsRead = source.indexOf(".select('odoo_enabled,country,base_currency,odoo_localization')");
    const disabledGate = source.indexOf('if (!settings?.odoo_enabled)');
    const claim = source.indexOf(worker.claim);
    const client = source.indexOf(worker.client, claim);

    assert.ok(settingsRead >= 0, `${worker.path} must read company Odoo settings`);
    assert.ok(disabledGate > settingsRead, `${worker.path} must gate after settings load`);
    assert.ok(claim > disabledGate, `${worker.path} must not claim rows before the disabled gate`);
    assert.ok(client > claim, `${worker.path} must not instantiate the Odoo client before the disabled gate`);

    const gateBody = source.slice(disabledGate, claim);
    assert.match(gateBody, /processed:\s*0/);
    assert.match(gateBody, /skipped:\s*true/);
  });
}

test('worker claim RPCs stay outside the authenticated SECURITY DEFINER allowlist', () => {
  const allowlist = read('docs/security/AUTHENTICATED_SECURITY_DEFINER_ALLOWLIST.md');
  const exactSection = allowlist.match(/## Exact allowlist([\s\S]*?)## Explicitly forbidden from the allowlist/)?.[1] ?? '';

  assert.doesNotMatch(exactSection, /claim_odoo_sync_batch/);
  assert.doesNotMatch(exactSection, /claim_odoo_investor_sync_batch/);
  assert.match(allowlist, /Odoo worker claim, complete, and fail helpers/);
});
