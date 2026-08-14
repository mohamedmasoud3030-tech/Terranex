'use client';

import Link from 'next/link';

export default function LivestockError({
  reset,
}: Readonly<{
  error: Error & { digest?: string };
  reset: () => void;
}>) {
  return (
    <section className="card stack">
      <h1>تعذر تحميل مساحة الثروة الحيوانية</h1>
      <p className="error" role="alert">
        حدث خطأ أثناء قراءة بيانات المواقع والقطعان والدفعات. تحقق من الاتصال وأعد المحاولة.
      </p>
      <div className="stack" style={{ flexDirection: 'row' }}>
        <button onClick={reset} className="button">إعادة المحاولة</button>
        <Link className="button secondary" href="/">العودة إلى المشاريع</Link>
      </div>
    </section>
  );
}
