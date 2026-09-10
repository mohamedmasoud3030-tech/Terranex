'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { ReactNode } from 'react';

/**
 * Primary navigation with current-route awareness. The desktop strip shows
 * the links inline; below 720px the same links plus the organization
 * switcher and sign-out live behind a native `<details>` "المزيد" control so
 * the header never consumes more than one row of a phone viewport.
 */
export const PRIMARY_LINKS: ReadonlyArray<{ href: string; label: string; match: (path: string) => boolean }> = [
  { href: '/', label: 'الرئيسية', match: (p) => p === '/' },
  { href: '/projects', label: 'المشاريع', match: (p) => p.startsWith('/projects') },
  { href: '/portfolios', label: 'المحافظ', match: (p) => p.startsWith('/portfolios') },
  { href: '/assets', label: 'الأصول', match: (p) => p.startsWith('/assets') },
];

export function AppNav({ tools }: { tools: ReactNode }) {
  const pathname = usePathname() ?? '/';
  const links = PRIMARY_LINKS.map((link) => (
    <Link key={link.href} href={link.href} aria-current={link.match(pathname) ? 'page' : undefined}>
      {link.label}
    </Link>
  ));
  return (
    <>
      <nav className="app-nav app-nav-desktop" aria-label="التنقل الرئيسي">
        {links}
      </nav>
      <div className="app-tools app-nav-desktop">{tools}</div>
      <details className="app-more app-nav-mobile">
        <summary aria-label="فتح القائمة">القائمة</summary>
        <div className="app-more-panel">
          <nav className="app-nav" aria-label="التنقل الرئيسي (جوال)" style={{ display: 'grid' }}>
            {links}
          </nav>
          {tools}
        </div>
      </details>
    </>
  );
}
