import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership, getProjectCashByCurrency, getProjectCapitalByCurrency } from '@/features/finance/queries';
import { buildProjectCapitalView } from '@/features/funding/project-capital';
import { CapitalPanel } from '@/features/funding/capital-panel';
import { getAccountingPeriods } from '@/features/close/queries';
import { getRealizedResults } from '@/features/revenue/queries';
import { formatMinorUnits } from '@/shared/money';
import { WorkspaceNav, sectorLandingHref } from '@/features/workspace/nav';
import { SECTOR_LABEL } from '@/features/agriculture/labels';

export const dynamic = 'force-dynamic';

const STATE_LABEL: Record<string, string> = {
  DRAFT: 'مسودة',
  FUNDING: 'مرحلة التمويل',
};

export default async function ProjectShell({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;
  const currency = project.reporting_currency;
  const sector = project.sector;

  const [membership, capitalRows, cashByCurrency, results, periods] = await Promise.all([
    getCurrentMembership(organizationId),
    getProjectCapitalByCurrency(projectId),
    getProjectCashByCurrency(projectId),
    getRealizedResults(projectId),
    getAccountingPeriods(projectId),
  ]);

  const capital = buildProjectCapitalView(capitalRows);
  const isDemo = Boolean(project.internal_reference?.startsWith('DEMO'));
  // Cash is reported per currency and never summed. Adding OMR minor units to
  // USD minor units and labelling the result with the project reporting currency
  // invented a number no ledger supports, so there is no combined figure here to
  // render — by design, not by omission.
  const realizedResult = results.reduce((sum, result) => sum + BigInt(result.realized_result_minor_units), 0n);
  const openPeriod = periods.find((period) => period.status === 'OPEN') ?? null;

  return (
    <section className="stack">
      <header className="project-context card">
        <div>
          <Link className="muted" href="/">← المشاريع</Link>
          <div className="topline">
            <div>
              <span className="status">
                {SECTOR_LABEL[sector] ?? sector} · {STATE_LABEL[project.lifecycle_state] ?? project.lifecycle_state}
              </span>
              <h1>{project.name}</h1>
              <p className="muted">
                {SECTOR_LABEL[sector] ?? sector} · {currency}
                {project.internal_reference ? ` · ${project.internal_reference}` : ''}
              </p>
            </div>
            <Link className="button secondary" href={sectorLandingHref(sector, projectId)}>
              دخول مساحة القطاع
            </Link>
          </div>
        </div>
      </header>

      {isDemo && (
        <div className="banner info" role="note">
          هذا المشروع ({project.internal_reference}) بيانات توضيحية اصطناعية ثابتة. تُستخدم للمعاينة والتدريب
          والتحقق، ولا تُحتسب كدليل عميل حقيقي أو إغلاق لأي بوابة مرحلَة ثانية أو ثالثة.
        </div>
      )}

      <WorkspaceNav projectId={projectId} active="overview" sector={sector} />

      <CapitalPanel view={capital} />

      <section className="card stack">
        <div className="topline">
          <h2>مساحة عمل المشروع</h2>
          <Link className="button" href={sectorLandingHref(sector, projectId)}>دخول مساحة القطاع</Link>
        </div>
        <p>{project.description || 'لم يُضف وصف للمشروع بعد.'}</p>
        <div className="overview-kpis">
          {cashByCurrency.length === 0 ? (
            <article className="overview-kpi">
              <span>النقدية الحالية</span>
              <strong>—</strong>
              <small>لا توجد حسابات نقدية مسجلة؛ لا نعرض صفرًا مفترضًا</small>
            </article>
          ) : (
            cashByCurrency.map((cash) => (
              <article className="overview-kpi" key={cash.currency}>
                <span>النقدية — {cash.currency}</span>
                <strong>{formatMinorUnits(cash.cash_balance_minor_units, cash.currency)}</strong>
                <small>
                  {cash.account_count} حساب
                  {cash.has_active_posted_movement ? '' : ' · بلا حركة نشطة'}
                  {cash.currency_mismatch_line_count > 0
                    ? ` · ${cash.currency_mismatch_line_count} حركة بعملة مخالفة مستبعدة`
                    : ''}
                </small>
              </article>
            ))
          )}
          <article className="overview-kpi">
            <span>النتيجة المحققة</span>
            <strong>{formatMinorUnits(realizedResult, currency)}</strong>
            <small>من قيود الاعتراف المتوازنة</small>
          </article>
          <article className="overview-kpi">
            <span>الفترة المحاسبية</span>
            <strong>
              {openPeriod
                ? `${new Date(openPeriod.start_date).toLocaleDateString('ar-EG')} → ${new Date(openPeriod.end_date).toLocaleDateString('ar-EG')}`
                : 'لا توجد فترة مفتوحة'}
            </strong>
            <small>{openPeriod ? openPeriod.status : 'أنشئ فترة من الإغلاق المالي'}</small>
          </article>
        </div>
      </section>

      {!membership && (
        <p className="error" role="alert">عضويتك الحالية لا تسمح بالوصول الكامل لهذا المشروع.</p>
      )}
    </section>
  );
}
