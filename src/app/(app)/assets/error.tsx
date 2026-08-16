'use client';

export default function AssetsError({ reset }: { reset: () => void }) {
  return (
    <section className="card stack">
      <h1>تعذر عرض سجل الأصول</h1>
      <p className="muted">
        حدث خطأ أثناء تحميل الأصول وأداء القطاعات. لم تُعرض تفاصيل تقنية، ولم يتغيّر
        أي سجل — هذه الصفحة للقراءة فقط.
      </p>
      <button type="button" onClick={() => reset()}>إعادة المحاولة</button>
    </section>
  );
}
