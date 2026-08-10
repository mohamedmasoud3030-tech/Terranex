#!/usr/bin/env node
// Minimal psql-compatible file runner used by the Greenfield database gate.
// Supports the small subset of psql meta-syntax used by the SQL tests:
//   - `\gset`           stores the previous SELECT row into variables named by columns
//   - `:name`           string substitution of a prior variable (safe: only from \gset)
//   - `:'name'`         quoted literal substitution
//   - all other statements run as-is via node-postgres.
// It correctly handles dollar-quoted function bodies ($$...$$) so semicolons inside
// them do not split statements. It is not a general psql replacement.
import { readFileSync } from 'node:fs';
import pg from 'pg';

const { Client } = pg;

const host = process.env.PGHOST || '/tmp';
const port = Number(process.env.PGPORT || 5433);
const user = process.env.PGUSER || 'postgres';
const password = process.env.PGPASSWORD || 'postgres';
const database = process.env.PGDATABASE || process.env.TERRANEX_TEST_DB || 'terranex_s0_test';
const file = process.argv[2];

if (!file) {
  console.error('usage: psql-runner.mjs <file.sql>');
  process.exit(2);
}

const client = new Client({ host, port, user, password, database, ssl: false });
await client.connect();

const vars = new Map();
const raw = readFileSync(file, 'utf8');

const statements = splitStatements(raw);

for (const entry of statements) {
  if (entry.gset) {
    const stmt = substitute(entry.sql, vars);
    if (stmt.trim()) {
      const res = await client.query(stmt);
      if (res.rows.length > 0) {
        for (const [k, v] of Object.entries(res.rows[0])) {
          vars.set(k, v === null || v === undefined ? '' : String(v));
        }
      }
    }
    continue;
  }
  const stmt = substitute(entry.sql, vars);
  if (stmt.trim()) await client.query(stmt);
}

await client.end();

// Split SQL text into top-level statements on semicolons, respecting:
//  - line comments (--), block comments, single-quoted strings, dollar quotes ($$...$$ and $tag$...$tag$)
//  - a trailing `\gset` directive that belongs to the preceding statement.
function splitStatements(text) {
  const out = [];
  let buf = '';
  let i = 0;
  const n = text.length;
  let dollarTag = null; // set when inside a dollar-quoted string

  while (i < n) {
    const ch = text[i];
    const two = text.slice(i, i + 2);

    // Line comment
    if (!dollarTag && two === '--') {
      const nl = text.indexOf('\n', i);
      const end = nl === -1 ? n : nl;
      buf += text.slice(i, end);
      i = end;
      continue;
    }
    // Block comment
    if (!dollarTag && two === '/*') {
      const close = text.indexOf('*/', i + 2);
      const end = close === -1 ? n : close + 2;
      buf += text.slice(i, end);
      i = end;
      continue;
    }
    // Single-quoted string (handle doubled quotes '')
    if (!dollarTag && ch === "'") {
      let j = i + 1;
      while (j < n) {
        if (text[j] === "'") {
          if (text[j + 1] === "'") { j += 2; continue; }
          j++; break;
        }
        j++;
      }
      buf += text.slice(i, j);
      i = j;
      continue;
    }
    // Dollar quote: detect $tag$ at current position.
    if (ch === '$') {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(text.slice(i));
      if (m) {
        const tag = m[0];
        if (dollarTag === null) {
          dollarTag = tag;
          buf += tag;
          i += tag.length;
          continue;
        } else if (dollarTag === tag) {
          dollarTag = null;
          buf += tag;
          i += tag.length;
          continue;
        }
      }
    }
    // A \gset directive (inline "... as col \gset" or on its own line) marks
    // the statement that *precedes* it as a gset. Handle it before the
    // semicolon branch because the original test file has no semicolon there.
    if (!dollarTag && ch === '\\' && text.slice(i, i + 5) === '\\gset'
        && /(^|\s)\\gset(?![A-Za-z0-9_])/.test(text.slice(Math.max(0, i - 1), i + 6))) {
      // Flush the current buffer as a gset statement.
      out.push({ sql: buf.trim(), gset: true });
      buf = '';
      i += 5;
      while (i < n && text[i] !== '\n') i++;
      continue;
    }
    // Semicolon ends a statement (only outside quotes/comments).
    if (!dollarTag && ch === ';') {
      buf += ';';
      out.push({ sql: buf, gset: false });
      buf = '';
      i++;
      continue;
    }
    buf += ch;
    i++;
  }
  if (buf.trim()) out.push({ sql: buf, gset: false });
  return out;
}

function substitute(text, vmap) {
  let out = text.replace(/:'([a-zA-Z_][a-zA-Z0-9_]*)'/g, (_, n) => {
    const val = vmap.get(n) ?? '';
    return "'" + String(val).replace(/'/g, "''") + "'";
  });
  out = out.replace(/(?<!:):([a-zA-Z_][a-zA-Z0-9_]*)/g, (match, n) =>
    vmap.has(n) ? vmap.get(n) : match
  );
  return out;
}
