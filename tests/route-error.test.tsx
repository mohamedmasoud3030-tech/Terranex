// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { RouteError } from '@/shared/ui/route-error';

/**
 * The shared route-error body.
 *
 * Twenty-eight `error.tsx` files now render this one component instead of
 * hand-rolling markup, so a regression here is a regression on every route at
 * once. That concentration is the point of the shared body and also the reason
 * it needs a behavioural test rather than a grep: the thing that matters is
 * what an operator is shown when a route throws, not which file contains the
 * string.
 */

const errorFiles = execSync("find src/app -name 'error.tsx'", { encoding: 'utf8' })
  .trim()
  .split('\n')
  .filter(Boolean);

describe('RouteError', () => {
  afterEach(() => cleanup());

  it('announces itself as an alert and names the surface that failed', () => {
    render(
      <RouteError
        surface="مساحة الإغلاق المالي"
        detail="حدث خطأ أثناء قراءة الفترات."
        reset={() => {}}
        backHref="/projects"
        backLabel="العودة إلى المشاريع"
      />,
    );
    expect(screen.getByRole('alert')).toBeDefined();
    expect(
      screen.getByRole('heading', { name: 'تعذر تحميل مساحة الإغلاق المالي' }),
    ).toBeDefined();
  });

  it('retries through the reset callback', () => {
    const reset = vi.fn();
    render(
      <RouteError
        surface="سجل المشاريع"
        detail="حدث خطأ."
        reset={reset}
        backHref="/"
        backLabel="العودة إلى اللوحة الرئيسية"
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'إعادة المحاولة' }));
    expect(reset).toHaveBeenCalledTimes(1);
  });

  it('offers a way back, and says plainly that no stale figures were shown', () => {
    render(
      <RouteError
        surface="مساحة الإيراد"
        detail="حدث خطأ."
        reset={() => {}}
        backHref="/projects"
        backLabel="العودة إلى المشاريع"
      />,
    );
    expect(screen.getByRole('link', { name: 'العودة إلى المشاريع' })).toBeDefined();
    // The product's standing rule: on failure, show nothing rather than show
    // something that looks current but is not.
    expect(document.body.textContent).toContain('لم تُعرض أرقام أو حالات قديمة');
  });

  it('takes no Error object, so a stack trace cannot reach the operator', () => {
    // The props are surface/detail/reset/backHref/backLabel. There is
    // deliberately no `error` prop to forward — Next.js still logs it
    // server-side, and a caller cannot pass one by accident.
    const source = readFileSync('src/shared/ui/route-error.tsx', 'utf8');
    const props = source.match(/export function RouteError\(\{([\s\S]*?)\}\s*:/)?.[1] ?? '';
    expect(props).toContain('surface');
    expect(props).toContain('reset');
    expect(props).not.toMatch(/\berror\b/);
  });
});

describe('route error boundary coverage', () => {
  it('every workspace route with a page has a boundary', () => {
    const pages = execSync("find 'src/app/(app)' -name 'page.tsx'", { encoding: 'utf8' })
      .trim()
      .split('\n');
    const missing = pages
      .map((file) => file.replace(/\/page\.tsx$/, ''))
      .filter((dir) => !errorFiles.includes(`${dir}/error.tsx`));
    // /statements only redirects, so a boundary there could never render.
    expect(missing).toEqual(['src/app/(app)/projects/[projectId]/statements']);
  });

  it('all of them share one body instead of duplicating markup', () => {
    const shell = 'src/app/(app)/error.tsx';
    const shared = errorFiles.filter((f) => f !== shell);
    expect(shared.length).toBeGreaterThanOrEqual(28);
    for (const file of shared) {
      const source = readFileSync(file, 'utf8');
      expect(source, file).toContain("from '@/shared/ui/route-error'");
      // No boundary should still hand-roll the card/heading/button markup.
      expect(source, file).not.toContain('className="card stack"');
    }
  });
});
