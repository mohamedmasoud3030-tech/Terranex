'use client';

export default function ProjectError({ reset }: { reset: () => void }) {
  return (
    <section className="card stack">
      <h1>تعذر عرض مساحة المشروع</h1>
      <p className="muted">حدث خطأ أثناء تحميل بيانات المشروع. لم تُعرض تفاصيل تقنية للمستخدم.</p>
      <button type="button" onClick={() => reset()}>إعادة المحاولة</button>
    </section>
  );
}
