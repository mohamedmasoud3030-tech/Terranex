import Link from 'next/link';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';

export const dynamic = 'force-dynamic';

const SECTOR_LABEL = {
  REAL_ESTATE: 'عقارات',
  AGRICULTURE: 'زراعة',
  LIVESTOCK: 'ثروة حيوانية',
} as const;

export default async function ProjectsPage() {
  const { organization } = await getActiveOrganization();

  if (!organization) {
    return (
      <section className="card stack">
        <h1>لنبدأ بإنشاء منظمتك</h1>
        <p className="muted">المنظمة هي الحدود الآمنة لبيانات الاستثمار الخاصة بفريقك.</p>
        <Link className="button" href="/onboarding">إنشاء منظمة</Link>
      </section>
    );
  }

  const projects = await getProjects(organization.id);

  return (
    <section className="stack">
      <div className="top">
        <div>
          <p className="muted">{organization.name}</p>
          <h1>المشاريع الاستثمارية</h1>
          <p className="muted">المشاريع المستقلة داخل المنظمة، مع القطاع والحالة وعملة التقارير من المصدر الرسمي.</p>
        </div>
        <Link className="button" href="/projects/new">مشروع جديد</Link>
      </div>

      {projects.length === 0 ? (
        <section className="card stack empty">
          <h2>لا توجد مشاريع بعد</h2>
          <p className="muted">أنشئ أول مشروع، أو استخدم المحافظ لتنظيم المشاريع تحت إطار إداري.</p>
          <div className="actions">
            <Link className="button" href="/projects/new">إنشاء أول مشروع</Link>
            <Link href="/portfolios">عرض المحافظ</Link>
          </div>
        </section>
      ) : (
        <div className="grid">
          {projects.map((project) => (
            <Link key={project.id} href={`/projects/${project.id}`} className="project">
              <strong>{project.name}</strong>
              <p className="muted">{project.description || 'بدون وصف مسجل'}</p>
              <span className="status">{SECTOR_LABEL[project.sector]}</span>
              <span className="muted">الحالة: {project.lifecycle_state} · عملة التقارير: {project.reporting_currency}</span>
              {project.internal_reference ? <small>المرجع: {project.internal_reference}</small> : null}
            </Link>
          ))}
        </div>
      )}
    </section>
  );
}
