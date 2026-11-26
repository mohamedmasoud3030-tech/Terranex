'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const ICONS: Record<string, string> = {
  home: 'M2.5 7.5 8 2.5l5.5 5v6h-3.8V9.6H6.3v3.9H2.5z',
  projects: 'M2 5.2h12v8.3H2zM5.5 5.2V3h5v2.2M2 8.6h12',
  portfolios: 'M2 4.5 8 2l6 2.5-6 2.5zM2 8l6 2.5L14 8M2 11.2 8 13.7l6-2.5',
  assets: 'M3 13.5V6.2L8 2.5l5 3.7v7.3M6.2 13.5V9h3.6v4.5',
  intake: 'M8 2.5v11M2.5 8h11',
};

const LINKS: ReadonlyArray<{ href: string; label: string; icon: keyof typeof ICONS; match: (p: string) => boolean }> = [
  { href: '/', label: 'لوحة الإدارة', icon: 'home', match: (p) => p === '/' },
  { href: '/projects', label: 'المشاريع', icon: 'projects', match: (p) => p.startsWith('/projects') },
  { href: '/portfolios', label: 'المحافظ', icon: 'portfolios', match: (p) => p.startsWith('/portfolios') },
  { href: '/assets', label: 'الأصول والأداء', icon: 'assets', match: (p) => p.startsWith('/assets') },
  { href: '/intake', label: 'إدخال مشروع', icon: 'intake', match: (p) => p.startsWith('/intake') },
];

export function SideNav() {
  const pathname = usePathname() ?? '/';
  return (
    <nav className="side-nav" aria-label="التنقل الرئيسي">
      {LINKS.map((link) => (
        <Link key={link.href} href={link.href} aria-current={link.match(pathname) ? 'page' : undefined}>
          <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d={ICONS[link.icon]} />
          </svg>
          <span>{link.label}</span>
        </Link>
      ))}
    </nav>
  );
}
