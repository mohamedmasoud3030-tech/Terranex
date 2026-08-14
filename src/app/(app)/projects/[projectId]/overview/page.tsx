import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership } from '@/features/finance/queries';
import {
  getCashAccountPositions,
  getObligationPositions,
} from '@/features/finance/queries';
import { getProjectCapitalPosition } from '@/features/funding/queries';
import { getPropertyWorkspaces, getRealEstateProfile } from '@/features/real-estate/queries';
import { getRealizedResults } from '@/features/revenue/queries';
import { getDistributions } from '@/features/allocation/queries';
import { getAccountingPeriods, getCloseRuns } from '@/features/close/queries';
import { getPilotAcceptanceReport } from '@/features/pilot/queries';
import { formatMinorUnits } from '@/shared/money';
import { WorkspaceChrome, ForbiddenCard } from '@/features/workspace/chrome';

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
  // Agriculture projects do not have a Real Estate overview; the
  // canonical sector landing is the agriculture workspace.
  if (project.sector === 'AGRICULTURE') redirect(`/projects/${projectId}/agriculture`);
  if (project.sector === 'LIVESTOCK') redirect(`/projects/${projectId}/livestock`);
  const organizationId = project.organization_id;
  const currency = project.reporting_currency;
  const money = (value: string | number | bigint | null | undefined) => formatMinorUnits(value ?? '0', currency);

  const [
    membership,
    position,
    cashAccounts,
    obligations,
    assets,
    profile,
    results,
    distributions,
    periods,
    closeRuns,
    report,
  ] = await Promise.all([
    getCurrentMembership(organizationId),
    getProjectCapitalPosition(projectId),
    getCashAccountPositions(projectId),
    getObligationPositions(projectId),
    getPropertyWorkspaces(projectId),
    getRealEstateProfile(projectId),
    getRealizedResults(projectId),
    getDistributions(projectId),
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
  const approvedDistributions = distributions
    .filter((distribution) => distribution.status === 'APPROVED' && !distribution.is_approval_reversed)
    .reduce((sum, distribution) => sum + BigInt(distribution.approved_amount_minor_units ?? distribution.requested_amount_minor_units), 0n);
  const paidDistributions = distributions
    .filter((distribution) => distribution.settlement_status === 'PAID' && !distribution.is_approval_reversed)
    .reduce((sum, distribution) => sum + BigInt(distribution.paid_minor_units), 0n);

  const openPeriod = periods.find((period) => period.status === 'OPEN') ?? null;
  const closedPeriods = periods.filter((period) => period.status === 'CLOSED');
  const lastClosed = closedPeriods[0] ?? null;
  const activeCloseRun = closeRuns[0] ?? null;

  const blockers: string[] = [];
  if (report && report.unresolved_critical_exceptions > 0) {
    blockers.push(`استثناءات مطابقة حرجة غير معالجة (${report.unresolved_critical_exceptions})`);
  }
  if (report && report.unreconciled_bank_statement_lines > 0) {
    blockers.push(`سطور بنكية غير مطابقة (${report.unreconciled_bank_statement_lines})`);
  }
  if (report && report.unbalanced_journal_batches > 0) {
    blockers.push(`قيود غير متوازنة (${report.unbalanced_journal_batches})`);
  }
  if (report && report.partner_capital_rollforward_breaks > 0) {
    blockers.push(`كسور في تطابق سجل رأس مال الشركاء (${report.partner_capital_rollforward_breaks})`);
  }

  const disposed = assets.filter((asset) => asset.operational_state === 'DISPOSED').length;
  const developing = assets.filter((asset) => asset.operational_state === 'DEVELOPING' || asset.operational_state === 'HELD').length;

  return (
    <section className="stack">
      <header className="project-context card">
        <div>
          <Link className="muted" href={`/projects/${projectId}`}>← مساحة المشروع</Link>
          <h1>نظرة المشروع</h1>
          <p className="muted">
            {project.name} · قطاع عقاري · {currency}
            {project.internal_reference ? ` · ${project.internal_reference}` : ''}
            {profile?.strategy ? ` · ${profile.strategy}` : ''}
          </p>
        </div>
      </header>

      {blockers.length > 0 && (
        <div className="banner" role="alert">
          <span>حاصرات رقابة مفتوحة:</span>
          <span>{blockers.join(' · ')}</span>
        </div>
      )}

      <section className="card stack">
        <h2>الوضع المالي</h2>
        <div className="overview-kpis">
          <article className="overview-kpi">
            <span>رأس المال الملتزم</span>
            <strong>{money(position?.committed_minor_units)}</strong>
            <small>الالتزام التعاقدي للمشاركين</small>
          </article>
          <article className="overview-kpi">
            <span>رأس المال المساهم به</span>
            <strong>{money(position?.contributed_minor_units)}</strong>
            <small>المساهمات النقدية المسجّلة</small>
          </article>
          <article className="overview-kpi">
            <span>المتبقي استلامه</span>
            <strong>{money(position?.receivable_minor_units)}</strong>
            <small>المطلوب ناقص المساهم</small>
          </article>
          <article className="overview-kpi">
            <span>النقدية الحالية</span>
            <strong>{formatMinorUnits(totalCash, currency)}</strong>
            <small>مجموع أرصدة الحسابات النقدية</small>
          </article>
          <article className="overview-kpi">
            <span>التزامات غير مسددة</span>
            <strong>{money(supplierPayable)}</strong>
            <small>مستحقات موردين معتمدة وغير مسددة</small>
          </article>
        </div>
      </section>

      <section className="card stack">
        <h2>الإيراد والنتيجة</h2>
        <div className="overview-kpis">
          <article className="overview-kpi">
            <span>إيراد البيع المعترف به</span>
            <strong>{money(recognizedRevenue)}</strong>
            <small>عبر قيود الاعتراف المتوازنة فقط</small>
          </article>
          <article className="overview-kpi negative">
            <span>النتيجة المحققة</span>
            <strong>{money(realizedResult)}</strong>
            <small>{results.length} تصرف معترف به</small>
          </article>
          <article className="overview-kpi">
            <span>توزيعات معتمدة</span>
            <strong>{money(approvedDistributions)}</strong>
            <small>قرارات التوزيع المعتمدة</small>
          </article>
          <article className="overview-kpi">
            <span>توزيعات مدفوعة</span>
            <strong>{money(paidDistributions)}</strong>
            <small>المستحق المسدّد نقدًا</small>
          </article>
        </div>
      </section>

      <section className="card stack">
        <h2>الأصول العقارية</h2>
        <div className="overview-kpis">
          <article className="overview-kpi">
            <span>عدد الأصول</span>
            <strong>{assets.length}</strong>
            <small>{disposed} مُتصرَّف بها · {developing} قيد التشغيل</small>
          </article>
          <article className="overview-kpi">
            <span>الأصول قيد التشغيل</span>
            <strong>{assets.length - disposed}</strong>
            <small>لم تُباع بعد</small>
          </article>
        </div>
        {assets.length === 0 ? (
          <p className="muted">لا توجد أصول عقارية مسجّلة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>الأصل</th><th>الحالة</th><th>الاستراتيجية</th></tr></thead>
              <tbody>
                {assets.map((asset) => (
                  <tr key={asset.property_asset_id}>
                    <td>{asset.name}</td>
                    <td><span className="status">{ASSET_STATE[asset.operational_state] ?? asset.operational_state}</span></td>
                    <td>{asset.strategy ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="card stack">
        <h2>الفترة المحاسبية والإغلاق</h2>
        <div className="overview-kpis">
          <article className="overview-kpi">
            <span>الفترة الحالية</span>
            <strong>{openPeriod ? `${d(openPeriod.start_date)} → ${d(openPeriod.end_date)}` : 'لا توجد فترة مفتوحة'}</strong>
            <small>{openPeriod ? PERIOD_STATUS[openPeriod.status] : 'أنشئ فترة OPEN'}</small>
          </article>
          <article className="overview-kpi">
            <span>آخر فترة مغلقة</span>
            <strong>{lastClosed ? `${d(lastClosed.start_date)} → ${d(lastClosed.end_date)}` : 'لا توجد'}</strong>
            <small>{activeCloseRun ? `آخر إغلاق: ${activeCloseRun.status}` : 'لا يوجد إغلاق'}</small>
          </article>
          <article className="overview-kpi">
            <span>نقاط مطابقة موقّعة</span>
            <strong>{report?.reconciliation_checkpoints ?? 0}</strong>
            <small>فروق غير صفرية: {report?.reconciliation_non_zero_variances ?? 0}</small>
          </article>
          <article className="overview-kpi">
            <span>مجاميع الرقابة الافتتاحية</span>
            <strong>{report?.opening_control_totals_match == null ? '—' : report.opening_control_totals_match ? 'مطابقة' : 'غير مطابقة'}</strong>
            <small>استيرادات مرحلة: {report?.posted_opening_imports ?? 0}</small>
          </article>
        </div>
        <p className="muted">
          الانتقال إلى <Link href={`/projects/${projectId}/close`}>الإغلاق المالي والتوزيع</Link> ·
          <Link href={`/projects/${projectId}/pilot`}> الاستيراد والمطابقة</Link>
        </p>
      </section>

      <section className="card stack">
        <h2>روابط التشغيل</h2>
        <p className="muted">إدارة المشروع كاملة من مساحة العمل. لكل قسم مسار تشغيلي واحد مرتبط بالأوامر الرسمية للمنتج.</p>
        <nav className="context-nav">
          <Link href={`/projects/${projectId}/funding`}>رأس المال</Link>
          <Link href={`/projects/${projectId}/operations`}>الأصول العقارية</Link>
          <Link href={`/projects/${projectId}/costs`}>التكاليف والنقدية</Link>
          <Link href={`/projects/${projectId}/revenue`}>الإيراد والبيع</Link>
          <Link href={`/projects/${projectId}/close`}>الإغلاق والتوزيع</Link>
          <Link href={`/projects/${projectId}/statements`}>كشوف الشركاء</Link>
          <Link href={`/projects/${projectId}/pilot`}>الاستيراد والمطابقة</Link>
          <Link href={`/projects/${projectId}/controls`}>الرقابة والجاهزية</Link>
          <Link href={`/projects/${projectId}/intake`}>إدخال مشروع حقيقي</Link>
        </nav>
      </section>
    </section>
  );
}
