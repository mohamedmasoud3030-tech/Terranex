import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const css = readFileSync('src/app/globals.css', 'utf8');

/**
 * The `:root { … }` token block — the only place a literal colour may live.
 * Extracted by brace matching, not by the first `}`, because the block is long.
 */
function extractTokenBlock(source: string, marker = ':root {'): string {
  const start = source.indexOf(marker);
  if (start === -1) return '';
  let depth = 0;
  for (let i = source.indexOf('{', start); i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    else if (source[i] === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(start, i + 1);
    }
  }
  return '';
}

const tokenBlock = extractTokenBlock(css);
// The dark theme is the same tokens re-valued, so it is a token block too.
const darkTokenBlock = extractTokenBlock(css, ':root[data-theme="dark"] {');
const outsideTokens = css.replace(tokenBlock, '').replace(darkTokenBlock, '');

describe('design system tokens', () => {
  it('keeps every literal colour inside the :root token block', () => {
    // rgb()/rgba()/hsl() are allowed outside the block only for elevation,
    // where a translucent shadow has no token and must not be themed.
    const literals = [...outsideTokens.matchAll(/#[0-9a-fA-F]{3,8}\b/g)].map((m) => m[0]);
    expect(literals).toEqual([]);
  });

  it('defines the sector accents for all three verticals', () => {
    for (const sector of ['real-estate', 'agriculture', 'livestock']) {
      for (const suffix of ['', '-ink', '-wash', '-edge']) {
        expect(tokenBlock).toContain(`--sector-${sector}${suffix}:`);
      }
      expect(css).toContain(`.sector-theme-${sector}`);
      expect(css).toContain(`.sector-${sector}`);
    }
  });

  it('keeps the five semantic status tones', () => {
    for (const tone of ['neutral', 'success', 'warning', 'danger', 'info']) {
      expect(css).toContain(`.badge-${tone}`);
    }
  });

  it('never communicates state by colour alone', () => {
    // The status pill draws a glyph from ::before, and the two "unsettled"
    // shapes are opt-in modifiers, so a greyscale or screen-reader user can
    // still tell an open state from a settled one.
    expect(css).toMatch(/\.status::before\s*\{[^}]*content:\s*""/);
    expect(css).toContain('.status.tone-open::before');
    expect(css).toContain('.status.tone-void::before');
  });

  it('uses tabular figures wherever numbers are compared', () => {
    expect(css).toContain('--tnum');
    for (const selector of ['td.num', '.stat-value', '.overview-kpi strong', '.facts dd']) {
      expect(css).toContain(selector);
    }
  });

  it('supports reduced motion, forced colours, and print', () => {
    expect(css).toContain('@media (prefers-reduced-motion: reduce)');
    expect(css).toContain('@media (forced-colors: active)');
    expect(css).toContain('@media print');
  });

  it('has a visible focus ring that is not the brand colour', () => {
    expect(css).toContain('--focus:');
    expect(css).toContain(':focus-visible');
    // The focus token must differ from the brand token, or a focused control
    // is indistinguishable from a selected one.
    const focus = tokenBlock.match(/--focus:\s*(#[0-9a-fA-F]{3,8})/)?.[1];
    const brand = tokenBlock.match(/--brand:\s*(#[0-9a-fA-F]{3,8})/)?.[1];
    expect(focus).toBeTruthy();
    expect(focus).not.toBe(brand);
  });

  it('writes RTL-structurally — no physical inline direction', () => {
    // Left/right in a stylesheet that must render right-to-left is a bug.
    // (Excludes the print rule, which only hides chrome.)
    const body = css.replace(/@media print \{[\s\S]*?\n\}/, '');
    expect(body).not.toMatch(/(^|[^-\w])(margin|padding|border|inset)-(left|right)\s*:/);
    expect(body).not.toMatch(/(^|[^-\w])(left|right)\s*:(?!.*auto)/m);
  });
});

describe('class-name contract', () => {
  /**
   * Every class the pre-upgrade stylesheet defined must still be defined. The
   * upgrade was required to be additive: pages that were not migrated must
   * keep rendering exactly as before.
   */
  const LEGACY_CLASSES = [
    'shell', 'top', 'brand', 'card', 'grid', 'stack', 'muted', 'error',
    'project', 'status', 'table-wrap', 'project-context', 'context-nav',
    'section-heading', 'topline', 'asset-grid', 'metric-grid', 'facts',
    'form-grid', 'inline-form', 'metric', 'result-highlight', 'empty',
    'milestones', 'milestone', 'timeline-row', 'timeline', 'scroll-target',
    'panel-grid', 'panel', 'gate', 'gate-dot', 'banner', 'role-badge',
    'skeleton', 'workspace-nav', 'workspace-nav-item', 'overview-kpis',
    'overview-kpi', 'org-switcher', 'status-draft', 'status-active',
    'status-archived', 'intake-badge-complete', 'intake-badge-missing',
    'intake-badge-failed', 'intake-badge-blocked', 'intake-badge-in_progress',
    'intake-badge-conditional_open', 'intake-badge-not_applicable',
    'sr-only', 'skip-link', 'app-topbar', 'app-nav', 'app-tools', 'app-more',
    'app-more-panel', 'app-nav-mobile', 'page-header', 'page-header-main',
    'page-title-row', 'page-description', 'page-actions', 'back-link',
    'eyebrow', 'section-actions', 'section-collapsible', 'section-body',
    'stat-grid', 'stat', 'stat-label', 'stat-value', 'stat-hint', 'stat-link',
    'stat-negative', 'stat-positive', 'tab-strip', 'tab-strip-secondary',
    'tab-strip-inpage', 'empty-inline', 'form-actions-wrap', 'form-actions',
    'form-note', 'field', 'field-hint', 'field-error', 'row-actions',
    'row-actions-panel', 'row-actions-row', 'skeleton-title', 'skeleton-nav',
    'skeleton-block', 'card-list', 'badge-row', 'clamp-1', 'link-list',
    'stepper', 'step-index', 'table-stackable', 'full', 'compact', 'cancel',
    'secondary', 'ghost', 'danger', 'sm', 'info', 'warning', 'negative',
    'positive', 'wide',
  ];

  it.each(LEGACY_CLASSES)('still defines .%s', (name) => {
    // Word-boundary match: `.positive` must not be satisfied by `.stat-positive`.
    expect(css).toMatch(new RegExp(`\\.${name}(?![\\w-])`));
  });

  it('defines the classes that pages use but nothing previously styled', () => {
    for (const name of [
      'metrics-grid',
      'responsive-grid',
      'section-summary-title',
      'field-label',
    ]) {
      expect(css).toContain(`.${name}`);
    }
  });
});

/* -------------------------------------------------------------------------- */
/* Contrast                                                                   */
/* -------------------------------------------------------------------------- */

/**
 * WCAG 2.2 AA contrast, measured from the tokens rather than eyeballed.
 *
 * Only tokens that carry *text* are asserted: a border or hover outline is a
 * non-text element and needs 3:1, not 4.5:1. Each foreground is checked
 * against every background its CSS rules can actually place it on — checking
 * a token against white alone is how `--muted-2` shipped at 3.77:1 while
 * sitting on `--neutral-wash`.
 */
function channel(value: number): number {
  const c = value / 255;
  return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
}

function luminance(hex: string): number {
  const h = hex.replace('#', '');
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

function contrastRatio(a: string, b: string): number {
  const la = luminance(a);
  const lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

const TOKEN: Record<string, string> = Object.fromEntries(
  [...tokenBlock.matchAll(/(--[\w-]+):\s*(#[0-9a-fA-F]{6})/g)].map((m) => [m[1], m[2]]),
);

const TEXT_TOKENS: [string, string[]][] = [
  ['--muted', ['--surface', '--surface-sunken']],
  // Sits on the archived badge wash and on `--paper-2`, not only on white.
  ['--muted-2', ['--surface', '--surface-sunken', '--paper-2', '--neutral-wash']],
  ['--ink', ['--surface', '--surface-sunken']],
  ['--ink-2', ['--surface', '--surface-sunken']],
  ['--brand', ['--surface', '--brand-soft', '--brand-softer']],
  ['--brand-ink', ['--surface', '--brand-soft', '--brand-softer']],
  ['--success-ink', ['--success-wash']],
  ['--warning-ink', ['--warning-wash']],
  ['--danger-ink', ['--danger-wash']],
  ['--info-ink', ['--info-wash']],
];

describe('text contrast (WCAG 2.2 AA)', () => {
  it('resolves every token it asserts on', () => {
    for (const [fg, bgs] of TEXT_TOKENS) {
      expect(TOKEN[fg], `${fg} is not a hex token`).toBeTruthy();
      for (const bg of bgs) expect(TOKEN[bg], `${bg} is not a hex token`).toBeTruthy();
    }
  });

  it.each(TEXT_TOKENS)('%s clears 4.5:1 on every background it is used on', (fg, bgs) => {
    for (const bg of bgs) {
      const ratio = contrastRatio(TOKEN[fg], TOKEN[bg]);
      expect(ratio, `${fg} on ${bg}`).toBeGreaterThanOrEqual(4.5);
    }
  });

  it('keeps the muted scale distinguishable from body ink', () => {
    // If --muted-2 is darkened to pass contrast it must not collapse onto
    // --muted, or the type scale loses a step.
    expect(TOKEN['--muted-2']).not.toBe(TOKEN['--muted']);
    expect(TOKEN['--muted']).not.toBe(TOKEN['--ink-2']);
  });
});

/* -------------------------------------------------------------------------- */
/* Gallery fidelity                                                           */
/* -------------------------------------------------------------------------- */

/**
 * `docs/design/design-system.html` is generated by scripts/build-design-gallery.mjs,
 * which inlines globals.css and supplies its own layout styles. A demo that
 * references a class the stylesheet does not define renders unstyled — it looks
 * like a deliberate design, so the gap is invisible in review. Every class the
 * gallery markup uses must exist in globals.css or in the gallery's own block.
 *
 * Regenerate with `node scripts/build-design-gallery.mjs` after changing either.
 */
describe('design gallery references only real classes', () => {
  const gallery = readFileSync('docs/design/design-system.html', 'utf8');
  const galleryStyle = gallery.match(/<style>([\s\S]*?)<\/style>/)?.[1] ?? '';
  const defined = new Set([
    ...css.matchAll(/\.([A-Za-z][\w-]*)/g),
    ...galleryStyle.matchAll(/\.([A-Za-z][\w-]*)/g),
  ].map((m) => m[1]));

  // Empty tokens are filtered: `class="a b "` splits to a trailing '' that is
  // not a class name. The generator is kept free of them regardless.
  const used = new Set(
    [...gallery.matchAll(/class="([^"]+)"/g)]
      .flatMap((m) => m[1].split(/\s+/))
      .filter(Boolean),
  );

  it('is non-trivial (the gallery really has markup and styles)', () => {
    expect(used.size).toBeGreaterThan(50);
    expect(galleryStyle.length).toBeGreaterThan(200);
  });

  it('uses no class that is not styled', () => {
    const missing = [...used].filter((name) => !defined.has(name)).sort();
    expect(missing).toEqual([]);
  });

  it('does not demonstrate components that were removed from the system', () => {
    // `ConfirmPanel` was exported but never used by a page; advertising it in
    // the spec made an unbuilt pattern look shipped.
    expect(gallery).not.toContain('confirm-panel');
    expect(css).not.toContain('.confirm-panel');
  });
});
