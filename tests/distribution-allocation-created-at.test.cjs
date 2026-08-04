const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(
  path.join(root, 'supabase/migrations/20260804145944_add_distribution_allocations_created_at.sql'),
  'utf8',
);
const rollback = fs.readFileSync(
  path.join(root, 'supabase/rollback/20260804145944_add_distribution_allocations_created_at.down.sql'),
  'utf8',
);

test('distribution allocations expose a stable creation timestamp for UI ordering', () => {
  assert.match(
    migration,
    /alter table public\.distribution_allocations[\s\S]*add column if not exists created_at timestamptz not null default now\(\)/i,
  );
});

test('rollback removes the allocation timestamp cleanly', () => {
  assert.match(
    rollback,
    /alter table public\.distribution_allocations[\s\S]*drop column if exists created_at/i,
  );
});
