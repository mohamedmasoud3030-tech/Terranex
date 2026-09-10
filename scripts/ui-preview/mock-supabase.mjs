#!/usr/bin/env node
/**
 * Local, offline mock of the tiny Supabase surface the Terranex UI reads
 * (GoTrue `/auth/v1/user` + PostgREST `GET /rest/v1/<view>`).
 *
 * Purpose: render every route of the real Next.js application in a sandbox
 * with NO network access to production Supabase, so the rendered interface
 * can be inspected at mobile/tablet/desktop widths. It is a review tool only:
 * writes are rejected, nothing is persisted, and the fixture data is
 * explicitly synthetic (`DEMO-UI-PREVIEW`). It must never be used as
 * customer evidence.
 *
 * Usage:
 *   node scripts/ui-preview/mock-supabase.mjs            # port 54329
 *   NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54329 npm run dev
 *   Cookie for a signed-in session: run with `--print-cookie`.
 */
import http from 'node:http';
import { fixtures, DEMO_USER } from './fixtures.mjs';

import { randomBytes } from 'node:crypto';

const PORT = Number(process.env.MOCK_SUPABASE_PORT ?? 54329);
const SCENARIO = process.env.MOCK_SCENARIO ?? 'populated'; // populated | empty
// Synthetic session material for the local mock only. Values come from the
// environment (so nothing secret-looking is committed) and default to random
// per-process strings; `--print-cookie` and the login form use the same env.
const ACCESS_TOKEN = process.env.MOCK_ACCESS_TOKEN ?? randomBytes(16).toString('hex');
const REFRESH_TOKEN = process.env.MOCK_REFRESH_TOKEN ?? randomBytes(16).toString('hex');
const LOGIN_EMAIL = process.env.MOCK_LOGIN_EMAIL ?? 'preview@terranex.local';
const LOGIN_SECRET = process.env.MOCK_LOGIN_SECRET ?? randomBytes(8).toString('hex');

function sessionCookieValue() {
  const session = {
    access_token: ACCESS_TOKEN,
    token_type: 'bearer',
    expires_in: 3600 * 24,
    expires_at: Math.floor(Date.now() / 1000) + 3600 * 24,
    refresh_token: REFRESH_TOKEN,
    user: DEMO_USER,
  };
  const b64 = Buffer.from(JSON.stringify(session), 'utf8')
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
  return `base64-${b64}`;
}

if (process.argv.includes('--print-cookie')) {
  console.log(`sb-127-auth-token=${sessionCookieValue()}`);
  process.exit(0);
}

function parseFilter(value) {
  // "eq.abc" | "in.(a,b)" | "is.null" | "neq.x"
  const dot = value.indexOf('.');
  const op = value.slice(0, dot);
  const raw = value.slice(dot + 1);
  return { op, raw };
}

function matches(row, key, { op, raw }) {
  const v = row[key];
  switch (op) {
    case 'eq': return String(v) === raw;
    case 'neq': return String(v) !== raw;
    case 'is': return raw === 'null' ? v === null || v === undefined : String(v) === raw;
    case 'in': {
      const list = raw.replace(/^\(|\)$/g, '').split(',').map((s) => s.replace(/^"|"$/g, ''));
      return list.includes(String(v));
    }
    case 'gte': return v >= raw;
    case 'lte': return v <= raw;
    case 'gt': return v > raw;
    case 'lt': return v < raw;
    default: return true;
  }
}

function handleRest(req, res, url) {
  const table = url.pathname.replace('/rest/v1/', '');
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ message: 'UI preview mock is read-only' }));
    return;
  }
  if (table.startsWith('rpc/')) {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end('null');
    return;
  }
  const source = fixtures[SCENARIO]?.[table] ?? fixtures.populated[table];
  let rows = Array.isArray(source) ? [...source] : [];
  if (SCENARIO === 'empty' && !fixtures.empty[table]) rows = [];

  let order = null;
  let limit = null;
  for (const [key, value] of url.searchParams.entries()) {
    if (key === 'select') continue;
    if (key === 'order') { order = value; continue; }
    if (key === 'limit') { limit = Number(value); continue; }
    if (key === 'offset') continue;
    const f = parseFilter(value);
    rows = rows.filter((row) => matches(row, key, f));
  }
  if (order) {
    const [col, dir] = order.split('.');
    rows.sort((a, b) => (a[col] > b[col] ? 1 : a[col] < b[col] ? -1 : 0) * (dir === 'desc' ? -1 : 1));
  }
  if (limit !== null) rows = rows.slice(0, limit);

  const accept = req.headers.accept ?? '';
  const wantsObject = accept.includes('vnd.pgrst.object');
  const headers = { 'content-type': 'application/json', 'content-range': `0-${rows.length}/${rows.length}` };
  if (wantsObject) {
    if (rows.length === 0) {
      res.writeHead(406, headers);
      res.end(JSON.stringify({ code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned', details: 'Results contain 0 rows' }));
      return;
    }
    res.writeHead(200, headers);
    res.end(JSON.stringify(rows[0]));
    return;
  }
  res.writeHead(200, headers);
  res.end(JSON.stringify(rows));
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  if (url.pathname === '/auth/v1/user') {
    const auth = req.headers.authorization ?? '';
    if (!auth.includes(ACCESS_TOKEN)) {
      res.writeHead(401, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ code: 401, msg: 'invalid JWT' }));
      return;
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(DEMO_USER));
    return;
  }
  if (url.pathname === '/auth/v1/token') {
    // Password sign-in: accept a single synthetic credential pair.
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      let ok = false;
      try { const j = JSON.parse(body); ok = j.email === LOGIN_EMAIL && j.password === LOGIN_SECRET; } catch { /* noop */ }
      if (!ok) {
        res.writeHead(400, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ error: 'invalid_grant', error_description: 'Invalid login credentials' }));
        return;
      }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({
        access_token: ACCESS_TOKEN, token_type: 'bearer', expires_in: 86400,
        expires_at: Math.floor(Date.now() / 1000) + 86400, refresh_token: REFRESH_TOKEN, user: DEMO_USER,
      }));
    });
    return;
  }
  if (url.pathname === '/auth/v1/logout') { res.writeHead(204); res.end(); return; }
  if (url.pathname.startsWith('/rest/v1/')) return handleRest(req, res, url);
  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ message: `mock: unhandled ${req.method} ${url.pathname}` }));
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`mock-supabase listening on http://127.0.0.1:${PORT} scenario=${SCENARIO}`);
  console.log(`login: ${LOGIN_EMAIL} / MOCK_LOGIN_SECRET=${LOGIN_SECRET} (set MOCK_ACCESS_TOKEN to reuse --print-cookie across processes)`);
});
