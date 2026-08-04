const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('owner derivation preserves validated trusted-server ownership but rejects authenticated spoofing', () => {
  const migration = read('supabase/migrations/20260804000700_owner_derivation_rpc_safety.sql');

  assert.match(migration, /v_authenticated_owner uuid := auth\.uid\(\)/);
  assert.match(migration, /new\.owner_id <> v_authenticated_owner/);
  assert.match(migration, /errcode = '42501'/);
  assert.match(migration, /new\.owner_id := v_authenticated_owner/);
  assert.match(migration, /elsif new\.owner_id is null/);
  assert.match(migration, /trusted server derivation/);
  assert.match(migration, /set search_path = public, auth, pg_temp/);
});

test('owner derivation safety migration has a matching rollback', () => {
  const rollback = read('supabase/rollback/20260804000700_owner_derivation_rpc_safety.down.sql');
  assert.match(rollback, /create or replace function trg_force_owner/);
  assert.match(rollback, /new\.owner_id := auth\.uid\(\)/);
});
