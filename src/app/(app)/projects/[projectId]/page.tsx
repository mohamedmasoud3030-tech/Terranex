import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership, getProjectCashByCurrency, getProjectCapitalByCurrency } from '@/features/finance/queries';
import { getProjectResultByCurrency } from '@/features/result/queries';
import { buildProjectResultView } from '@/features/result/project-result';
import { ResultPanel } from '@/features/result/result-panel';
import { buildProjectCapitalView } from '@/features/funding/project-capital';
import { CapitalPanel } from '@/features/funding/capital-panel';
import { getAccountingPeriods } from '@/features/close/queries';
import { formatMinorUnits } from '@/shared/money';
import { WorkspaceNav, sectorLandingHref, sectionsFor } from '@/features/workspace/nav';
import { PROJECT_LIFECYCLE_LABEL, SECTOR_LABEL, projectLifecycleTone } from '@/features/projects/labels';
import { Banner, Section, Stat, StatGrid, StatusBadge } from '@/shared/ui';

export const dynamic = 'force-dynamic';

/**
 * Project home: identity, a short position summary, and the section map.
 * Detailed financial dashboards live in `/overview` and the finance sections;
 * this page only orients the operator and routes onward.
 */
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

  const [membership, capitalRows, cashByCurrency, resultRows, periods] = await Promise.all([
    getCurrentMembership(organizationId),
    getProjectCapitalByCurrency(projectId),
    getProjectCashByCurrency(projectId),
    getProjectResultByCurrency(projectId),
    getAccountingPeriods(projectId),
  ]);

  const capital = buildProjectCapitalView(capitalRows);
  const result = buildProjectResultView(resultRows);

  const isDemo = Boolean(project.internal_reference?.startsWith('DEMO'));
  const openPeriod = periods.find((period) => period.status === 'OPEN') ?? null;
  const sections = sectionsFor(sector).filter((section) => section.id !== 'overview');

  return (
    <section className="stack">
      <header className="project-context card page-header">
        <div className="page-header-main">
          <Link className="muted back-link" href="/projects">← المشاريع</Link>
          <div className="page-title-row">
            <h1>{project.name}</h1>
            <StatusBadge tone={projectLifecycleTone(project.lifecycle_state)}>
              {PROJECT_LIFECYCLE_LABEL[project.lifecycle_state] ?? project.lifecycle_state}
            </StatusBadge>
            <StatusBadge>{SECTOR_LABEL[sector] ?? sector}</StatusBadge>
          </div>
          <p className="muted page-description">
            {currency}
            {project.internal_reference ? ` · ${project.internal_reference}` : ''}
            {project.description ? ` · ${project.description}` : ''}
          </p>
        </div>
        <div className="page-actions">
          <Link className="button" href={sectorLandingHref(sector, projectId)}>دخول مساحة القطاع</Link>
        </div>
      </header>

      {isDemo && (
        <Banner tone="info">
          هذا المشروع ({project.internal_reference}) بيانات توضيحية اصطناعية ثابتة. تُستخدم للمعاينة والتدريب
          والتحقق، ولا تُحتسب كدليل عميل حقيقي أو إغلاق لأي بوابة مرحلَة ثانية أو ثالثة.
        </Banner>
      )}

      {!membership && (
        <Banner tone="warning" role="alert">عضويتك الحالية لا تسمح بالوصول الكامل لهذا المشروع.</Banner>
      )}

      <WorkspaceNav projectId={projectId} active="overview" sector={sector} />

      <StatGrid label="الموقف الحالي للمشروع">
        <Stat
          label="رأس المال المساهم به"
          value={formatMinorUnits(position?.contributed_minor_units ?? '0', currency)}
          hint="من القراءة الرسمية للموقف الرأسمالي"
          href={`/projects/${projectId}/funding`}
        />
        <Stat
          label="النقدية الحالية"
          value={formatMinorUnits(totalCash, currency)}
          hint="مجموع أرصدة الحسابات النقدية"
          href={`/projects/${projectId}/cash`}
        />
        <Stat
          label="النتيجة المحققة"
          value={formatMinorUnits(realizedResult, currency)}
          hint="من قيود الاعتراف المتوازنة"
          href={`/projects/${projectId}/revenue`}
        />
        <Stat
          label="الفترة المحاسبية"
          value={
            openPeriod
              ? `${new Date(openPeriod.start_date).toLocaleDateString('ar-EG')} → ${new Date(openPeriod.end_date).toLocaleDateString('ar-EG')}`
              : 'لا توجد فترة مفتوحة'
          }
          hint={openPeriod ? 'فترة مفتوحة' : 'أنشئ فترة من الإغلاق المالي'}
          href={`/projects/${projectId}/close`}
        />
      </StatGrid>

      <CapitalPanel view={capital} />

      <ResultPanel view={result} />

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

      <Section title="أقسام مساحة العمل" description="كل قسم يعرض حقائقه المسجلة فقط؛ ابدأ من القسم المناسب لمهمتك.">
        <ul className="link-list" aria-label="أقسام مساحة العمل">
          {sections.map((section) => (
            <li key={section.id}>
              <Link href={section.href(projectId)}>
                <strong>{section.label}</strong>
                <span className="muted">{section.description}</span>
              </Link>
            </li>
          ))}
        </ul>
      </Section>
    </section>
  );
}
