const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const srcRoot = path.join(root, 'src');
const migrationsRoot = path.join(root, 'supabase', 'migrations');

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}

function sourceFiles() {
  return walk(srcRoot).filter((file) => /\.(?:ts|tsx)$/.test(file));
}

function migrationSql() {
  return fs.readdirSync(migrationsRoot)
    .filter((name) => name.endsWith('.sql'))
    .sort()
    .map((name) => fs.readFileSync(path.join(migrationsRoot, name), 'utf8'))
    .join('\n');
}

function resolveToken(token, constants) {
  const trimmed = token.trim();
  const literal = trimmed.match(/^['"]([^'"]+)['"]$/);
  if (literal) return literal[1];
  return constants.get(trimmed) ?? null;
}

function extractRuntimeContracts() {
  const relations = new Set();
  const orderPairs = new Set();
  const rpcNames = new Set();
  const unresolved = [];

  for (const file of sourceFiles()) {
    const relative = path.relative(root, file);
    const source = fs.readFileSync(file, 'utf8');
    const constants = new Map();

    for (const match of source.matchAll(/\bconst\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*['"]([^'"]+)['"]/g)) {
      constants.set(match[1], match[2]);
    }

    if (!relative.endsWith(path.join('src', 'core', 'storage', 'supabaseStore.ts'))) {
      for (const match of source.matchAll(/createSupabaseStore<[^>]+>\(\s*([^,]+),\s*([^,\)]+?)(?:,\s*['"]([^'"]+)['"])?\s*,?\s*\)/g)) {
        const relation = resolveToken(match[1], constants);
        if (!relation) {
          unresolved.push(`${relative}: unresolved createSupabaseStore relation ${match[1].trim()}`);
          continue;
        }
        const orderColumn = match[3] ?? 'created_at';
        relations.add(relation);
        orderPairs.add(`${relation}.${orderColumn}`);
      }
    }

    for (const match of source.matchAll(/\.from\(\s*([^\)]+?)\s*\)([^;]{0,800}?)(?:\.order\(\s*['"]([^'"]+)['"]|$)/g)) {
      const relation = resolveToken(match[1], constants);
      if (!relation) {
        unresolved.push(`${relative}: unresolved from() relation ${match[1].trim()}`);
        continue;
      }
      relations.add(relation);
      if (match[3]) orderPairs.add(`${relation}.${match[3]}`);
    }

    for (const match of source.matchAll(/\.rpc\(\s*['"]([^'"]+)['"]/g)) {
      rpcNames.add(match[1]);
    }
  }

  return { relations, orderPairs, rpcNames, unresolved };
}

function parseMigrationSchema(sql) {
  const tables = new Map();
  const views = new Map();
  const functions = new Set();

  for (const match of sql.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z_][a-z0-9_]*)\s*\(([\s\S]*?)\n\);/gi)) {
    const table = match[1].toLowerCase();
    const columns = tables.get(table) ?? new Set();
    for (const rawLine of match[2].split('\n')) {
      const line = rawLine.replace(/--.*$/, '').trim();
      const column = line.match(/^"?([a-z_][a-z0-9_]*)"?\s+/i)?.[1]?.toLowerCase();
      if (!column || ['constraint', 'primary', 'unique', 'foreign', 'check', 'exclude'].includes(column)) continue;
      columns.add(column);
    }
    tables.set(table, columns);
  }

  for (const statement of sql.split(';')) {
    const table = statement.match(/alter\s+table\s+(?:if\s+exists\s+)?(?:public\.)?([a-z_][a-z0-9_]*)/i)?.[1]?.toLowerCase();
    if (!table) continue;
    const columns = tables.get(table) ?? new Set();
    for (const match of statement.matchAll(/add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?/gi)) {
      columns.add(match[1].toLowerCase());
    }
    tables.set(table, columns);
  }

  for (const match of sql.matchAll(/create\s+(?:or\s+replace\s+)?view\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*(?:with\s*\([^)]*\)\s*)?as\s+([\s\S]*?);/gi)) {
    views.set(match[1].toLowerCase(), match[2].toLowerCase());
  }

  for (const match of sql.matchAll(/create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z_][a-z0-9_]*)/gi)) {
    functions.add(match[1].toLowerCase());
  }

  return { tables, views, functions };
}

test('every runtime Supabase relation and order column exists in the migration schema', () => {
  const runtime = extractRuntimeContracts();
  const schema = parseMigrationSchema(migrationSql());

  assert.deepEqual(runtime.unresolved, [], runtime.unresolved.join('\n'));
  assert.ok(runtime.relations.size >= 20, `expected broad runtime coverage, found only ${runtime.relations.size} relations`);
  assert.ok(runtime.orderPairs.size >= 15, `expected broad order-column coverage, found only ${runtime.orderPairs.size} pairs`);
  assert.ok(runtime.orderPairs.has('distribution_allocations.created_at'));

  for (const relation of runtime.relations) {
    assert.ok(
      schema.tables.has(relation) || schema.views.has(relation),
      `runtime relation ${relation} is missing from the migration schema`,
    );
  }

  for (const pair of runtime.orderPairs) {
    const separator = pair.lastIndexOf('.');
    const relation = pair.slice(0, separator);
    const column = pair.slice(separator + 1);
    if (schema.tables.has(relation)) {
      assert.ok(
        schema.tables.get(relation).has(column),
        `runtime query orders ${relation} by missing column ${column}`,
      );
    } else {
      const viewSql = schema.views.get(relation);
      assert.ok(viewSql, `runtime view ${relation} is missing`);
      assert.match(viewSql, new RegExp(`\\b${column}\\b`, 'i'), `runtime view ${relation} does not expose ${column}`);
    }
  }
});

test('every literal frontend RPC exists in the migration schema', () => {
  const runtime = extractRuntimeContracts();
  const schema = parseMigrationSchema(migrationSql());

  assert.ok(runtime.rpcNames.size >= 15, `expected broad RPC coverage, found only ${runtime.rpcNames.size} RPCs`);
  for (const rpc of runtime.rpcNames) {
    assert.ok(schema.functions.has(rpc.toLowerCase()), `frontend RPC ${rpc} is missing from migrations`);
  }
});
