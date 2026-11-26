import Link from 'next/link';
import { EmptyState, PageHeader, Section, Stat, StatGrid } from '@/shared/ui';
import { EntryLinks } from '@/features/workspace/entry-links';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { getOrganizationHarvestInventory } from '@/features/agriculture/queries';
import { formatDate } from '@/features/procurement/labels';

export const dynamic = 'force-dynamic';

/**
 * المخزون: أرصدة المحاصيل المحصودة حسب موقع التخزين عبر مشاريع الزراعة.
 * هذا هو المخزون الوحيد المسجَّل في النظام؛ لا يوجد مخزون عام للمواد. لا تُجمع كميات بوحدات مختلفة.
 */
export default async function InventoryPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="المخزون يظهر بعد تسجيل حصاد في مشروع زراعي."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }
  const [rows, projects] = await Promise.all([getOrganizationHarvestInventory(org.id), getProjects(org.id)]);
  const projectName = new Map(projects.map((p) => [p.id, p.name]));
  const units = [...new Set(rows.map((r) => r.quantity_unit))];
  return (
    <section className="stack-lg">
      <PageHeader
        eyebrow={org.name}
        title="المخزون"
        description="أرصدة المحاصيل المحصودة حسب موقع التخزين عبر مشاريع الزراعة، قراءة فقط. لا يوجد مخزون عام للمواد في النظام، ولا نجمع كميات بوحدات مختلفة."
      />
      <StatGrid label="ملخص المخزون">
        <Stat label="أرصدة (دفعة × موقع)" value={rows.length} />
        <Stat label="مواقع تخزين" value={new Set(rows.map((r) => r.storage_id)).size} />
        <Stat label="وحدات القياس" value={units.length === 0 ? '—' : units.join('، ')} />
      </StatGrid>
      <EntryLinks title="تسجيل حصاد أو حركة مخزون" projects={projects.filter((p) => p.sector === 'AGRICULTURE')} label="الزراعة" hrefFor={(p) => `/projects/${p.id}/agriculture`} />

      {rows.length === 0 ? (
        <EmptyState title="لا يوجد مخزون مسجَّل" description="يظهر بعد تسجيل حصاد وتخزينه من صفحة الزراعة في المشروع." action={<Link className="button" href="/projects">فتح المشاريع</Link>} />
      ) : (
        <Section title="الأرصدة" description={`${rows.length} رصيد.`}>
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">أرصدة المخزون: الدفعة والموقع والمشروع والرصيد وآخر حركة</caption>
              <thead>
                <tr>
                  <th scope="col">الدفعة</th>
                  <th scope="col">موقع التخزين</th>
                  <th scope="col">المشروع</th>
                  <th scope="col" className="num">الرصيد</th>
                  <th scope="col">آخر حركة</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={`${r.harvest_lot_id}-${r.storage_id}`}>
                    <td data-label="الدفعة"><strong>{r.lot_reference}</strong>{r.grade ? <><br /><small className="muted">درجة {r.grade}</small></> : null}</td>
                    <td data-label="موقع التخزين">{r.storage_name}</td>
                    <td data-label="المشروع"><Link href={`/projects/${r.project_id}/agriculture`}>{projectName.get(r.project_id) ?? 'مشروع'}</Link></td>
                    <td data-label="الرصيد" className="num">{r.current_balance} {r.quantity_unit}</td>
                    <td data-label="آخر حركة">{formatDate(r.last_movement_date)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Section>
      )}
    </section>
  );
}
