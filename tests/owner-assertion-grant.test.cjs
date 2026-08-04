const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(
  path.join(root, 'supabase/migrations/20260804000900_restore_authenticated_owner_assertion.sql'),
  'utf8',
);
const rollback = fs.readFileSync(
  path.join(root, 'supabase/rollback/20260804000900_restore_authenticated_owner_assertion.down.sql'),
  'utf8',
);

test('owner assertion remains denied to anonymous roles and allowed to authenticated callers', () => {
  assert.match(
    migration,
    /revoke all on function public\.terranex_assert_owner\(uuid\)[\s\S]*from public, anon;/,
  );
  assert.match(
    migration,
    /grant execute on function public\.terranex_assert_owner\(uuid\)[\s\S]*to authenticated, service_role;/,
  );
  assert.doesNotMatch(migration, /grant execute[\s\S]*to public|grant execute[\s\S]*to anon/i);
});

test('rollback cannot break SECURITY INVOKER RPC dependencies', () => {
  assert.doesNotMatch(rollback, /revoke[\s\S]*authenticated/i);
  assert.match(rollback, /required by SECURITY INVOKER/i);
});
