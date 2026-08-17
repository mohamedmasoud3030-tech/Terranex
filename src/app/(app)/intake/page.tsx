import Link from 'next/link';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { SECTOR_LABEL } from '@/features/agriculture/labels';

export const dynamic = 'force-dynamic';

export default async function IntakeStartPage() {
  const { organization } = await getActiveOrganization();
  if (!organization) {
    return (
      <section className="card stack" style={{ maxWidth: 680 }}>
        <h1>إدخال أول مشروع حقيقي</h1>
        <p>ابدأ بالمنظمة. عملة المشاريع: جنيه مصري (EGP). القطاعات المدعومة: عقارات، زراعة، ثروة حيوانية.</p>
        <p className="muted">لا نعرض بيانات تجريبية. المسار يستخدم أوامر المنتج الحالية فقط.</p>
        <Link className="button" href="/onboarding">إنشاء المنظمة</Link>
      </section>
    );
  }

  const projects = await getProjects(organization.id);

  return (
    <section className="stack">
      <div>
        <p className="muted">{organization.name}</p>
        <h1>إدخال المشروع الحقيقي</h1>
        <p className="muted">مسار موجّه: الإعداد → الأطراف والاتفاقية → رأس المال → البنك → حقائق القطاع → المركز الافتتاحي → التحقق.</p>
      </div>
      {projects.length === 0 ? (
        <section className="card stack">
          <h2>لا يوجد مشروع بعد</h2>
          <p>أنشئ مشروعًا بقطاعه المحدد (عقارات، زراعة، أو ثروة حيوانية) ضمن نطاق التشغيل التجريبي المتفق عليه.</p>
          <Link className="button" href="/projects/new">إنشاء أول مشروع</Link>
        </section>
      ) : (
        <div className="grid">
          {projects.map((project) => (
            <Link key={project.id} href={`/projects/${project.id}/intake`} className="project">
              <strong>{project.name}</strong>
              <p className="muted">{project.internal_reference || 'بدون مرجع داخلي'}</p>
              <span className="status">{SECTOR_LABEL[project.sector] ?? project.sector} · متابعة الإدخال</span>
            </Link>
          ))}
          <Link href="/projects/new" className="project">
            <strong>مشروع إضافي</strong>
            <p className="muted">فقط إذا كان داخل نطاق التشغيل التجريبي الموقّع.</p>
            <span className="status">مشروع جديد</span>
          </Link>
        </div>
      )}
    </section>
  );
}
