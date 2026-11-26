import Link from 'next/link';
import { EmptyState, PageHeader, Section, Stat, StatGrid } from '@/shared/ui';
import { BarList } from '@/shared/ui/insight';
import { EntryLinks } from '@/features/workspace/entry-links';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { getOrganizationProcurementEvidence } from '@/features/procurement/queries';
import { EVIDENCE_CLASSIFICATION_LABEL, formatDate } from '@/features/procurement/labels';

export const dynamic = 'force-dynamic';

/** المستندات: ملفات أدلة المشتريات (عقود وأوامر شراء واستلام وفواتير) عبر المشاريع. قراءة فقط، الرفع من المشتريات. */
export default async function DocumentsPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="المستندات تظهر بعد رفع أدلة من المشاريع."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }
  const [docs, projects] = await Promise.all([getOrganizationProcurementEvidence(org.id), getProjects(org.id)]);
  const projectName = new Map(projects.map((p) => [p.id, p.name]));
  const kinds = Object.keys(EVIDENCE_CLASSIFICATION_LABEL);
  return (
    <section className="stack-lg">
      <PageHeader
        eyebrow={org.name}
        title="المستندات"
        description="ملفات أدلة المشتريات عبر المشاريع: عقود وأوامر شراء وإثباتات استلام وفواتير. روابط التنزيل مؤقتة (5 دقائق). الرفع من صفحة المشتريات داخل المشروع."
      />
      <StatGrid label="ملخص المستندات">
        <Stat label="عدد الملفات" value={docs.length} />
        <Stat label="مستندات مميزة" value={new Set(docs.map((d) => d.document_id)).size} />
      </StatGrid>
      <EntryLinks title="رفع مستند" projects={projects} label="المشتريات" hrefFor={(p) => `/projects/${p.id}/procurement`} />

      {docs.length === 0 ? (
        <EmptyState title="لا توجد مستندات بعد" description="ارفع دليلًا من صفحة المشتريات داخل المشروع." action={<Link className="button" href="/projects">فتح المشاريع</Link>} />
      ) : (
        <Section title="الملفات" description={`${docs.length} ملف، الأحدث أولًا.`}>
          <BarList
            caption="حسب النوع"
            items={kinds.map((k) => ({ key: k, label: EVIDENCE_CLASSIFICATION_LABEL[k], value: docs.filter((d) => d.classification === k).length }))}
          />
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">المستندات: العنوان والنوع والمشروع والإصدار وتاريخ الرفع</caption>
              <thead>
                <tr>
                  <th scope="col">المستند</th>
                  <th scope="col">النوع</th>
                  <th scope="col">المشروع</th>
                  <th scope="col">الإصدار</th>
                  <th scope="col">تاريخ الرفع</th>
                </tr>
              </thead>
              <tbody>
                {docs.map((d) => (
                  <tr key={d.evidence_link_id}>
                    <td data-label="المستند">
                      {d.download_url ? <a href={d.download_url} target="_blank" rel="noreferrer"><strong>{d.title}</strong></a> : <strong>{d.title}</strong>}
                      <br /><small className="muted">{d.original_filename}</small>
                    </td>
                    <td data-label="النوع">{EVIDENCE_CLASSIFICATION_LABEL[d.classification] ?? d.classification}</td>
                    <td data-label="المشروع"><Link href={`/projects/${d.project_id}/procurement`}>{projectName.get(d.project_id) ?? 'مشروع'}</Link></td>
                    <td data-label="الإصدار">{d.version_number}</td>
                    <td data-label="تاريخ الرفع">{formatDate(d.uploaded_at)}</td>
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
