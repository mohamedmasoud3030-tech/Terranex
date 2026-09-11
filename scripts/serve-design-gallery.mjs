#!/usr/bin/env node
/**
 * Serves the generated design gallery so it can be looked at rather than read.
 *
 * `docs/design/design-system.html` is self-contained — scripts/build-design-gallery.mjs
 * inlines globals.css into it — so this needs no build step and no dependencies.
 * Serves that one file at `/` and binds 0.0.0.0 so it is reachable from outside
 * the sandbox.
 *
 * Usage: node scripts/serve-design-gallery.mjs [port]
 */
import { createServer } from 'node:http';
import { readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const PORT = Number(process.argv[2] ?? 4173);
const FILE = join(process.cwd(), 'docs/design/design-system.html');

const server = createServer((req, res) => {
  const url = (req.url ?? '/').split('?')[0];
  if (url !== '/' && url !== '/index.html' && url !== '/design-system.html') {
    res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('Not found — the gallery is a single self-contained document at /');
    return;
  }
  let body;
  try {
    body = readFileSync(FILE);
  } catch {
    res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(
      'docs/design/design-system.html is missing.\n' +
        'Generate it first: node scripts/build-design-gallery.mjs',
    );
    return;
  }
  res.writeHead(200, {
    'content-type': 'text/html; charset=utf-8',
    'content-length': body.length,
    // The gallery embeds no scripts; a strict CSP keeps it honest about that.
    'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'; img-src data:;",
  });
  res.end(body);
});

const size = (() => {
  try {
    return `${(statSync(FILE).size / 1024).toFixed(1)} kB`;
  } catch {
    return 'missing';
  }
})();

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[gallery] serving docs/design/design-system.html (${size}) on 0.0.0.0:${PORT}`);
});
