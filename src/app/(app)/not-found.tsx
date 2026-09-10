import Link from 'next/link';

export default function NotFound() {
  return (
    <section className="card stack">
      <h1>العنصر غير موجود</h1>
      <p className="muted">قد لا تملك صلاحية الوصول إليه أو ربما حُذف.</p>
      <div className="page-actions">
        <Link href="/projects" className="button">العودة إلى المشاريع</Link>
        <Link href="/" className="button secondary">الرئيسية</Link>
      </div>
    </section>
  );
}
