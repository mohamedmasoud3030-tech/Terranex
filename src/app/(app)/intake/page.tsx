import Link from 'next/link';
import { getOrganizations } from '@/features/organizations/queries';
import { getProjects } from '@/features/projects/queries';

export const dynamic = 'force-dynamic';

export default async function IntakeStartPage() {
  const organizations = await getOrganizations();
  if (organizations.length === 0) {
    return (
      <section className="card stack" style={{ maxWidth: 680 }}>
        <h1>إدخال أول مشروع حقيقي</h1>
        <p>ابدأ بالمنظمة. العملة الوظيفية ثابتة: جنيه مصري. القطاع الأول: عقاري.</p>
        <p className="muted">لا نعرض بيانات تجريبية. المسار يستخدم أوامر المنتج الحالية فقط.</p>
        <Link className="button" href="/onboarding">إنشاء المنظمة</Link>
      </section>
    );
  }

  const organization = organizations[0];
  const projects = await getProjects(organization.id);

  return (
    <section className="stack">
      <div>
        <p className="muted">{organization.name}</p>
        <h1>إدخال المشروع الحقيقي</h1>
        <p className="muted">مسار موجّه: الإعداد → المستثمرون → رأس المال → البنك → العقار → المركز الافتتاحي → التحقق.</p>
      </div>
      {projects.length === 0 ? (
        <section className="card stack">
          <h2>لا يوجد مشروع بعد</h2>
          <p>أنشئ مشروعًا عقاريًا واحدًا ضمن نطاق التشغيل التجريبي المتفق عليه.</p>
          <Link className="button" href="/projects/new">إنشاء مشروع عقاري</Link>
        </section>
      ) : (
        <div className="grid">
          {projects.map((project) => (
            <Link key={project.id} href={`/projects/${project.id}/intake`} className="project">
              <strong>{project.name}</strong>
              <p className="muted">{project.internal_reference || 'بدون مرجع داخلي'}</p>
              <span className="status">متابعة الإدخال</span>
            </Link>
          ))}
          <Link href="/projects/new" className="project">
            <strong>مشروع عقاري إضافي</strong>
            <p className="muted">فقط إذا كان داخل نطاق التشغيل التجريبي الموقّع.</p>
          </Link>
        </div>
      )}
    </section>
  );
}
