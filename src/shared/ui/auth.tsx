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
 */
export function AuthShell({ children }: { children: ReactNode }) {
  return (
    <main className="auth-layout">
      <aside className="auth-aside" aria-hidden="false">
        <div className="auth-aside-inner">
          <span className="auth-brand">
            <svg width="30" height="30" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M2.2 12.6 8 2.6l5.8 10M2.2 12.6h11.6M4.4 12.6 8 6.4l3.6 6.2" />
            </svg>
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
        <section className="card stack auth-card">{children}</section>
      </div>
    </main>
  );
}
