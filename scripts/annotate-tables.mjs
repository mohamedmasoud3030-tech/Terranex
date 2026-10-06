#!/usr/bin/env node
/**
 * Gives every data table an accessible name and column scope.
 *
 * A <table> with no <caption> is announced as an unnamed grid, and a <th>
 * with no scope is not reliably associated with its column. Both are cheap to
 * fix and expensive to leave: this is a finance product read by operators who
 * may well be using a screen reader.
 *
 * Captions are derived mechanically from the table's own Arabic column
 * headers, so no caption can misdescribe a table. Tables whose headers contain
 * JSX expressions are reported and left for manual wording rather than being
 * given a caption that could be wrong.
 *
 * Idempotent. Run with --check to report without writing.
 *
 * Usage: node ./scripts/annotate-tables.mjs [--check]
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const CHECK = process.argv.includes('--check');

const files = execSync("find src -name '*.tsx'", { encoding: 'utf8' })
  .trim()
  .split('\n')
  .filter(Boolean);

let captionsAdded = 0;
let scopesAdded = 0;
const skipped = [];

for (const file of files) {
  const source = readFileSync(file, 'utf8');
  if (!source.includes('<table')) continue;
  let out = source;

  out = out.replace(/<table\b[^>]*>([\s\S]*?)<\/table>/g, (table) => {
    let next = table;

    const headRow = next.match(/<thead>\s*<tr>([\s\S]*?)<\/tr>/);
    const headerCells = headRow
      ? [...headRow[1].matchAll(/<th\b([^>]*)>([\s\S]*?)<\/th>/g)]
      : [];

    // Column scope. Skip headers that already declare one, and skip the
    // row-header pattern (a <th> inside <tbody>).
    if (headRow) {
      let patchedHead = headRow[0];
      for (const cell of headerCells) {
        const attrs = cell[1];
        if (/\bscope=/.test(attrs)) continue;
        const whole = cell[0];
        patchedHead = patchedHead.replace(whole, whole.replace(/<th\b/, '<th scope="col"'));
        scopesAdded += 1;
      }
      next = next.replace(headRow[0], patchedHead);
    }

    // Accessible name. Only when the headers are static Arabic text, so the
    // caption is derived from the table itself and cannot misdescribe it.
    const alreadyNamed = /<caption\b/.test(next) || /\baria-label/.test(next.slice(0, next.indexOf('>') + 1));
    if (!alreadyNamed && headerCells.length) {
      const labels = headerCells.map((cell) => cell[2].replace(/<[^>]*>/g, '').trim());
      const hasExpression = headerCells.some((cell) => /\{/.test(cell[2]));
      if (hasExpression || labels.some((label) => !label)) {
        skipped.push(`${file} (dynamic or empty header text)`);
      } else {
        const caption = `<caption className="sr-only">جدول: ${labels.join(' · ')}</caption>`;
        next = next.replace(/(<table\b[^>]*>)/, `$1\n              ${caption}`);
        captionsAdded += 1;
      }
    }

    return next;
  });

  if (out !== source) {
    if (!CHECK) writeFileSync(file, out, 'utf8');
    else console.log('  would patch', file);
  }
}

console.log(
  `${CHECK ? '[check] ' : ''}${captionsAdded} caption(s) added, ${scopesAdded} column scope(s) added`,
);
if (skipped.length) {
  console.log(`\n${skipped.length} table(s) left for manual wording:`);
  for (const entry of skipped) console.log('  ', entry);
}
