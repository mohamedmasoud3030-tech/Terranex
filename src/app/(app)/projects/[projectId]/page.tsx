import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership, getCashAccountPositions } from '@/features/finance/queries';
import { getProjectCapitalPosition } from '@/features/funding/queries';
import { getAccountingPeriods } from '@/features/close/queries';
import { getRealizedResults } from '@/features/revenue/queries';
import { formatMinorUnits } from '@/shared/money';
import { WorkspaceNavGrouped, sectorLandingHref, sectionsFor } from '@/features/workspace/nav';
import { SECTOR_LABEL } from '@/features/agriculture/labels';
import { PROJECT_LIFECYCLE_LABEL, projectLifecycleTone } from '@/features/projects/labels';
import { Banner, Section, SectorChip, Stat, StatGrid, StatusBadge } from '@/shared/ui';
import { SECTOR_THEME_CLASS } from '@/shared/ui/sector';

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

  const [membership, position, cashAccounts, results, periods] = await Promise.all([
    getCurrentMembership(organizationId),
    getProjectCapitalPosition(projectId),
    getCashAccountPositions(projectId),
    getRealizedResults(projectId),
    getAccountingPeriods(projectId),
  ]);

  const isDemo = Boolean(project.internal_reference?.startsWith('DEMO'));
  const totalCash = cashAccounts.reduce((sum, account) => sum + BigInt(account.balance_minor_units), 0n);
  const realizedResult = results.reduce((sum, result) => sum + BigInt(result.realized_result_minor_units), 0n);
  const openPeriod = periods.find((period) => period.status === 'OPEN') ?? null;
  const sections = sectionsFor(sector).filter((section) => section.id !== 'overview');

  return (
    <section className="stack">
      <header className={`project-context card page-header ${SECTOR_THEME_CLASS[sector]}`.trim()}>
        <div className="page-header-main">
          <Link className="back-link" href="/projects">→ المشاريع</Link>
          <div className="page-title-row">
            <h1>{project.name}</h1>
            <SectorChip sector={sector} label={SECTOR_LABEL[sector] ?? sector} />
            <StatusBadge tone={projectLifecycleTone(project.lifecycle_state)}>
              {PROJECT_LIFECYCLE_LABEL[project.lifecycle_state] ?? project.lifecycle_state}
            </StatusBadge>
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

      <div className={SECTOR_THEME_CLASS[sector]}>
        <WorkspaceNavGrouped projectId={projectId} active="overview" sector={sector} />
      </div>

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
