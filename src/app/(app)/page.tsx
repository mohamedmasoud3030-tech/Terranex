import Link from 'next/link';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { getPortfolios } from '@/features/portfolios/queries';
import { getRegisteredAssets, getSectorPerformance } from '@/features/assets/queries';
import { getIntegritySignals, getOrganizationConsolidation } from '@/features/control/queries';
import { sectorLandingHref } from '@/features/workspace/nav';
import { SECTOR_LABEL } from '@/features/agriculture/labels';
import { formatMinorUnits } from '@/shared/money';
import { SEVERITY_LABEL, severityTone } from '@/features/projects/labels';
import { EmptyState, PageHeader, Section, Stat, StatGrid, StatusBadge } from '@/shared/ui';

const FX_STATUS_AR: Record<string, string> = {
  CONSOLIDATED_AT_RATE: 'مجمّع بسعر صرف مسجل',
  CONSOLIDATION_INCOMPLETE_NO_RATE_SNAPSHOT: 'التجميع غير مكتمل: سعر صرف مفقود',
  NO_REPORTING_CURRENCY: 'لم تُحدد عملة تقرير للمنظمة',
};

export default async function Home() {
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
  const [projects, portfolios, assets, sectorPerformance, consolidation, integritySignals] =
    await Promise.all([
      getProjects(org.id),
      getPortfolios(org.id),
      getRegisteredAssets(org.id),
      getSectorPerformance(org.id),
      getOrganizationConsolidation(org.id),
      getIntegritySignals(org.id),
    ]);

  const consolidated = consolidation.find((row) => row.level === 'CONSOLIDATED') ?? null;
  const canShowConsolidatedMoney =
    consolidated?.fx_status === 'CONSOLIDATED_AT_RATE' &&
    consolidated.org_reporting_currency !== null;
  const reportingCurrency = consolidated?.org_reporting_currency ?? null;
  const integritySubjects = integritySignals.reduce((sum, signal) => sum + signal.subject_count, 0);
  const criticalSignals = integritySignals.filter((signal) => signal.severity === 'CRITICAL');

  return (
    <section className="stack">
      <PageHeader
        eyebrow={org.name}
        title="لوحة الإدارة التنفيذية"
        description="ملخص تشغيلي ومالي من الحقائق المسجلة فقط، بدون أرقام تقديرية أو تجميع عملات غير مكتمل."
        actions={
          <>
            <Link className="button" href="/projects/new">مشروع جديد</Link>
            <Link className="button secondary" href="/intake">إدخال مشروع حقيقي (مسار موجّه)</Link>
          </>
        }
      />

      <StatGrid label="ملخص المحفظة التشغيلية">
        <Stat label="المحافظ الاستثمارية" value={portfolios.length} hint="فتح المحافظ" href="/portfolios" />
        <Stat label="المشاريع" value={projects.length} hint="فتح المشاريع" href="/projects" />
        <Stat label="الأصول المسجلة عبر القطاعات" value={assets.length} hint="فتح سجل الأصول" href="/assets" />
        <Stat
          label="موضوعات سلامة البيانات المفتوحة"
          value={integritySubjects}
          tone={criticalSignals.length ? 'negative' : undefined}
          hint={criticalSignals.length ? `${criticalSignals.length} إشارات حرجة` : 'لا توجد إشارة حرجة مسجلة'}
        />
      </StatGrid>

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
                <small>من حقيقة المشروع إلى المنظمة</small>
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
            <p className="muted">كل صف يحتفظ بعملته الأصلية؛ المصروفات تظهر منفصلة عن النتيجة المحققة.</p>
          </div>
          <Link className="button secondary" href="/assets">الأصول والأداء</Link>
        </div>
        {sectorPerformance.length === 0 ? (
          <p className="muted">لا توجد حقائق مالية قطاعية مسجلة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th>القطاع</th>
                  <th>المشاريع</th>
                  <th>الأصول</th>
                  <th>النقدية</th>
                  <th>الإيراد المعترف به</th>
                  <th>تكلفة المبيعات</th>
                  <th>المصروفات</th>
                  <th>النتيجة المحققة*</th>
                </tr>
              </thead>
              <tbody>
                {sectorPerformance.map((row) => (
                  <tr key={`${row.sector}-${row.currency}`}>
                    <td data-label="القطاع">{SECTOR_LABEL[row.sector] ?? row.sector}</td>
                    <td data-label="المشاريع">{row.project_count}</td>
                    <td data-label="الأصول">{row.asset_count}</td>
                    <td data-label="النقدية">{formatMinorUnits(row.cash_balance_minor_units, row.currency)}</td>
                    <td data-label="الإيراد المعترف به">{formatMinorUnits(row.revenue_recognized_minor_units, row.currency)}</td>
                    <td data-label="تكلفة المبيعات">{formatMinorUnits(row.cost_of_sale_minor_units, row.currency)}</td>
                    <td data-label="المصروفات">{formatMinorUnits(row.expense_posted_minor_units, row.currency)}</td>
                    <td data-label="النتيجة المحققة*">{formatMinorUnits(row.realized_result_minor_units, row.currency)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="muted">* النتيجة المحققة هنا = الإيراد المعترف به − تكلفة المبيعات وفق read model الحالي؛ المصروفات التشغيلية معروضة في عمود مستقل وليست مضمّنة في هذا الرقم.</p>
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
                  <StatusBadge tone={severityTone(signal.severity)}>{SEVERITY_LABEL[signal.severity] ?? signal.severity}</StatusBadge>
                  <p>{signal.subject_count} موضوع</p>
                </div>
              </div>
            ))}
          </div>
        </section>
      ) : null}

      <Section
        title="المشاريع الاستثمارية"
        description="كل مشروع يحتفظ بدورته وأصوله ودفتره المالي بشكل مستقل."
        actions={<Link className="button secondary sm" href="/projects">كل المشاريع</Link>}
      >
        {projects.length === 0 ? (
          <EmptyState
            title="لا توجد مشاريع بعد"
            description="أدخل أول مشروع عبر المسار الموجّه. لن نعرض أرقامًا أو بيانات تجريبية."
            action={<Link className="button" href="/intake">بدء إدخال المشروع</Link>}
          />
        ) : (
          <ul className="link-list" aria-label="أحدث المشاريع">
            {projects.slice(0, 6).map((project) => (
              <li key={project.id}>
                <Link href={sectorLandingHref(project.sector, project.id)}>
                  <strong>{project.name}</strong>
                  <span className="muted">{project.internal_reference || 'بدون مرجع داخلي'}</span>
                  <StatusBadge>{SECTOR_LABEL[project.sector] ?? project.sector} · {project.reporting_currency}</StatusBadge>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </Section>
    </section>
  );
}
