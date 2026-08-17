import Link from 'next/link';
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
      <div className="top">
        <div>
          <p className="muted">{org.name}</p>
          <h1>المحافظ الاستثمارية</h1>
          <p className="muted">
            المحفظة إطار إداري وتنظيمي للمشاريع المستقلة، وليست كيانًا قانونيًا أو صندوقًا
            أو وعاء أموال مجمّعًا.
          </p>
        </div>
        <Link className="button" href="/portfolios/new">محفظة جديدة</Link>
      </div>

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
