import Link from 'next/link';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { getPortfolios } from '@/features/portfolios/queries';
import { getRegisteredAssets, getSectorPerformance } from '@/features/assets/queries';
import { getIntegritySignals, getOrganizationConsolidation } from '@/features/control/queries';
import { getSectorManagementResult } from '@/features/result/queries';
import {
  qualifiedResultViewFromRow,
  presentQualifiedResult,
  unclassifiedCaveatAr,
  RESULT_TERM_AR,
  type QualifiedResultView,
} from '@/features/result/qualified-result';
import { sectorLandingHref } from '@/features/workspace/nav';
import { SECTOR_LABEL } from '@/features/agriculture/labels';
import { formatMinorUnits } from '@/shared/money';

const FX_STATUS_AR: Record<string, string> = {
  CONSOLIDATED_AT_RATE: 'مجمّع بسعر صرف مسجل',
  CONSOLIDATION_INCOMPLETE_NO_RATE_SNAPSHOT: 'التجميع غير مكتمل: سعر صرف مفقود',
  NO_REPORTING_CURRENCY: 'لم تُحدد عملة تقرير للمنظمة',
};

export default async function Home() {
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
  const [
    projects,
    portfolios,
    assets,
    sectorPerformance,
    sectorResultRows,
    consolidation,
    integritySignals,
  ] = await Promise.all([
    getProjects(org.id),
    getPortfolios(org.id),
    getRegisteredAssets(org.id),
    getSectorPerformance(org.id),
    getSectorManagementResult(org.id),
    getOrganizationConsolidation(org.id),
    getIntegritySignals(org.id),
  ]);

  // A qualified result that does not satisfy the ADR 0034 contract is never
  // rendered as a number. Collect the failures and say so, rather than taking
  // down the panels that are fine.
  const resultBySector = new Map<string, QualifiedResultView>();
  const resultRowBySector = new Map(
    sectorResultRows.map((row) => [`${row.sector}-${row.currency}`, row]),
  );
  let resultContractError: string | null = null;
  for (const row of sectorResultRows) {
    try {
      resultBySector.set(`${row.sector}-${row.currency}`, qualifiedResultViewFromRow(row));
    } catch (error) {
      resultContractError = error instanceof Error ? error.message : String(error);
    }
  }

  const consolidated = consolidation.find((row) => row.level === 'CONSOLIDATED') ?? null;
  const canShowConsolidatedMoney =
    consolidated?.fx_status === 'CONSOLIDATED_AT_RATE' &&
    consolidated.org_reporting_currency !== null;
  const reportingCurrency = consolidated?.org_reporting_currency ?? null;
  const integritySubjects = integritySignals.reduce((sum, signal) => sum + signal.subject_count, 0);
  const criticalSignals = integritySignals.filter((signal) => signal.severity === 'CRITICAL');

  return (
    <section className="stack">
      <div className="top">
        <div>
          <p className="muted">{org.name}</p>
          <h1>لوحة الإدارة التنفيذية</h1>
          <p className="muted">ملخص تشغيلي ومالي من الحقائق المسجلة فقط، بدون أرقام تقديرية أو تجميع عملات غير مكتمل.</p>
        </div>
        <div className="stack" style={{ justifyItems: 'end' }}>
          <Link className="button" href="/intake">إدخال مشروع حقيقي</Link>
          <Link className="button secondary" href="/projects/new">مشروع جديد</Link>
        </div>
      </div>

      <div className="overview-kpis" aria-label="ملخص المحفظة التشغيلية">
        <Link className="overview-kpi" href="/portfolios">
          <span>المحافظ الاستثمارية</span>
          <strong>{portfolios.length}</strong>
          <small>فتح المحافظ</small>
        </Link>
        <Link className="overview-kpi" href="/projects">
          <span>المشاريع</span>
          <strong>{projects.length}</strong>
          <small>فتح المشاريع</small>
        </Link>
        <Link className="overview-kpi" href="/assets">
          <span>الأصول المسجلة عبر القطاعات</span>
          <strong>{assets.length}</strong>
          <small>فتح سجل الأصول</small>
        </Link>
        <div className={`overview-kpi${criticalSignals.length ? ' negative' : ''}`}>
          <span>موضوعات سلامة البيانات المفتوحة</span>
          <strong>{integritySubjects}</strong>
          <small>{criticalSignals.length ? `${criticalSignals.length} إشارات حرجة` : 'لا توجد إشارة حرجة مسجلة'}</small>
        </div>
      </div>

      {consolidated ? (
        <section className="card stack" aria-labelledby="consolidated-heading">
          <div className="section-heading">
            <div>
              <h2 id="consolidated-heading">الموقف المالي على مستوى المنظمة</h2>
              <p className="muted">
                {FX_STATUS_AR[consolidated.fx_status] ?? consolidated.fx_status}
                {reportingCurrency ? ` · عملة التقرير ${reportingCurrency}` : ''}
              </p>
            </div>
          </div>
          {canShowConsolidatedMoney && reportingCurrency ? (
            <div className="overview-kpis">
              <div className="overview-kpi">
                <span>النقدية</span>
                <strong>{consolidated.converted_cash_balance_minor_units === null ? '—' : formatMinorUnits(consolidated.converted_cash_balance_minor_units, reportingCurrency)}</strong>
                <small>بعد التحويل المعتمد</small>
              </div>
              <div className="overview-kpi">
                <span>الموردون / الالتزامات المفتوحة</span>
                <strong>{consolidated.converted_payable_open_minor_units === null ? '—' : formatMinorUnits(consolidated.converted_payable_open_minor_units, reportingCurrency)}</strong>
                <small>{consolidated.overdue_obligations} التزامات متأخرة</small>
              </div>
              <div className="overview-kpi">
                <span>المدفوع</span>
                <strong>{consolidated.converted_paid_minor_units === null ? '—' : formatMinorUnits(consolidated.converted_paid_minor_units, reportingCurrency)}</strong>
                <small>إجمالي مدفوع محوّل</small>
              </div>
              <div className="overview-kpi">
                <span>مشاريع داخلة في التجميع</span>
                <strong>{consolidated.project_count}</strong>
                <small>Project truth → Organization</small>
              </div>
            </div>
          ) : (
            <div className="banner info">
              لا نعرض إجماليًا نقديًا موحدًا حتى تتوفر عملة تقرير وسعر صرف صالح لكل مشروع مطلوب تحويله. التفاصيل حسب العملة والقطاع ظاهرة أدناه.
            </div>
          )}
        </section>
      ) : null}

      <section className="card stack" aria-labelledby="sector-performance-heading">
        <div className="section-heading">
          <div>
            <h2 id="sector-performance-heading">أداء القطاعات</h2>
            <p className="muted">
              كل صف يحتفظ بعملته الأصلية. {RESULT_TERM_AR} تظهر بأساسها القطاعي وحالة تصنيف
              تكلفتها؛ لا يُعرض رقم بلا أساس.
            </p>
          </div>
          <Link className="button secondary" href="/assets">الأصول والأداء</Link>
        </div>
        {resultContractError ? (
          <div className="banner info">
            تعذّر قراءة عقد النتيجة المؤهَّلة لأحد القطاعات، ولم نعرض رقمًا بديلًا: {resultContractError}
          </div>
        ) : null}
        {sectorPerformance.length === 0 ? (
          <p className="muted">لا توجد حقائق مالية قطاعية مسجلة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>القطاع</th>
                  <th>المشاريع</th>
                  <th>الأصول</th>
                  <th>النقدية</th>
                  <th>الإيراد المعترف به</th>
                  <th>تكلفة مُصنَّفة مخصومة</th>
                  <th>تكلفة تشغيل غير مُصنَّفة</th>
                  <th>{RESULT_TERM_AR}</th>
                </tr>
              </thead>
              <tbody>
                {sectorPerformance.map((row) => {
                  const key = `${row.sector}-${row.currency}`;
                  const sectorResult = resultBySector.get(key);
                  const presentation = sectorResult ? presentQualifiedResult(sectorResult) : null;
                  const caveat = sectorResult ? unclassifiedCaveatAr(sectorResult) : null;
                  return (
                    <tr key={key}>
                      <td>{SECTOR_LABEL[row.sector] ?? row.sector}</td>
                      <td>{row.project_count}</td>
                      <td>{row.asset_count}</td>
                      <td>{formatMinorUnits(row.cash_balance_minor_units, row.currency)}</td>
                      <td>{formatMinorUnits(row.revenue_recognized_minor_units, row.currency)}</td>
                      <td>
                        {sectorResult
                          ? formatMinorUnits(
                              resultRowBySector.get(key)?.classified_deducted_minor_units ?? '0',
                              sectorResult.currency,
                            )
                          : '—'}
                      </td>
                      <td
                        className={
                          sectorResult?.unclassifiedMinorUnits &&
                          /^[1-9]/.test(sectorResult.unclassifiedMinorUnits)
                            ? 'unclassified-cost'
                            : undefined
                        }
                      >
                        {sectorResult?.unclassifiedMinorUnits
                          ? formatMinorUnits(sectorResult.unclassifiedMinorUnits, sectorResult.currency)
                          : '—'}
                      </td>
                      <td>
                        {presentation === null ? (
                          <span className="muted">—</span>
                        ) : presentation.kind === 'SUPPRESSED' ? (
                          <>
                            <strong className="result-suppressed">لا نعرض نتيجة</strong>
                            <p className="muted">{presentation.reasonAr}</p>
                            <p className="muted">{presentation.captionAr}</p>
                          </>
                        ) : (
                          <>
                            <strong
                              className={presentation.tone === 'caution' ? 'result-caution' : undefined}
                            >
                              {presentation.amountText}
                            </strong>
                            <p className="muted">{presentation.captionAr}</p>
                            {caveat ? <p className="unclassified-note">{caveat}</p> : null}
                          </>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        <p className="muted">
          {RESULT_TERM_AR} مقياس إداري على أساس قطاعي معلن: العقار = نتيجة التصرفات المحققة +
          الإيجار − التكلفة المنسوبة للأصل (عدا تكاليف البيع المخصومة داخل نتيجة التصرف) − المصروف
          المُعلن؛ الزراعة والماشية = إيراد البيع − التكلفة المنسوبة للدورات أو القطعان − المصروف
          المُعلن. ليست ربحًا ولا عائدًا للمستثمر، ولا تتضمن تقييمًا أو مضاعفات.
        </p>
        <p className="muted">
          الرقم القديم «النتيجة المحققة» كان يخصم تكلفة المبيعات للعقار فقط، فيظهر إيراد الزراعة
          والماشية وكأنه نتيجة صافية. أُزيل من المقارنة ولم يُعتمد عليه.
        </p>
      </section>

      {integritySignals.length ? (
        <section className="card stack" aria-labelledby="integrity-heading">
          <div className="section-heading">
            <div>
              <h2 id="integrity-heading">إشارات السلامة والاستثناءات</h2>
              <p className="muted">إشارات رقابية ناتجة من read models المالية، وليست تنبؤات.</p>
            </div>
          </div>
          <div className="milestones">
            {integritySignals.slice(0, 8).map((signal) => (
              <div className="milestone" key={`${signal.signal_code}-${signal.project_id ?? 'org'}-${signal.currency ?? 'none'}`}>
                <div>
                  <strong>{signal.signal_label_ar}</strong>
                  <p className="muted">{signal.signal_code}</p>
                </div>
                <div>
                  <span className="status">{signal.severity}</span>
                  <p>{signal.subject_count} موضوع</p>
                </div>
              </div>
            ))}
          </div>
        </section>
      ) : null}

      <section className="card stack" aria-labelledby="projects-heading">
        <div className="section-heading">
          <div>
            <h2 id="projects-heading">المشاريع الاستثمارية</h2>
            <p className="muted">كل مشروع يحتفظ بدورته وأصوله ودفتره المالي بشكل مستقل.</p>
          </div>
          <Link className="button secondary" href="/projects">كل المشاريع</Link>
        </div>
        {projects.length === 0 ? (
          <section className="stack empty">
            <h3>لا توجد مشاريع بعد</h3>
            <p className="muted">أدخل أول مشروع عبر المسار الموجّه. لن نعرض أرقامًا أو بيانات تجريبية.</p>
            <Link className="button" href="/intake">بدء إدخال المشروع</Link>
          </section>
        ) : (
          <div className="grid">
            {projects.slice(0, 6).map((project) => (
              <Link key={project.id} href={sectorLandingHref(project.sector, project.id)} className="project">
                <strong>{project.name}</strong>
                <p className="muted">{project.internal_reference || 'بدون مرجع داخلي'}</p>
                <span className="status">
                  {SECTOR_LABEL[project.sector] ?? project.sector} · {project.reporting_currency}
                </span>
              </Link>
            ))}
          </div>
        )}
      </section>
    </section>
  );
}
