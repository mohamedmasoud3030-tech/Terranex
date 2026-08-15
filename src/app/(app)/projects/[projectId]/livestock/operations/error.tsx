'use client';

export default function LivestockOperationsError({ reset }: Readonly<{ reset: () => void }>) {
  return <section className="card stack" dir="rtl" role="alert">
    <h1>تعذر تحميل العمليات الحيوانية</h1>
    <p>لم تُعرض بيانات جزئية على أنها مكتملة. تحقق من الاتصال والصلاحيات ثم أعد المحاولة.</p>
    <button type="button" onClick={reset}>إعادة المحاولة</button>
  </section>;
}
