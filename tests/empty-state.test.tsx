// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { EmptyState } from '@/shared/ui';

/**
 * Empty states.
 *
 * Two invariants, both of which had already been violated once:
 *
 * 1. An empty state inside a section must not add a second `<h2>` at the same
 *    level. Agriculture had a mix of `<h3>` and `<h4>` empty-state headings
 *    under one `<h2>`, so a screen reader's heading list read a subsection as
 *    its own sibling. `headingLevel` exists for this.
 * 2. Pages must not hand-roll the card/heading/paragraph shape again — that is
 *    how the mix in (1) happened in the first place.
 */
describe('EmptyState', () => {
  afterEach(() => cleanup());

  it('renders an h2 by default, for a page-level empty state', () => {
    render(<EmptyState title="لا توجد مشاريع" />);
    expect(screen.getByRole('heading', { level: 2, name: 'لا توجد مشاريع' })).toBeDefined();
  });

  it('renders an h3 when asked, so it can sit inside a section', () => {
    render(<EmptyState headingLevel={3} title="لا توجد مزارع بعد" />);
    expect(screen.getByRole('heading', { level: 3, name: 'لا توجد مزارع بعد' })).toBeDefined();
  });

  it('renders its action, and omits the action wrapper when there is none', () => {
    const { rerender, container } = render(
      <EmptyState headingLevel={3} title="t" action={<button>أضف</button>} />,
    );
    expect(screen.getByRole('button', { name: 'أضف' })).toBeDefined();
    expect(container.querySelector('.page-actions')).not.toBeNull();
    rerender(<EmptyState headingLevel={3} title="t" />);
    expect(container.querySelector('.page-actions')).toBeNull();
  });

  it('renders no heading at all in compact mode', () => {
    // Compact sits inside an already-headed card; a heading there would be a
    // second one for the same section.
    const { container } = render(<EmptyState compact title="لا توجد تكاليف" />);
    expect(container.querySelector('h2, h3')).toBeNull();
    expect(container.querySelector('.empty-inline')).not.toBeNull();
  });
});

describe('card-level empty states go through the primitive', () => {
  const files = execSync("find src/app -name '*.tsx'", { encoding: 'utf8' })
    .trim()
    .split('\n')
    .filter(Boolean);

  /**
   * Two distinct forms exist on purpose and only one of them is the
   * primitive's job:
   *
   * - A card-level empty state (`card empty`) owns a heading and often an
   *   action. It must be `<EmptyState>` — hand-rolling it is how agriculture
   *   ended up with `<h3>` and `<h4>` headings at the same level.
   * - `<p className="empty">` is a centred one-line note inside a section
   *   that simply has no rows. `.empty` centres it; `EmptyState compact`
   *   would start-align it and bold the sentence, which is worse for a
   *   "nothing here" note. That form is allowed to stay hand-written.
   *
   * The card-level match is order-insensitive on purpose: two agriculture
   * states written `className="card empty stack"` escaped the original
   * `card(?: stack)? empty` pattern purely by class order and survived a
   * full pass. A guard that depends on token order is not a guard.
   */
  it('no page hand-rolls the card-level form', () => {
    const offenders: string[] = [];
    for (const file of files) {
      const source = readFileSync(file, 'utf8');
      for (const m of source.matchAll(/className="card[^"]*\bempty\b[^"]*"/g)) {
        offenders.push(`${file}: ${m[0]}`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('the only hand-rolled form left is the inline note', () => {
    const notes: string[] = [];
    for (const file of files) {
      const source = readFileSync(file, 'utf8');
      notes.push(
        ...[...source.matchAll(/<(\w+) className="[^"]*\bempty\b[^"]*"/g)].map((m) => m[1]),
      );
    }
    // Every remaining one is a <p>; a <div> or <section> here would mean the
    // card-level form creeping back in.
    expect(notes.length).toBeGreaterThan(0);
    expect(new Set(notes)).toEqual(new Set(['p']));
  });
});
