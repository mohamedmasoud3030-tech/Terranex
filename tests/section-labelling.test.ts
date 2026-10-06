import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { describe, expect, it } from 'vitest';

/**
 * Sections are labelled by their own heading.
 *
 * A `<section>` with no accessible name is not exposed as a labelled region,
 * so on a page with thirteen to twenty-three sections a screen reader user
 * cannot jump between them by name — they have to read the whole page linearly.
 * The heading is already present and already correct; it only has to be wired
 * up, which is what scripts/associate-section-headings.mjs does.
 *
 * Two properties are asserted, because the second is the one a codemod gets
 * wrong: that every section with a heading is labelled, and that every
 * `aria-labelledby` points at an id that actually exists in the same document.
 * A dangling reference is silent — the section simply stays unnamed.
 */

const files = execSync("find src/app -name '*.tsx'", { encoding: 'utf8' })
  .trim()
  .split('\n')
  .filter(Boolean);

function analyse(file: string) {
  const source = readFileSync(file, 'utf8');
  const ids = new Set([...source.matchAll(/\bid="([^"{}]+)"/g)].map((m) => m[1]));
  const labelled = [...source.matchAll(/aria-labelledby="([^"]+)"/g)].map((m) => m[1]);
  const sections = [...source.matchAll(/<section\b[^>]*>/g)].map((m) => m[0]);
  return { source, ids, labelled, sections };
}

describe('section labelling', () => {
  it('every aria-labelledby resolves to an id in the same file', () => {
    const dangling: string[] = [];
    for (const file of files) {
      const { ids, labelled } = analyse(file);
      for (const ref of labelled) {
        if (!ids.has(ref)) dangling.push(`${file} -> ${ref}`);
      }
    }
    expect(dangling).toEqual([]);
  });

  it('no id is duplicated within a file', () => {
    const dupes: string[] = [];
    for (const file of files) {
      const source = readFileSync(file, 'utf8');
      const seen = new Set<string>();
      for (const m of source.matchAll(/\bid="([^"{}]+)"/g)) {
        if (seen.has(m[1])) dupes.push(`${file} -> ${m[1]}`);
        seen.add(m[1]);
      }
    }
    expect(dupes).toEqual([]);
  });

  it('no section or heading carries a duplicated attribute', () => {
    // The failure mode of an attribute-inserting codemod: a second
    // `className` or `id` on the same tag, which React resolves by last-wins
    // and which TypeScript does not always reject.
    const bad: string[] = [];
    for (const file of files) {
      const source = readFileSync(file, 'utf8');
      for (const m of source.matchAll(/<(?:section|h2)\b[^>]*>/g)) {
        for (const attr of ['aria-labelledby', 'id', 'className']) {
          const n = (m[0].match(new RegExp(`\\b${attr}=`, 'g')) ?? []).length;
          if (n > 1) bad.push(`${file}: ${attr} x${n}`);
        }
      }
    }
    expect(bad).toEqual([]);
  });

  it('every top-level section that opens with an h2 is labelled', () => {
    const unnamed: string[] = [];
    for (const file of files) {
      const source = readFileSync(file, 'utf8');
      // Only sections whose own leading content is an h2. Sections that open
      // with an h1 (PermissionState) or with no heading are out of scope.
      const re = /<section\b([^>]*)>((?:(?!<section\b)[\s\S])*?)<h2\b/g;
      for (const m of source.matchAll(re)) {
        if (!/\baria-labelledby\s*=/.test(m[1])) unnamed.push(`${file}: ${(m[2] ?? '').slice(-40)}`);
      }
    }
    expect(unnamed).toEqual([]);
  });
});
