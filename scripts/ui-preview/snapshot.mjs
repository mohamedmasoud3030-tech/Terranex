#!/usr/bin/env node
/**
 * Headless screenshot + basic layout audit of every application route.
 *
 * Requires a chromium binary and puppeteer-core. In the review sandbox they
 * live outside the repo (see PUPPETEER_MODULE / CHROME_PATH env vars); this
 * script is intentionally NOT a project dependency.
 *
 *   PUPPETEER_MODULE=/tmp/chr/node_modules/puppeteer-core \
 *   CHROME_PATH=/tmp/chromium LD_LIBRARY_PATH=/tmp/al2023lib/lib \
 *   node scripts/ui-preview/snapshot.mjs [outDir] [routeFilter]
 *
 * For each route × viewport it records: horizontal overflow, smallest tap
 * target under 40px among interactive elements, number of headings, and
 * writes a PNG. Results land in <outDir>/report.json.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const puppeteer = (await import(process.env.PUPPETEER_MODULE ?? 'puppeteer-core')).default;
const BASE = process.env.PREVIEW_BASE ?? 'http://localhost:3000';
const OUT = process.argv[2] ?? '/tmp/ui-shots';
const FILTER = process.argv[3] ?? '';
mkdirSync(OUT, { recursive: true });

const cookie = execFileSync('node', [path.join(path.dirname(new URL(import.meta.url).pathname), 'mock-supabase.mjs'), '--print-cookie']).toString().trim();
const [cookieName, ...rest] = cookie.split('=');
const cookieValue = rest.join('=');

const RE = '33333333-3333-4333-8333-333333333331';
const AG = '33333333-3333-4333-8333-333333333332';
const LS = '33333333-3333-4333-8333-333333333333';
const PF = '44444444-4444-4444-8444-444444444441';

export const ROUTES = [
  '/login', '/forgot-password',
  '/', '/projects', '/projects/new', '/portfolios', '/portfolios/new', `/portfolios/${PF}`, '/assets', '/invoices', '/journal', '/transactions', '/documents', '/inventory', '/vat', '/reports', '/settings', '/intake', '/onboarding',
  `/projects/${RE}`, `/projects/${RE}/overview`, `/projects/${RE}/funding`, `/projects/${RE}/terms`, `/projects/${RE}/operations`,
  `/projects/${RE}/costs`, `/projects/${RE}/cash`, `/projects/${RE}/adjustments`, `/projects/${RE}/revenue`, `/projects/${RE}/close`, `/projects/${RE}/investors`,
  `/projects/${RE}/pilot`, `/projects/${RE}/controls`, `/projects/${RE}/intake`, `/projects/${RE}/budget`, `/projects/${RE}/integrity`,
  `/projects/${RE}/governance`, `/projects/${RE}/procurement`,
  `/projects/${AG}`, `/projects/${AG}/agriculture`, `/projects/${LS}`, `/projects/${LS}/livestock`, `/projects/${LS}/livestock/operations`,
  '/projects/does-not-exist',
];

const VIEWPORTS = [
  { name: 'mobile', width: 360, height: 780 },
  { name: 'tablet', width: 768, height: 1024 },
  { name: 'laptop', width: 1280, height: 800 },
  { name: 'wide', width: 1600, height: 900 },
];

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH,
  headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage', '--font-render-hinting=none'],
});

const report = [];
for (const route of ROUTES.filter((r) => r.includes(FILTER))) {
  for (const vp of VIEWPORTS) {
    const page = await browser.newPage();
    await page.setViewport({ width: vp.width, height: vp.height, deviceScaleFactor: 1 });
    await page.setCookie({ name: cookieName, value: cookieValue, domain: 'localhost', path: '/' });
    const consoleErrors = [];
    page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 200)); });
    let status = 0;
    try {
      const res = await page.goto(BASE + route, { waitUntil: 'networkidle0', timeout: 90000 });
      status = res?.status() ?? 0;
    } catch (e) {
      report.push({ route, viewport: vp.name, error: String(e).slice(0, 200) });
      await page.close();
      continue;
    }
    const audit = await page.evaluate(() => {
      const doc = document.documentElement;
      const overflowX = doc.scrollWidth - doc.clientWidth;
      const interactive = [...document.querySelectorAll('a,button,input,select,textarea,summary')];
      let smallest = null;
      for (const el of interactive) {
        const r = el.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) continue;
        if (el.type === 'hidden') continue;
        if (smallest === null || r.height < smallest) smallest = Math.round(r.height);
      }
      return {
        overflowX,
        smallestTapTarget: smallest,
        h1: document.querySelectorAll('h1').length,
        h2: document.querySelectorAll('h2').length,
        tables: document.querySelectorAll('table').length,
        forms: document.querySelectorAll('form').length,
        details: document.querySelectorAll('details').length,
        title: document.querySelector('h1')?.textContent?.trim().slice(0, 60) ?? null,
        height: doc.scrollHeight,
        dir: doc.dir,
      };
    });
    const file = path.join(OUT, `${route.replace(/[^a-z0-9]+/gi, '_').replace(/^_|_$/g, '') || 'root'}--${vp.name}.png`);
    await page.screenshot({ path: file, fullPage: true });
    await page.screenshot({ path: file.replace('.png', '.fold.png'), fullPage: false });
    report.push({ route, viewport: vp.name, status, ...audit, consoleErrors, file });
    await page.close();
  }
}
await browser.close();
writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(report, null, 2));
for (const r of report) {
  console.log(`${r.route.padEnd(70)} ${r.viewport.padEnd(7)} ${r.status} ovf=${r.overflowX} tap=${r.smallestTapTarget} h1=${r.h1} tbl=${r.tables} frm=${r.forms} det=${r.details} h=${r.height} ${r.error ?? ''}`);
}
