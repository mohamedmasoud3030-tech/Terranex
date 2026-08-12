'use client';

type PilotErrorProps = Readonly<{
  error: Error & { digest?: string };
  reset: () => void;
}>;

export default function PilotError({ reset }: PilotErrorProps) {
  return (
    <section className="card stack" role="alert">
      <h1>تعذر تحميل لوحة التشغيل التجريبي</h1>
      <p className="error">
        لم نعرض مجاميع رقابة أو فروق مطابقة قديمة بدلًا من البيانات الحالية. تحقق من الاتصال والصلاحية ثم أعد المحاولة.
      </p>
      <button type="button" onClick={reset}>
        إعادة المحاولة
      </button>
    </section>
  );
}
