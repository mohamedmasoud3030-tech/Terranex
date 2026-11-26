import Link from 'next/link';
import { EmptyState, PageHeader, SectorChip, Section } from '@/shared/ui';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { getSectorPerformance } from '@/features/assets/queries';
import { SectorCard } from '@/features/assets/sector-card';
import { SECTOR_LABEL } from '@/features/assets/labels';
import { PROJECT_LIFECYCLE_LABEL } from '@/features/projects/labels';

export const dynamic = 'force-dynamic';

/** Report pages that exist inside every project. Links only, no new numbers. */
const PROJECT_REPORTS: ReadonlyArray<{ path: string; label: string }> = [
  { path: 'overview', label: 'الملخص' },
  { path: 'costs', label: 'التكاليف' },
  { path: 'cash', label: 'النقدية' },
  { path: 'revenue', label: 'الإيرادات' },
  { path: 'budget', label: 'الميزانية' },
  { path: 'close', label: 'الإقفال' },
  { path: 'integrity', label: 'سلامة البيانات' },
];

export default async function ReportsPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="التقارير تظهر بعد إنشاء منظمة ومشروع."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }
  const [projects, performance] = await Promise.all([getProjects(org.id), getSectorPerformance(org.id)]);
  return (
    <section className="stack-lg">
      <PageHeader
        eyebrow={org.name}
        title="التقارير"
        description="أداء القطاعات وتقارير كل مشروع في مكان واحد. الأرقام من قاعدة البيانات فقط، وكل عملة تُعرض منفصلة."
      />
      <Section title="أداء القطاعات">
        {performance.length === 0 ? (
          <EmptyState title="لا توجد بيانات قطاعات بعد" description="ستظهر هنا فور إنشاء مشروع." />
        ) : (
          <div className="panel-grid">
            {performance.map((row) => <SectorCard key={`${row.sector}-${row.currency}`} row={row} />)}
          </div>
        )}
      </Section>
      <Section title="تقارير المشاريع" description={`${projects.length} مشروع`}>
        {projects.length === 0 ? (
          <EmptyState title="لا توجد مشاريع" action={<Link className="button" href="/intake">إدخال مشروع</Link>} />
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">روابط تقارير كل مشروع</caption>
              <thead>
                <tr>
                  <th scope="col">المشروع</th>
                  <th scope="col">التقارير</th>
                </tr>
              </thead>
              <tbody>
                {projects.map((p) => (
                  <tr key={p.id}>
                    <td data-label="المشروع">
                      <strong>{p.name}</strong><br />
                      <SectorChip sector={p.sector} label={SECTOR_LABEL[p.sector] ?? p.sector} />{' '}
                      <small className="muted">{PROJECT_LIFECYCLE_LABEL[p.lifecycle_state] ?? p.lifecycle_state}</small>
                    </td>
                    <td data-label="التقارير">
                      <span className="badge-row">
                        {PROJECT_REPORTS.map((r) => (
                          <Link key={r.path} className="button secondary sm" href={`/projects/${p.id}/${r.path}`}>{r.label}</Link>
                        ))}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>
    </section>
  );
}
