import Link from 'next/link';
import { EmptyState, PageHeader } from '@/shared/ui';
import { getActiveOrganization } from '@/features/organizations/context';
import {
  getOrganizationActiveMemberships,
  getPortfolios,
} from '@/features/portfolios/queries';
import {
  PORTFOLIO_STATUS_BADGE_CLASS,
  PORTFOLIO_STATUS_LABEL,
} from '@/features/portfolios/labels';

export const dynamic = 'force-dynamic';

export default async function PortfoliosPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="المنظمة هي الحدود الآمنة لبيانات الاستثمار الخاصة بفريقك."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }
  const portfolios = await getPortfolios(org.id);
  const memberships = await getOrganizationActiveMemberships(org.id);
  const countByPortfolio = new Map<string, number>();
  for (const m of memberships) {
    countByPortfolio.set(m.portfolio_id, (countByPortfolio.get(m.portfolio_id) ?? 0) + 1);
  }

  return (
    <section className="stack-lg">
      <PageHeader
        eyebrow={org.name}
        title="المحافظ الاستثمارية"
        description="المحفظة إطار إداري وتنظيمي للمشاريع المستقلة، وليست كيانًا قانونيًا أو صندوقًا أو وعاء أموال مجمّعًا."
        actions={<Link className="button" href="/portfolios/new">محفظة جديدة</Link>}
      />

      {portfolios.length === 0 ? (
        <EmptyState
          title="لا توجد محافظ بعد"
          description="أنشئ أول محفظة لتنظيم مشاريع المنظمة تحت إطار إداري واحد. لن نعرض أرقامًا مجمعة أو بيانات تجريبية."
          action={<Link className="button" href="/portfolios/new">إنشاء أول محفظة</Link>}
        />
      ) : (
        <ul className="grid card-list" aria-label="قائمة المحافظ">
          {portfolios.map((pf) => (
            <li key={pf.id}>
              <Link href={`/portfolios/${pf.id}`} className="project no-sector">
                <strong>{pf.name}</strong>
                <div className="badge-row">
                  <span className={PORTFOLIO_STATUS_BADGE_CLASS[pf.status]}>
                    {PORTFOLIO_STATUS_LABEL[pf.status]}
                  </span>
                  <span className="status">
                    {countByPortfolio.get(pf.id) ?? 0} مشروع مُسند
                  </span>
                </div>
                <p className="muted">{pf.description || 'بدون غرض إداري مسجل'}</p>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
