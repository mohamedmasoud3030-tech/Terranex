import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { describe, expect, it } from 'vitest';

/**
 * In-page navigation contract.
 *
 * `InPageTabs` renders anchor links into a sticky strip. An anchor that points
 * at an id the page does not render is a link that does nothing when clicked —
 * invisible in review, obvious to the operator, and impossible to notice from
 * the markup alone. This test parses each page's tab hrefs and its `id`
 * attributes and fails on any href with no target.
 *
 * The reverse direction is deliberately NOT asserted: a page may legitimately
 * contain sub-anchors (a drill-down target inside a tabbed parent) that are
 * reached from body copy rather than from the strip.
 */

const files = execSync("find 'src/app' -name 'page.tsx'", { encoding: 'utf8' })
  .trim()
  .split('\n')
  .filter(Boolean);

function pageAnchorReport(file: string) {
  const source = readFileSync(file, 'utf8');
  const tabs = [...source.matchAll(/\{\s*href:\s*'#([\w-]+)'\s*,\s*label:\s*'([^']+)'\s*\}/g)].map(
    (match) => ({ href: match[1], label: match[2] }),
  );
  const ids = new Set([...source.matchAll(/\bid="([\w-]+)"/g)].map((match) => match[1]));
  const dead = tabs.filter((tab) => !ids.has(tab.href));
  return { tabs, ids, dead };
}

describe('in-page navigation anchors', () => {
  const withTabs = files.filter((file) => pageAnchorReport(file).tabs.length > 0);

  it('finds pages that use in-page navigation', () => {
    // Guards against this test silently passing because the parse broke.
    expect(withTabs.length).toBeGreaterThanOrEqual(4);
  });

  it.each(withTabs.map((file) => [file.replace(/^src\/app\/\(app\)\//, ''), file]))(
    '%s: every tab points at a section the page renders',
    (_label, file) => {
      const { dead } = pageAnchorReport(file as string);
      expect(dead).toEqual([]);
    },
  );

  it('keeps the livestock strip in step with the sections on the page', () => {
    const { tabs, ids } = pageAnchorReport(
      'src/app/(app)/projects/[projectId]/livestock/page.tsx',
    );
    // Every top-level section heading on the page must be reachable. These
    // four were previously rendered below the strip with no link to them.
    for (const required of ['setup', 'location', 'count-flow', 'lineage']) {
      expect(ids.has(required)).toBe(true);
      expect(tabs.some((tab) => tab.href === required)).toBe(true);
    }
  });

  it('offers the rental tab only where the rental section renders', () => {
    const source = readFileSync('src/app/(app)/projects/[projectId]/revenue/page.tsx', 'utf8');
    // The section is gated on the real-estate sector; the tab must be gated
    // on the same condition, or it dead-links for other sectors.
    expect(source).toMatch(/project\.sector === 'REAL_ESTATE'[\s\S]{0,120}#rentals/);
    expect(source).toMatch(/<section id="rentals"/);
  });
});
