import Image from 'next/image';
import type { ReactNode } from 'react';

/**
 * Auth / system-state shell (template T5, dark reference build).
 *
 * A single centred column on deep navy: the full brand lockup (mark +
 * wordmark + tagline, `public/logo-full.png`) crowns a hairline-bordered
 * card that carries the one task of the screen — heading, fields, action.
 * No side panel, no chips, no claims: the reference design keeps the
 * sign-in surface a quiet, single-purpose moment, so the identity is the
 * logo and nothing else.
 *
 * The card sits on the page background with only a 1px outline, the exact
 * anatomy of the approved reference (outlined panel, dark inset fields,
 * one full-width accent action). The page closes with the product
 * attribution — «إحدى منتجات Lena Digital» — linking to the Lena Digital
 * platform, pinned under the card as the last line of the page.
 */
export function AuthShell({ children }: { children: ReactNode }) {
  return (
    <main className="auth-layout">
      <section className="auth-card">
        <Image
          src="/logo-full.png"
          alt="تيرانكس"
          width={140}
          height={144}
          priority
          className="auth-lockup"
        />
        {children}
      </section>
      <footer className="auth-footer">
        إحدى منتجات{' '}
        <a href="https://lenadigital.vercel.app/en" target="_blank" rel="noopener noreferrer">
          Lena Digital
        </a>
      </footer>
    </main>
  );
}
