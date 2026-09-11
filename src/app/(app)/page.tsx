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
import {
  EmptyState,
  Figure,
  PageHeader,
  SectorChip,
  Section,
  Stat,
  StatGrid,
  StatusBadge,
} from '@/shared/ui';

const FX_STATUS_AR: Record<string, string> = {
  CONSOLIDATED_AT_RATE: 'مجمّع بسعر صرف مسجل',
  CONSOLIDATION_INCOMPLETE_NO_RATE_SNAPSHOT: 'التجميع غير مكتمل: سعر صرف مفقود',
  NO_REPORTING_CURRENCY: 'لم تُحدد عملة تقرير للمنظمة',
};

/**
 * Executive home. Decision order, not decoration order:
 *   1. what the organization holds (stat grid)
 *   2. what needs the owner's attention (integrity signals — raised above the
 *      money because an unattended exception invalidates the money)
 *   3. the consolidated financial position, with its FX basis stated
 *   4. sector performance, each row in its own currency
 *   5. the projects themselves
 *
 * Every figure keeps its basis visible. No total is shown without saying what
 * it was computed from and in which currency.
 */
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
    <section className="stack-lg">
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

      {/* Attention before money: an unresolved exception means the figures
          below may not be trustworthy yet. */}
      {integritySignals.length ? (
        <Section
          title="يحتاج انتباهك — إشارات السلامة والاستثناءات"
          description="إشارات رقابية ناتجة من read models المالية، وليست تنبؤات."
        >
          <div className="milestones">
            {integritySignals.slice(0, 8).map((signal) => (
              <div className="milestone" key={`${signal.signal_code}-${signal.project_id ?? 'org'}-${signal.currency ?? 'none'}`}>
                <div>
                  <strong>{signal.signal_label_ar}</strong>
                  <p className="muted">
                    <code>{signal.signal_code}</code>
                    {signal.currency ? ` · ${signal.currency}` : ''}
                  </p>
                </div>
                <div>
                  <StatusBadge tone={severityTone(signal.severity)}>
                    {SEVERITY_LABEL[signal.severity] ?? signal.severity}
                  </StatusBadge>
                  <p>{signal.subject_count} موضوع</p>
                </div>
              </div>
            ))}
          </div>
          {integritySignals.length > 8 ? (
            <p className="muted">
              معروض أول 8 إشارات من {integritySignals.length}.{' '}
              <Link href="/projects">افتح المشروع المعني لعرض كل الإشارات</Link>.
            </p>
          ) : null}
        </Section>
      ) : null}

      {consolidated ? (
        <Section
          title="الموقف المالي على مستوى المنظمة"
          description={`${FX_STATUS_AR[consolidated.fx_status] ?? consolidated.fx_status}${
            reportingCurrency ? ` · عملة التقرير ${reportingCurrency}` : ''
          }`}
        >
          {canShowConsolidatedMoney && reportingCurrency ? (
            <div className="overview-kpis">
              <Figure
                basis="النقدية"
                value={consolidated.converted_cash_balance_minor_units === null ? '—' : formatMinorUnits(consolidated.converted_cash_balance_minor_units, reportingCurrency)}
                asOf="بعد التحويل المعتمد"
              />
              <Figure
                basis="الموردون / الالتزامات المفتوحة"
                value={consolidated.converted_payable_open_minor_units === null ? '—' : formatMinorUnits(consolidated.converted_payable_open_minor_units, reportingCurrency)}
                asOf={`${consolidated.overdue_obligations} التزامات متأخرة`}
                negative={consolidated.overdue_obligations > 0}
              />
              <Figure
                basis="المدفوع"
                value={consolidated.converted_paid_minor_units === null ? '—' : formatMinorUnits(consolidated.converted_paid_minor_units, reportingCurrency)}
                asOf="إجمالي مدفوع محوّل"
              />
              <Figure
                basis="مشاريع داخلة في التجميع"
                value={consolidated.project_count}
                asOf="من حقيقة المشروع إلى المنظمة"
              />
            </div>
          ) : (
            <div className="banner info">
              لا نعرض إجماليًا نقديًا موحدًا حتى تتوفر عملة تقرير وسعر صرف صالح لكل مشروع مطلوب تحويله. التفاصيل حسب العملة والقطاع ظاهرة أدناه.
            </div>
          )}
        </Section>
      ) : null}

      <Section
        title="أداء القطاعات"
        description="كل صف يحتفظ بعملته الأصلية؛ المصروفات تظهر منفصلة عن النتيجة المحققة."
        actions={<Link className="button secondary sm" href="/assets">الأصول والأداء</Link>}
      >
        {sectorPerformance.length === 0 ? (
          <p className="muted">لا توجد حقائق مالية قطاعية مسجلة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">
                أداء القطاعات: عدد المشاريع والأصول والنقدية والإيراد المعترف به وتكلفة المبيعات والمصروفات والنتيجة المحققة، لكل قطاع بعملته الأصلية
              </caption>
              <thead>
                <tr>
                  <th scope="col">القطاع</th>
                  <th scope="col" className="num">المشاريع</th>
                  <th scope="col" className="num">الأصول</th>
                  <th scope="col" className="num">النقدية</th>
                  <th scope="col" className="num">الإيراد المعترف به</th>
                  <th scope="col" className="num">تكلفة المبيعات</th>
                  <th scope="col" className="num">المصروفات</th>
                  <th scope="col" className="num">النتيجة المحققة*</th>
                </tr>
              </thead>
              <tbody>
                {sectorPerformance.map((row) => (
                  <tr key={`${row.sector}-${row.currency}`}>
                    <td data-label="القطاع">
                      <SectorChip sector={row.sector} label={SECTOR_LABEL[row.sector] ?? row.sector} />
                      <br />
                      <small className="muted">{row.currency}</small>
                    </td>
                    <td className="num" data-label="المشاريع">{row.project_count}</td>
                    <td className="num" data-label="الأصول">{row.asset_count}</td>
                    <td className="num" data-label="النقدية">{formatMinorUnits(row.cash_balance_minor_units, row.currency)}</td>
                    <td className="num" data-label="الإيراد المعترف به">{formatMinorUnits(row.revenue_recognized_minor_units, row.currency)}</td>
                    <td className="num" data-label="تكلفة المبيعات">{formatMinorUnits(row.cost_of_sale_minor_units, row.currency)}</td>
                    <td className="num" data-label="المصروفات">{formatMinorUnits(row.expense_posted_minor_units, row.currency)}</td>
                    <td className="num" data-label="النتيجة المحققة*">{formatMinorUnits(row.realized_result_minor_units, row.currency)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="muted">* النتيجة المحققة هنا = الإيراد المعترف به − تكلفة المبيعات وفق read model الحالي؛ المصروفات التشغيلية معروضة في عمود مستقل وليست مضمّنة في هذا الرقم.</p>
      </Section>

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
                  <SectorChip sector={project.sector} label={SECTOR_LABEL[project.sector] ?? project.sector} />
                  <span className="status">{project.reporting_currency}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </Section>
    </section>
  );
}
