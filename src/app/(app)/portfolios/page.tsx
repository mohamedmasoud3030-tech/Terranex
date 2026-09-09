import Link from 'next/link';
import { PageHeader } from '@/shared/ui';
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
      <section className="card stack">
        <h1>لنبدأ بإنشاء منظمتك</h1>
        <p className="muted">المنظمة هي الحدود الآمنة لبيانات الاستثمار الخاصة بفريقك.</p>
        <Link className="button" href="/onboarding">إنشاء منظمة</Link>
      </section>
    );
  }
  const portfolios = await getPortfolios(org.id);
  const memberships = await getOrganizationActiveMemberships(org.id);
  const countByPortfolio = new Map<string, number>();
  for (const m of memberships) {
    countByPortfolio.set(m.portfolio_id, (countByPortfolio.get(m.portfolio_id) ?? 0) + 1);
  }

  return (
    <section className="stack">
      <PageHeader
        eyebrow={org.name}
        title="المحافظ الاستثمارية"
        description="المحفظة إطار إداري وتنظيمي للمشاريع المستقلة، وليست كيانًا قانونيًا أو صندوقًا أو وعاء أموال مجمّعًا."
        actions={<Link className="button" href="/portfolios/new">محفظة جديدة</Link>}
      />

      {portfolios.length === 0 ? (
        <section className="card stack empty">
          <h2>لا توجد محافظ بعد</h2>
          <p className="muted">
            أنشئ أول محفظة لتنظيم مشاريع المنظمة تحت إطار إداري واحد. لن نعرض أرقامًا
            مجمعة أو بيانات تجريبية.
          </p>
          <Link className="button" href="/portfolios/new">إنشاء أول محفظة</Link>
        </section>
      ) : (
        <div className="grid">
          {portfolios.map((pf) => (
            <Link key={pf.id} href={`/portfolios/${pf.id}`} className="project">
              <strong>{pf.name}</strong>
              <p className="muted">{pf.description || 'بدون غرض إداري مسجل'}</p>
              <span className={PORTFOLIO_STATUS_BADGE_CLASS[pf.status]}>
                {PORTFOLIO_STATUS_LABEL[pf.status]}
              </span>
              <span className="status">
                {countByPortfolio.get(pf.id) ?? 0} مشروع مُسند
              </span>
            </Link>
          ))}
        </div>
      )}
    </section>
  );
}
