import Image from 'next/image';
import type { ReactNode } from 'react';
import { SECTOR_AR, SECTOR_KEYS, SECTOR_TONE_CLASS } from '@/features/workspace/sectors';
import { SectorGlyph } from './sector';

/**
 * Auth / system-state shell (template T5).
 *
 * Two zones, RTL-ordered: the product identity on the leading (right) side,
 * the single task on the trailing side. The identity zone states what the
 * product is and which three verticals it operates — nothing else. No
 * testimonials, no counters, no marketing claims: this is the sign-in screen
 * of a financial system, and an unearned claim here is the fastest way to
 * lose the trust the rest of the interface is built to earn.
 *
 * The owner's real brand mark (gold on transparency, `public/logo.png`)
 * crowns both zones: beside the wordmark on the dark panel and at the head
 * of the task card. It is decorative in both places — the adjacent text
 * carries the name, so the mark stays `alt=""`.
 *
 * The page closes with the product attribution: «إحدى منتجات Lena Digital»,
 * linking to the Lena Digital platform. It sits under the card on every
 * auth surface, on brand-coloured text, as the last line of the page.
 */
export function AuthShell({ children }: { children: ReactNode }) {
  return (
    <main className="auth-layout">
      <aside className="auth-aside" aria-hidden="false">
        <div className="auth-aside-inner">
          <span className="auth-brand">
            <Image
              src="/logo.png"
              alt=""
              width={46}
              height={45}
              priority
              className="auth-logo"
            />
            تيرانكس
          </span>
          <p className="auth-tagline">نظام تشغيل الاستثمار</p>
          <p className="auth-aside-copy">
            مساحة تشغيل واحدة لإدارة الاستثمار في أصول حقيقية: دورة المشروع،
            الأدلة، والدفتر المالي — من الالتزام حتى الإغلاق.
          </p>
          <ul className="auth-verticals" aria-label="القطاعات التي يغطيها النظام">
            {SECTOR_KEYS.map((sector) => (
              <li key={sector} className={`sector-chip ${SECTOR_TONE_CLASS[sector]}`}>
                <SectorGlyph sector={sector} />
                {SECTOR_AR[sector]}
              </li>
            ))}
          </ul>
        </div>
      </aside>

      <div className="auth-main">
        <div className="auth-main-inner">
          <section className="card stack auth-card">
            <span className="auth-card-brand" aria-hidden="true">
              <Image src="/logo.png" alt="" width={40} height={39} className="auth-logo-sm" />
            </span>
            {children}
          </section>
          <footer className="auth-footer">
            إحدى منتجات{' '}
            <a href="https://lenadigital.vercel.app/en" target="_blank" rel="noopener noreferrer">
              Lena Digital
            </a>
          </footer>
        </div>
      </div>
    </main>
  );
}
