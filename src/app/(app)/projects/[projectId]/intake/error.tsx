'use client';

export default function IntakeError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <section className="card stack" role="alert">
      <h1>تعذر تحميل مسار الإدخال</h1>
      <p className="error">لم نعرض أرقامًا أو حالات قديمة بدلًا من البيانات الحالية. تحقق من الاتصال والصلاحية ثم أعد المحاولة.</p>
      <button onClick={() => reset()}>إعادة المحاولة</button>
    </section>
  );
}
