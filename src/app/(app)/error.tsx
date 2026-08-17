'use client';

import Link from 'next/link';

/**
 * App-level error boundary for the authenticated shell. Any unhandled server
 * or render error inside (app) shows this Arabic recoverable state instead of
 * the default English Next.js error page. Error details stay out of the UI;
 * Next.js server logs still capture them.
 */
export default function AppError({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <section className="card stack" role="alert">
      <h1>حدث خطأ غير متوقع</h1>
      <p className="muted">
        تعذر عرض هذه الصفحة حاليًا. يمكنك إعادة المحاولة أو العودة إلى اللوحة الرئيسية؛ بياناتك المسجلة لم تتأثر.
      </p>
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        <button onClick={reset}>إعادة المحاولة</button>
        <Link className="button secondary" href="/">العودة إلى اللوحة الرئيسية</Link>
      </div>
    </section>
  );
}
