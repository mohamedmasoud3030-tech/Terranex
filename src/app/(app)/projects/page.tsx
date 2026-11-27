import Link from 'next/link';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { PROJECT_LIFECYCLE_LABEL, SECTOR_LABEL, projectLifecycleTone } from '@/features/projects/labels';
import { EmptyState, PageHeader, SectorChip, StatusBadge } from '@/shared/ui';
import { SECTOR_THEME_CLASS } from '@/features/workspace/sectors';
import type { ProjectSector } from '@/features/projects/queries';
import { PlainIntro } from '@/features/plain-language/plain-intro';

export const dynamic = 'force-dynamic';

const SECTOR_ORDER: ReadonlyArray<ProjectSector> = ['REAL_ESTATE', 'AGRICULTURE', 'LIVESTOCK'];

function isSector(value: string | undefined): value is ProjectSector {
  return value === 'REAL_ESTATE' || value === 'AGRICULTURE' || value === 'LIVESTOCK';
}

/**
 * Investment projects index.
 *
 * A card here is a decision preview, not a marketing tile: identity, which
 * vertical it belongs to, where it is in its lifecycle, which currency its
 * books are kept in, and one obvious way in. The vertical is the primary
 * filter because it decides which operating rules, sections, and evidence the
 * project is governed by — it is the one distinction an operator uses to
 * choose where to work next.
 */
export default async function ProjectsPage({
  searchParams,
}: {
  searchParams?: Promise<{ sector?: string }>;
}) {
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

  const params = (await searchParams) ?? {};
  const activeSector = isSector(params.sector) ? params.sector : null;
  const projects = await getProjects(organization.id);

  const countBySector = new Map<ProjectSector, number>();
  for (const project of projects) {
    countBySector.set(project.sector, (countBySector.get(project.sector) ?? 0) + 1);
  }

  const visible = activeSector
    ? projects.filter((project) => project.sector === activeSector)
    : projects;

  const filters = (
    <nav className="tab-strip tab-strip-secondary" aria-label="تصفية حسب القطاع">
      <Link
        href="/projects"
        aria-current={activeSector === null ? 'page' : undefined}
        className="tab"
      >
        كل القطاعات ({projects.length})
      </Link>
      {SECTOR_ORDER.map((sector) => (
        <Link
          key={sector}
          href={`/projects?sector=${sector}`}
          aria-current={activeSector === sector ? 'page' : undefined}
          className="tab"
        >
          {SECTOR_LABEL[sector]} ({countBySector.get(sector) ?? 0})
        </Link>
      ))}
    </nav>
  );

  return (
    <section className="stack-lg">
      <PlainIntro page="projects" />
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
        <>
          {filters}

          {visible.length === 0 ? (
            <EmptyState
              title={`لا توجد مشاريع في قطاع ${activeSector ? SECTOR_LABEL[activeSector] : ''}`}
              description="غيّر القطاع لعرض بقية مشاريع المنظمة."
              action={<Link className="button secondary" href="/projects">كل القطاعات</Link>}
            />
          ) : (
            <ul className="grid card-list" aria-label="قائمة المشاريع">
              {visible.map((project) => (
                <li key={project.id} className={SECTOR_THEME_CLASS[project.sector]}>
                  <Link href={`/projects/${project.id}`} className="project">
                    <strong>{project.name}</strong>
                    <div className="badge-row">
                      <SectorChip sector={project.sector} label={SECTOR_LABEL[project.sector] ?? project.sector} />
                      <StatusBadge tone={projectLifecycleTone(project.lifecycle_state)}>
                        {PROJECT_LIFECYCLE_LABEL[project.lifecycle_state] ?? project.lifecycle_state}
                      </StatusBadge>
                      <span className="status">{project.reporting_currency}</span>
                    </div>
                    <p className="muted clamp-1">{project.description || 'بدون وصف مسجل'}</p>
                    {project.internal_reference ? (
                      <small className="muted">المرجع: <code>{project.internal_reference}</code></small>
                    ) : null}
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
    </section>
  );
}
