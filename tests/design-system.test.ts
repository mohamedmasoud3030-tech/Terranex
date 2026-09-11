import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const css = readFileSync('src/app/globals.css', 'utf8');

/**
 * The `:root { … }` token block — the only place a literal colour may live.
 * Extracted by brace matching, not by the first `}`, because the block is long.
 */
function extractTokenBlock(source: string): string {
  const start = source.indexOf(':root {');
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
const outsideTokens = css.replace(tokenBlock, '');

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
