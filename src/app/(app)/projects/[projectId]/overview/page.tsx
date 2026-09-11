import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership, getCashAccountPositions, getObligationPositions } from '@/features/finance/queries';
import { getProjectCapitalPosition } from '@/features/funding/queries';
import { getPropertyWorkspaces, getRealEstateProfile } from '@/features/real-estate/queries';
import { getRealizedResults } from '@/features/revenue/queries';
import { getAccountingPeriods, getCloseRuns } from '@/features/close/queries';
import { getPilotAcceptanceReport } from '@/features/pilot/queries';
import { formatMinorUnits } from '@/shared/money';
import { WorkspaceChrome, ForbiddenCard } from '@/features/workspace/chrome';
import { Section } from '@/shared/ui';

export const dynamic = 'force-dynamic';

const ASSET_STATE: Record<string, string> = {
  CANDIDATE: 'مرشح',
  DUE_DILIGENCE: 'فحص نافي للجهالة',
  ACQUIRING: 'قيد الاستحواذ',
  HELD: 'مُحتفظ به / تحت السيطرة',
  DEVELOPING: 'قيد التطوير',
  EXITING: 'قيد التخارج',
  DISPOSED: 'تم التصرف',
};

const PERIOD_STATUS: Record<string, string> = { OPEN: 'مفتوحة', CLOSED: 'مغلقة' };

function d(value: string | null | undefined) {
  return value ? new Date(value).toLocaleDateString('ar-EG') : '—';
}

export default async function OverviewPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  if (project.sector === 'AGRICULTURE') redirect(`/projects/${projectId}/agriculture`);
  if (project.sector === 'LIVESTOCK') redirect(`/projects/${projectId}/livestock`);
  const organizationId = project.organization_id;
  const currency = project.reporting_currency;
  const money = (value: string | number | bigint | null | undefined) =>
    value === null || value === undefined ? '—' : formatMinorUnits(value, currency);

  const [membership, position, cashAccounts, obligations, assets, profile, results, periods, closeRuns, report] = await Promise.all([
    getCurrentMembership(organizationId),
    getProjectCapitalPosition(projectId),
    getCashAccountPositions(projectId),
    getObligationPositions(projectId),
    getPropertyWorkspaces(projectId),
    getRealEstateProfile(projectId),
    getRealizedResults(projectId),
    getAccountingPeriods(projectId),
    getCloseRuns(projectId),
    getPilotAcceptanceReport(projectId),
  ]);

  if (!membership) {
    return <ForbiddenCard projectId={projectId} message="عضويتك الحالية لا تسمح بقراءة نظرة المشروع العامة." />;
  }

  const totalCash = cashAccounts.reduce((sum, account) => sum + BigInt(account.balance_minor_units), 0n);
  const supplierPayable = obligations
    .filter((obligation) => !obligation.is_reversed && obligation.status === 'AUTHORIZED')
    .reduce((sum, obligation) => sum + BigInt(obligation.outstanding_minor_units), 0n);
  const recognizedRevenue = results.reduce((sum, result) => sum + BigInt(result.recognized_revenue_minor_units), 0n);
  const realizedResult = results.reduce((sum, result) => sum + BigInt(result.realized_result_minor_units), 0n);

  const openPeriod = periods.find((period) => period.status === 'OPEN') ?? null;
  const closedPeriods = periods.filter((period) => period.status === 'CLOSED');
  const lastClosed = closedPeriods[0] ?? null;
  const activeCloseRun = closeRuns[0] ?? null;

  const blockers: string[] = [];
  if (report && report.unresolved_critical_exceptions > 0) blockers.push(`استثناءات مطابقة حرجة غير معالجة (${report.unresolved_critical_exceptions})`);
  if (report && report.unreconciled_bank_statement_lines > 0) blockers.push(`سطور بنكية غير مطابقة (${report.unreconciled_bank_statement_lines})`);
  if (report && report.unbalanced_journal_batches > 0) blockers.push(`قيود غير متوازنة (${report.unbalanced_journal_batches})`);

  const disposed = assets.filter((asset) => asset.operational_state === 'DISPOSED').length;
  const developing = assets.filter((asset) => asset.operational_state === 'DEVELOPING' || asset.operational_state === 'HELD').length;

  return (
    <section className="stack-lg">
      <WorkspaceChrome
        projectId={projectId}
        active="overview"
        title="نظرة المشروع"
        subtitle={`${project.name} · ${currency}${profile?.strategy ? ` · ${profile.strategy}` : ''}`}
        internalReference={project.internal_reference}
        sector={project.sector}
      />

      {blockers.length > 0 && (
        <div className="banner" role="alert">
          <span>حاصرات رقابة مفتوحة:</span>
          <span>{blockers.join(' · ')}</span>
        </div>
      )}

      <Section title="الوضع المالي" description="كل مبلغ من قراءة رسمية واحدة؛ لا يُجمع رقم عبر عملات مختلفة.">
        <div className="overview-kpis">
          <article className="overview-kpi"><span>رأس المال الملتزم</span><strong className="num">{money(position?.committed_minor_units)}</strong><small>واقعة تمويل مسجلة؛ لا تعني ملكية أو حصة ربح</small></article>
          <article className="overview-kpi"><span>رأس المال المساهم به</span><strong className="num">{money(position?.contributed_minor_units)}</strong><small>مساهمات مسجلة؛ لا تُستخدم كأساس entitlement</small></article>
          <article className="overview-kpi"><span>المتبقي استلامه</span><strong className="num">{money(position?.receivable_minor_units)}</strong><small>وفق وقائع التمويل المسجلة فقط</small></article>
          <article className="overview-kpi"><span>النقدية الحالية</span><strong className="num">{formatMinorUnits(totalCash, currency)}</strong><small>مجموع أرصدة الحسابات النقدية</small></article>
          <article className={`overview-kpi${supplierPayable > 0n ? ' negative' : ''}`}><span>التزامات غير مسددة</span><strong className="num">{formatMinorUnits(supplierPayable, currency)}</strong><small>مستحقات موردين معتمدة وغير مسددة</small></article>
        </div>
      </Section>

      <Section title="الإيراد والنتيجة التشغيلية" description="الاعتراف من قيود متوازنة فقط.">
        <div className="overview-kpis">
          <article className="overview-kpi"><span>إيراد البيع المعترف به</span><strong className="num">{formatMinorUnits(recognizedRevenue, currency)}</strong><small>عبر قيود الاعتراف المتوازنة فقط</small></article>
          <article className="overview-kpi"><span>النتيجة المحققة من التصرفات</span><strong className="num">{formatMinorUnits(realizedResult, currency)}</strong><small>{results.length} تصرف معترف به · ليست حصة مستثمر</small></article>
        </div>
        <div className="banner info">
          <strong>غير محدد بسياسة معتمدة</strong> — تخصيص النتيجة على المستثمرين أو تحديد النقدية القابلة للتوزيع غير معروض هنا حتى تُحسم BD-006 وBD-008 في R14. لا يُعرض صفر ولا تقدير بديل.
        </div>
      </Section>

      <Section title="الأصول العقارية" description="الأصل الاقتصادي منفصل عن المشروع والقطعة والعقد والدفع.">
        <div className="overview-kpis">
          <article className="overview-kpi"><span>عدد الأصول</span><strong className="num">{assets.length}</strong><small>{disposed} مُتصرَّف بها · {developing} قيد التشغيل</small></article>
          <article className="overview-kpi"><span>الأصول قيد التشغيل</span><strong className="num">{assets.length - disposed}</strong><small>لم تُبع بعد</small></article>
        </div>
        {assets.length === 0 ? <p className="muted">لا توجد أصول عقارية مسجّلة بعد.</p> : (
          <div className="table-wrap"><table className="table-stackable"><caption className="sr-only">الأصول العقارية: الاسم والحالة التشغيلية والاستراتيجية</caption><thead><tr><th scope="col">الأصل</th><th scope="col">الحالة</th><th scope="col">الاستراتيجية</th></tr></thead><tbody>
            {assets.map((asset) => <tr key={asset.property_asset_id}><td data-label="الأصل">{asset.name}</td><td data-label="الحالة"><span className="status">{ASSET_STATE[asset.operational_state] ?? asset.operational_state}</span></td><td data-label="الاستراتيجية">{asset.strategy ?? '—'}</td></tr>)}
          </tbody></table></div>
        )}
      </Section>

      <Section title="الفترة المحاسبية والإغلاق" description="حالة الإغلاق وبواباته كما هي مسجلة الآن.">
        <div className="overview-kpis">
          <article className="overview-kpi"><span>الفترة الحالية</span><strong>{openPeriod ? `${d(openPeriod.start_date)} → ${d(openPeriod.end_date)}` : 'لا توجد فترة مفتوحة'}</strong><small>{openPeriod ? PERIOD_STATUS[openPeriod.status] : 'أنشئ فترة OPEN'}</small></article>
          <article className="overview-kpi"><span>آخر فترة مغلقة</span><strong>{lastClosed ? `${d(lastClosed.start_date)} → ${d(lastClosed.end_date)}` : 'لا توجد'}</strong><small>{activeCloseRun ? `آخر إغلاق: ${activeCloseRun.status}` : 'لا يوجد إغلاق'}</small></article>
          <article className="overview-kpi"><span>نقاط مطابقة موقّعة</span><strong>{report?.reconciliation_checkpoints ?? 0}</strong><small>فروق غير صفرية: {report?.reconciliation_non_zero_variances ?? 0}</small></article>
          <article className="overview-kpi"><span>مجاميع الرقابة الافتتاحية</span><strong>{report?.opening_control_totals_match == null ? '—' : report.opening_control_totals_match ? 'مطابقة' : 'غير مطابقة'}</strong><small>استيرادات مرحلة: {report?.posted_opening_imports ?? 0}</small></article>
        </div>
        <p className="muted">الانتقال إلى <Link href={`/projects/${projectId}/close`}>الإغلاق المالي</Link> · <Link href={`/projects/${projectId}/pilot`}>الاستيراد والمطابقة</Link></p>
      </Section>

      <p className="muted">
        لإدخال بيانات مشروع حقيقي عبر المسار الموجّه: <Link href={`/projects/${projectId}/intake`}>إدخال مشروع حقيقي</Link>
      </p>
    </section>
  );
}
