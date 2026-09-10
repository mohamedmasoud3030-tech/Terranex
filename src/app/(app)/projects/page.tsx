import Link from 'next/link';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { PROJECT_LIFECYCLE_LABEL, SECTOR_LABEL, projectLifecycleTone } from '@/features/projects/labels';
import { EmptyState, PageHeader, StatusBadge } from '@/shared/ui';

export const dynamic = 'force-dynamic';

export default async function ProjectsPage() {
  const { organization } = await getActiveOrganization();

  if (!organization) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="المنظمة هي الحدود الآمنة لبيانات الاستثمار الخاصة بفريقك."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }

  const projects = await getProjects(organization.id);

  return (
    <section className="stack">
      <PageHeader
        eyebrow={organization.name}
        title="المشاريع الاستثمارية"
        description="المشاريع المستقلة داخل المنظمة، مع القطاع والحالة وعملة التقارير من المصدر الرسمي."
        actions={<Link className="button" href="/projects/new">مشروع جديد</Link>}
      />

      {projects.length === 0 ? (
        <EmptyState
          title="لا توجد مشاريع بعد"
          description="أنشئ أول مشروع، أو استخدم المحافظ لتنظيم المشاريع تحت إطار إداري. لن نعرض أرقامًا أو بيانات تجريبية."
          action={
            <>
              <Link className="button" href="/projects/new">إنشاء أول مشروع</Link>
              <Link className="button secondary" href="/portfolios">عرض المحافظ</Link>
            </>
          }
        />
      ) : (
        <ul className="grid card-list" aria-label="قائمة المشاريع">
          {projects.map((project) => (
            <li key={project.id}>
              <Link href={`/projects/${project.id}`} className="project">
                <strong>{project.name}</strong>
                <p className="muted clamp-1">{project.description || 'بدون وصف مسجل'}</p>
                <div className="badge-row">
                  <StatusBadge>{SECTOR_LABEL[project.sector] ?? project.sector}</StatusBadge>
                  <StatusBadge tone={projectLifecycleTone(project.lifecycle_state)}>
                    {PROJECT_LIFECYCLE_LABEL[project.lifecycle_state] ?? project.lifecycle_state}
                  </StatusBadge>
                  <span className="muted">{project.reporting_currency}</span>
                </div>
                {project.internal_reference ? <small className="muted">المرجع: {project.internal_reference}</small> : null}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
