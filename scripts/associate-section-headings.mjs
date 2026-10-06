#!/usr/bin/env node
/**
 * Gives every `<section>` on a page an `aria-labelledby` pointing at its own
 * heading, and gives that heading the `id` it needs to be pointed at.
 *
 * Why: a `<section>` with no accessible name is not exposed as a labelled
 * region, so on a page with thirteen to twenty-three sections a screen reader
 * user cannot jump between them by name. The heading is already there and
 * already correct — it is simply not wired up.
 *
 * This is deliberately additive. It does not convert markup to `<Section>`;
 * it adds two attributes and changes nothing else. Idempotent: a section that
 * already has `aria-labelledby`, or a heading that already has an `id`, is
 * left alone.
 *
 * Usage:
 *   node scripts/associate-section-headings.mjs --check   # report only, exit 1 if work needed
 *   node scripts/associate-section-headings.mjs           # apply
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const CHECK = process.argv.includes('--check');

const files = execSync("find src/app -name '*.tsx'", { encoding: 'utf8' })
  .trim()
  .split('\n')
  .filter(Boolean);

/** Index of the `>` that closes the opening tag at `open`, skipping `>` inside
 *  quoted attribute values and JSX expression braces. */
function endOfOpeningTag(source, open) {
  let depth = 0;
  let quote = null;
  for (let i = open; i < source.length; i += 1) {
    const ch = source[i];
    if (quote) {
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'") quote = ch;
    else if (ch === '{') depth += 1;
    else if (ch === '}') depth -= 1;
    else if (ch === '>' && depth === 0) return i;
  }
  return -1;
}

function processFile(file) {
  let source = readFileSync(file, 'utf8');
  const edits = [];
  let counter = 0;

  // Walk sections outermost-first; nested sections are handled when the scan
  // reaches them, so each pass only looks at its own leading heading.
  for (const openMatch of [...source.matchAll(/<section\b/g)]) {
    const open = openMatch.index;
    const tagEnd = endOfOpeningTag(source, open);
    if (tagEnd === -1) continue;
    const attrs = source.slice(open + '<section'.length, tagEnd);
    if (/\baria-labelledby\s*=/.test(attrs)) continue;

    // The section's own content, up to the first nested section if any.
    const nested = source.indexOf('<section', tagEnd);
    const bodyEnd = nested === -1 ? source.length : nested;
    const heading = /<h2\b([^>]*)>/.exec(source.slice(tagEnd, bodyEnd));
    if (!heading) continue;
    const headingAttrs = heading[1];
    if (/\bid\s*=/.test(headingAttrs)) continue;

    const ownId = /\bid="([^"]+)"/.exec(attrs)?.[1];
    counter += 1;
    // Sections that already carry an id (anchor targets for the in-page tab
    // strip) name their heading after themselves. The rest get a readable
    // per-route prefix — the last path segment, not a mangled filename.
    const route = file.split('/').filter((p) => p !== 'page.tsx' && !p.startsWith('[')).pop() ?? 'section';
    const headingId = ownId ? `${ownId}-title` : `${route}-s${counter}`;

    const headingAt = tagEnd + heading.index;
    edits.push({ headingAt, insertAfter: `<h2`, headingId, sectionTagEnd: tagEnd });
  }

  if (edits.length === 0) return 0;

  // Apply from the end backwards so earlier offsets stay valid.
  for (const edit of edits.sort((a, b) => b.headingAt - a.headingAt)) {
    source = `${source.slice(0, edit.headingAt)}<h2 id="${edit.headingId}"${source.slice(edit.headingAt + '<h2'.length)}`;
    source = `${source.slice(0, edit.sectionTagEnd)} aria-labelledby="${edit.headingId}"${source.slice(edit.sectionTagEnd)}`;
  }

  if (!CHECK) writeFileSync(file, source);
  return edits.length;
}

let total = 0;
const touched = [];
for (const file of files) {
  const n = processFile(file);
  if (n > 0) {
    total += n;
    touched.push(`   ${file.replace('src/app/(app)/', '')}: ${n}`);
  }
}

console.log(`[${CHECK ? 'check' : 'apply'}] ${total} section(s) associated across ${touched.length} file(s)`);
if (touched.length) console.log(touched.join('\n'));
if (CHECK && total > 0) process.exit(1);
