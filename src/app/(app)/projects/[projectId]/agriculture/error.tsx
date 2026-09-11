'use client';
import Link from 'next/link';

export default function AgricultureError({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <section className="card stack">
      <h1>تعذر تحميل مساحة الزراعة</h1>
      <p className="error" role="alert">
        حدث خطأ أثناء قراءة بيانات الزراعة. أعد المحاولة بعد التحقق من اتصال الدخول.
      </p>
      <div className="row-wrap">
        <button onClick={reset} className="button">إعادة المحاولة</button>
        <Link className="button secondary" href="/">العودة إلى المشاريع</Link>
      </div>
    </section>
  );
}
