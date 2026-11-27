// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest';
import { act, cleanup, render, screen } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { FocusHero } from '@/features/mobile-focus/focus-hero';
import { MobileFold } from '@/features/mobile-focus/mobile-fold';
import { JARGON_BLOCKLIST } from '@/features/plain-language/copy';

/**
 * The mobile design pass contract (Stream A follow-up).
 *
 * On the phone, the app behaves like a simple records app: one focus per
 * screen — a calm hero with three numbers and one clear action — and heavy
 * detail opens on demand (MobileFold). Nothing is removed: the same content
 * renders expanded on larger screens. These tests guard that split and keep
 * the hero's copy in the plain register.
 */

const homeSource = readFileSync('src/app/(app)/page.tsx', 'utf8');
const intakeSource = readFileSync('src/app/(app)/projects/[projectId]/intake/page.tsx', 'utf8');
const cssSource = readFileSync('src/app/globals.css', 'utf8');

function mockMatchMedia(matches: boolean) {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: (query: string) => ({
      matches,
      media: query,
      addEventListener: () => {},
      removeEventListener: () => {},
    }),
  });
}

afterEach(cleanup);

describe('FocusHero', () => {
  it('shows three numbers and exactly one action', () => {
    render(
      <FocusHero
        orgName="شركة النيل"
        numbers={[
          { label: 'مشاريع', value: 2 },
          { label: 'أصول مسجلة', value: 5 },
          { label: 'النقدية', value: '١٢٬٠٠٠ ج.م' },
        ]}
        action={{ href: '/intake', label: 'ابدأ إدخال أول مشروع' }}
      />,
    );
    expect(screen.getByText('شركة النيل')).toBeTruthy();
    expect(screen.getByText('مشاريع')).toBeTruthy();
    expect(screen.getByText('أصول مسجلة')).toBeTruthy();
    expect(screen.getByText('النقدية')).toBeTruthy();
    const links = screen.getAllByRole('link');
    expect(links).toHaveLength(1);
    expect(links[0].getAttribute('href')).toBe('/intake');
  });

  it('keeps the hero copy free of accounting jargon', () => {
    const heroCopy = ['مشاريع', 'أصول مسجلة', 'النقدية', 'ابدأ إدخال أول مشروع', 'افتح مشروعك', 'ملخص سريع'];
    for (const phrase of heroCopy) {
      for (const jargon of JARGON_BLOCKLIST) {
        expect(phrase.includes(jargon), `"${phrase}" must not contain "${jargon}"`).toBe(false);
      }
    }
  });
});

describe('MobileFold', () => {
  it('renders the expanded section on large screens (server/first render)', () => {
    mockMatchMedia(false);
    render(
      <MobileFold title="تفاصيل" description="وصف">
        <p>المحتوى الكامل</p>
      </MobileFold>,
    );
    expect(document.querySelector('details')).toBeNull();
    expect(screen.getByText('المحتوى الكامل')).toBeTruthy();
    expect(screen.getByRole('heading', { name: 'تفاصيل' })).toBeTruthy();
  });

  it('collapses into an on-demand disclosure after hydration on small screens', async () => {
    mockMatchMedia(true);
    render(
      <MobileFold title="تفاصيل" description="وصف">
        <p>المحتوى الكامل</p>
      </MobileFold>,
    );
    // First paint matches the server render (expanded), then the effect
    // swaps to the collapsed disclosure.
    await act(async () => {});
    const details = document.querySelector('details.m-fold');
    expect(details).not.toBeNull();
    expect(details?.hasAttribute('open')).toBe(false);
    expect(screen.getByText('تفاصيل')).toBeTruthy();
  });
});

describe('mobile design pass wiring', () => {
  it('puts the focus hero at the top of the home dashboard', () => {
    expect(homeSource).toContain('FocusHero');
    expect(homeSource.indexOf('FocusHero')).toBeLessThan(homeSource.indexOf('PageHeader'));
    expect(homeSource).toContain('لوحة الإدارة التنفيذية');
  });

  it('opens the dense home sections on demand on the phone', () => {
    for (const title of ['الموقف المالي على مستوى المنظمة', 'القطاعات في لمحة', 'أداء القطاعات', 'المشاريع الاستثمارية']) {
      expect(homeSource).toContain(title);
    }
    const foldCount = (homeSource.match(/<MobileFold/g) ?? []).length;
    expect(foldCount).toBeGreaterThanOrEqual(4);
  });

  it('keeps the attention-first integrity section expanded', () => {
    expect(homeSource).toContain('يحتاج انتباهك — إشارات السلامة والاستثناءات');
    const attention = homeSource.indexOf('يحتاج انتباهك');
    const nearestSection = homeSource.lastIndexOf('<Section', attention);
    const nearestFold = homeSource.lastIndexOf('<MobileFold', attention);
    expect(nearestSection).toBeGreaterThan(nearestFold);
  });

  it('folds finished intake cards on the phone and keeps unfinished ones open', () => {
    expect(intakeSource).toContain('MobileFold');
    expect(intakeSource).toContain("item.status === 'COMPLETE'");
    expect(intakeSource).toContain('intake-fold-title');
  });

  it('ships the phone styles inside the design system tokens', () => {
    expect(cssSource).toContain('.focus-hero');
    expect(cssSource).toContain('.m-fold > summary');
    expect(cssSource).toContain('@media (max-width: 960px)');
  });
});
