import { TaxRegistryTable } from '@/features/control/tax-registry-table';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { newCommandNonce } from '@/shared/idempotency';
import { WorkspaceChrome } from '@/features/workspace/chrome';
import { Section, StatusBadge } from '@/shared/ui';
import { RECORD_STATUS_LABEL, severityTone } from '@/features/projects/labels';
import { formatMinorUnits } from '@/shared/money';
import { isRenderableCurrency } from '@/shared/money/by-currency';
import { getCurrentMembership } from '@/features/finance/queries';
import {
  getApprovalExceptions,
  getApprovalPolicies,
  getBudgetConsumption,
  getFxConversionLog,
  getFxSnapshots,
  getIntegritySignals,
  getOrganizationConsolidation,
  getOrganizationReportingCurrency,
  getProjectPosition,
  getTaxRegistry,
} from '@/features/control/queries';
import {
  ApprovalPolicyForm,
  DecideExceptionForm,
  ResubmitExceptionForm,
  FxConversionForm,
  FxSnapshotForm,
  OpenExceptionForm,
  OrgReportingCurrencyForm,
  TaxTreatmentForm,
} from './forms';

export const dynamic = 'force-dynamic';

/**
 * مبلغ صف يُعرض بعملته المسجّلة فقط.
 *
 * كانت هذه الصفحة تعرض صفوفًا بلا عملة معلنة موسومةً بعملة المشروع
 * (`signal.currency ?? project.reporting_currency`)، وهو ما يجعل مبلغًا معلومًا
 * يبدو وكأنه مقوّم بعملة لم تُسجَّل له. الأمان هنا بنيوي: غياب عملة الصف تعني
 * غياب الوحدة، فلا يُستعار شيء ولا يُخترع رقم.
 */
function moneyCell(amount: string | null, rowCurrency: string | null): string {
  if (!amount) return '—';
  // لا توجد عملة مفترضة: مبلغ بلا عملة معلنة لا يُنسب إلى عملة المشروع.
  if (!rowCurrency) return '— (مبلغ بلا عملة معلنة)';
  if (!isRenderableCurrency(rowCurrency)) return `— (${amount} بعملة غير مدعومة: ${rowCurrency})`;
  return formatMinorUnits(amount, rowCurrency);
}

const SEVERITY_LABEL: Record<string, { label: string; className: string }> = {
  CRITICAL: { label: 'حرج', className: 'severity-critical' },
  WARNING: { label: 'تنبيه', className: 'severity-warning' },
  INFO: { label: 'معلومة', className: 'severity-info' },
};

const FX_STATUS_LABEL: Record<string, string> = {
  NO_REPORTING_CURRENCY: 'لا توجد عملة تقارير معلنة',
  NO_RATE_SNAPSHOT: 'لا توجد لقطة سعر مسجلة',
  CONSOLIDATION_INCOMPLETE_NO_RATE_SNAPSHOT: 'توحيد غير مكتمل: لقطة سعر ناقصة',
  CONSOLIDATED_AT_RATE: 'موحد بسعر مسجل',
  CONVERTED_AT_RATE: 'محول بسعر مسجل',
  SAME_CURRENCY: 'نفس العملة',
};

export default async function IntegrityPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;
  // عملة تقارير المشروع تبقى للعرض السياقي فقط (ترويسة الصفحة). كل مبلغ قادم
  // من قراءة مالية يحمل عملته الخاصة ولا يُوسم بعملة المشروع.
  const reportingCurrency = project.reporting_currency;

  const [
    membership,
    position,
    signals,
    policies,
    exceptions,
    snapshots,
    conversions,
    taxRegistry,
    orgReportingCurrency,
    consolidation,
    consumption,
  ] = await Promise.all([
    getCurrentMembership(organizationId),
    getProjectPosition(projectId),
    getIntegritySignals(organizationId),
    getApprovalPolicies(organizationId),
    getApprovalExceptions(projectId),
    getFxSnapshots(organizationId),
    getFxConversionLog(organizationId),
    getTaxRegistry(organizationId),
    getOrganizationReportingCurrency(organizationId),
    getOrganizationConsolidation(organizationId),
    getBudgetConsumption(projectId),
  ]);
  const isOwner = membership?.role === 'OWNER';

  const projectSignals = signals.filter((s) => s.project_id === projectId);
  const orgSignals = signals.filter((s) => s.project_id === null);

  const exceptionSubjects = [
    ...consumption
      .filter((c) => c.status === 'APPROVED')
      .map((c) => ({ type: 'project_budget_line', id: c.budget_line_id, label: `بند موازنة (${c.cost_treatment} · إصدار ${c.version})` })),
    ...exceptions
      .filter((e) => e.subject_type !== 'none' && e.subject_id)
      .map((e) => ({ type: e.subject_type, id: e.subject_id as string, label: `${e.exception_kind} (${e.subject_type})` })),
  ].filter((subject, index, list) => list.findIndex((s) => s.type === subject.type && s.id === subject.id) === index);

  const critical = projectSignals.filter((s) => s.severity === 'CRITICAL').length;
  const warnings = projectSignals.filter((s) => s.severity === 'WARNING').length;

  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="integrity"
        title="مركز النزاهة المالية"
        subtitle={`${project.name} · ${reportingCurrency}`}
        internalReference={project.internal_reference}
        sector={project.sector}
      />

      <section className="grid">
        <div className="card">
          <p className="muted">إشارات حرجة</p>
          <strong>{critical}</strong>
        </div>
        <div className="card">
          <p className="muted">إشارات تنبيه</p>
          <strong>{warnings}</strong>
        </div>
        <div className="card">
          <p className="muted">التزامات متنازع عليها</p>
          <strong>{position?.disputed_obligations ?? 0}</strong>
        </div>
        <div className="card">
          <p className="muted">التزامات متأخرة</p>
          <strong>{position?.overdue_obligations ?? 0}</strong>
        </div>
      </section>

      {position ? (
                <Section
          title="الوضع المالي الرسمي (من القيود المرحّلة فقط)"
          description={`نطاق هذا الجدول عملة تقارير المشروع (${position.currency}) فقط: العرض يجمع القيود المُرحّلة المقومة بها ويستبعد ما رُحّل بعملة أخرى. للأرقام لكل عملة على حدة استخدم ملخصات النقدية ورأس المال والنتيجة.`}
        >
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: العملة · النقدية · ذمم مفتوحة · إيراد معترف به · مصروفات مرحّلة · أعمال تحت التطوير · مستحقات مفتوحة · المدفوع · حجز ضمان قائم</caption>
              <thead>
                <tr>
                  <th scope="col">العملة</th>
                  <th scope="col" className="num">النقدية</th>
                  <th scope="col" className="num">ذمم مفتوحة</th>
                  <th scope="col" className="num">إيراد معترف به</th>
                  <th scope="col">مصروفات مرحّلة</th>
                  <th scope="col">أعمال تحت التطوير</th>
                  <th scope="col" className="num">مستحقات مفتوحة</th>
                  <th scope="col" className="num">المدفوع</th>
                  <th scope="col" className="num">حجز ضمان قائم</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td data-label="العملة"><strong>{position.currency}</strong></td>
                  <td className="num" data-label="النقدية">{moneyCell(position.cash_balance_minor_units, position.currency)}</td>
                  <td className="num" data-label="ذمم مفتوحة">{moneyCell(position.receivable_open_minor_units, position.currency)}</td>
                  <td className="num" data-label="إيراد معترف به">{moneyCell(position.revenue_recognized_minor_units, position.currency)}</td>
                  <td data-label="مصروفات مرحّلة">{moneyCell(position.expense_posted_minor_units, position.currency)}</td>
                  <td data-label="أعمال تحت التطوير">{moneyCell(position.wip_posted_minor_units, position.currency)}</td>
                  <td className="num" data-label="مستحقات مفتوحة">{moneyCell(position.payable_open_minor_units, position.currency)}</td>
                  <td className="num" data-label="المدفوع">{moneyCell(position.paid_minor_units, position.currency)}</td>
                  <td className="num" data-label="حجز ضمان قائم">{moneyCell(position.retention_held_minor_units, position.currency)}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p className="muted">
            لا يوجد رقم «ربح» غامض: كل رقم يُشتق من القيود غير المعكوسة ويُفصل عن غيره.
          </p>
        </Section>
      ) : (
        <p className="muted">لا يوجد وضع مالي مرحّل مسجّل لهذا المشروع حتى الآن.</p>
      )}

            <Section
        title="إشارات نزاهة المشروع"
      >
        {projectSignals.length === 0 ? (
          <p className="muted">لا توجد إشارات لهذا المشروع حاليًا.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: الخطورة · الإشارة · العدد · المبلغ</caption>
              <thead>
                <tr>
                  <th scope="col">الخطورة</th>
                  <th scope="col">الإشارة</th>
                  <th scope="col">العدد</th>
                  <th scope="col" className="num">المبلغ</th>
                </tr>
              </thead>
              <tbody>
                {projectSignals.map((signal) => {
                  const severity = SEVERITY_LABEL[signal.severity] ?? { label: signal.severity, className: '' };
                  return (
                    <tr key={`${signal.signal_code}-${signal.currency ?? ''}`}>
                      <td data-label="الخطورة"><span className={`status ${severity.className}`}>{severity.label}</span></td>
                      <td data-label="الإشارة">{signal.signal_label_ar}</td>
                      <td data-label="العدد">{signal.subject_count}</td>
                      <td className="num" data-label="المبلغ">
                        {moneyCell(signal.amount_minor_units, signal.currency)}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        {orgSignals.length > 0 ? (
          <>
            <h3>إشارات على مستوى المنظمة</h3>
            <div className="table-wrap">
              <table className="table-stackable">
              <caption className="sr-only">جدول: الخطورة · الإشارة · العدد</caption>
                <thead>
                  <tr><th scope="col">الخطورة</th><th scope="col">الإشارة</th><th scope="col">العدد</th></tr>
                </thead>
                <tbody>
                  {orgSignals.map((signal) => {
                    const severity = SEVERITY_LABEL[signal.severity] ?? { label: signal.severity, className: '' };
                    return (
                      <tr key={signal.signal_code}>
                        <td data-label="الخطورة"><span className={`status ${severity.className}`}>{severity.label}</span></td>
                        <td data-label="الإشارة">{signal.signal_label_ar}</td>
                        <td data-label="العدد">{signal.subject_count}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </>
        ) : null}
      </Section>

            <Section
        title="سياسات الاعتماد"
      >
        {policies.length === 0 ? (
          <p className="muted">
            لا توجد سياسات مخصصة؛ القواعد الأساسية (فصل الصلاحيات + حد المالك) تعمل دائمًا.
          </p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: المجال · الحد · العملة · يتطلب مستندًا · مفعّلة</caption>
              <thead>
                <tr><th scope="col">المجال</th><th scope="col">الحد</th><th scope="col">العملة</th><th scope="col">يتطلب مستندًا</th><th scope="col">مفعّلة</th></tr>
              </thead>
              <tbody>
                {policies.map((policy) => (
                  <tr key={policy.policy_id}>
                    <td data-label="المجال">{policy.policy_domain}</td>
                    <td data-label="الحد">{policy.threshold_minor_units ?? '—'}</td>
                    <td data-label="العملة">{policy.currency ?? 'أي عملة'}</td>
                    <td data-label="يتطلب مستندًا">{policy.evidence_required ? 'نعم' : 'لا'}</td>
                    <td data-label="مفعّلة">{policy.active ? 'نعم' : 'لا'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {isOwner ? <ApprovalPolicyForm organizationId={organizationId} commandNonce={newCommandNonce()} /> : null}
      </Section>

            <Section
        title="سجل الاستثناءات الموحد"
      >
        {exceptions.length === 0 ? (
          <p className="muted">لا توجد استثناءات مسجلة لهذا المشروع.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: المجال · النوع · الخطورة · الاستحقاق · الحالة · المبلغ · السبب · القرار</caption>
              <thead>
                <tr><th scope="col">المجال</th><th scope="col">النوع</th><th scope="col">الخطورة</th><th scope="col">الاستحقاق</th><th scope="col">الحالة</th><th scope="col" className="num">المبلغ</th><th scope="col">السبب</th><th scope="col">القرار</th></tr>
              </thead>
              <tbody>
                {exceptions.map((exception) => (
                  <tr key={exception.exception_id}>
                    <td data-label="المجال">{exception.domain}</td>
                    <td data-label="النوع">{exception.exception_kind}</td>
                    <td data-label="الخطورة"><StatusBadge tone={severityTone(exception.severity)}>{SEVERITY_LABEL[exception.severity]?.label ?? exception.severity}</StatusBadge></td>
                    <td data-label="الاستحقاق">{exception.due_date ?? '—'}</td>
                    <td data-label="الحالة"><StatusBadge tone={exception.status === 'OPEN' ? 'warning' : 'neutral'}>{RECORD_STATUS_LABEL[exception.status] ?? exception.status}</StatusBadge></td>
                    <td className="num" data-label="المبلغ">
                      {moneyCell(exception.amount_minor_units, exception.currency)}
                    </td>
                    <td data-label="السبب">{exception.reason}</td>
                    <td data-label="القرار">
                      {exception.status === 'OPEN' && isOwner ? (
                        <DecideExceptionForm
                          organizationId={organizationId}
                          projectId={projectId}
                          exception={exception}
                          commandNonce={newCommandNonce()}
                        />
                      ) : null}
                      {exception.status === 'REJECTED' && isOwner ? (
                        <ResubmitExceptionForm
                          organizationId={organizationId}
                          projectId={projectId}
                          exception={exception}
                          commandNonce={newCommandNonce()}
                        />
                      ) : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {isOwner ? (
          <OpenExceptionForm
            organizationId={organizationId}
            projectId={projectId}
            subjects={exceptionSubjects}
            commandNonce={newCommandNonce()}
          />
        ) : null}
      </Section>

            <Section
        title="عقد العملة (سعر الصرف والتحويلات المحددة)"
      >
        {snapshots.length === 0 ? (
          <p className="muted">لا توجد لقطات سعر صرف مسجلة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: الزوج · الكسر · التاريخ · المصدر</caption>
              <thead>
                <tr><th scope="col">الزوج</th><th scope="col">الكسر</th><th scope="col">التاريخ</th><th scope="col">المصدر</th></tr>
              </thead>
              <tbody>
                {snapshots.map((snapshot) => (
                  <tr key={snapshot.snapshot_id}>
                    <td data-label="الزوج">{snapshot.base_currency} → {snapshot.quote_currency}</td>
                    <td data-label="الكسر">{snapshot.rate_numerator} / {snapshot.rate_denominator}</td>
                    <td data-label="التاريخ">{snapshot.rate_date}</td>
                    <td data-label="المصدر">{snapshot.rate_source}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {conversions.length > 0 ? (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: المصدر · الناتج · الغرض · التاريخ</caption>
              <thead>
                <tr><th scope="col">المصدر</th><th scope="col">الناتج</th><th scope="col">الغرض</th><th scope="col">التاريخ</th></tr>
              </thead>
              <tbody>
                {conversions.map((conversion) => (
                  <tr key={conversion.conversion_id}>
                    <td data-label="المصدر">{conversion.source_amount_minor_units} {conversion.source_currency}</td>
                    <td data-label="الناتج">{conversion.converted_amount_minor_units} {conversion.target_currency}</td>
                    <td data-label="الغرض">{conversion.purpose}</td>
                    <td data-label="التاريخ">{conversion.conversion_date}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
        {isOwner ? (
          <>
            <FxSnapshotForm
              organizationId={organizationId}
              projectId={projectId}
              commandNonce={newCommandNonce()}
            />
            {snapshots.length > 0 ? (
              <FxConversionForm
                organizationId={organizationId}
                projectId={projectId}
                snapshots={snapshots}
                commandNonce={newCommandNonce()}
              />
            ) : null}
          </>
        ) : null}
      </Section>

            <Section
        title="التوحيد على مستوى المنظمة"
        description="صف «حسب العملة» يخص عملة واحدة كما سُجلت. صف «موحد» لا يحمل جمعًا أصليًا مختلطًا: أعمدة المبالغ الأصلية تظل فارغة إلا إذا كانت المنظمة بلا عملة تقارير ولها عملة وقائع واحدة، والتحويل لا يظهر إلا في عمود «النقدية المحولة» بعد تحويل فعلي بسعر مسجّل. لذلك لا يُوسم أي مبلغ مختلط بعملة."
      >
        {isOwner ? (
          <OrgReportingCurrencyForm
            organizationId={organizationId}
            current={orgReportingCurrency}
            commandNonce={newCommandNonce()}
          />
        ) : null}
        {consolidation.length === 0 ? (
          <p className="muted">لا توجد أرقام توحيد بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: المستوى · العملة · المشاريع · النقدية · المدفوع · المستحقات · حالة التحويل · النقدية المحولة</caption>
              <thead>
                <tr>
                  <th scope="col">المستوى</th>
                  <th scope="col">العملة</th>
                  <th scope="col">المشاريع</th>
                  <th scope="col" className="num">النقدية</th>
                  <th scope="col" className="num">المدفوع</th>
                  <th scope="col" className="num">المستحقات</th>
                  <th scope="col">حالة التحويل</th>
                  <th scope="col" className="num">النقدية المحولة</th>
                </tr>
              </thead>
              <tbody>
                {consolidation.map((row) => (
                  <tr key={`${row.level}-${row.currency ?? 'org'}`}>
                    <td data-label="المستوى">{row.level === 'CONSOLIDATED' ? 'موحد' : 'حسب العملة'}</td>
                    <td data-label="العملة">{row.currency ?? '—'}</td>
                    <td data-label="المشاريع">{row.project_count}</td>
                    <td className="num" data-label="النقدية">{moneyCell(row.cash_balance_minor_units, row.currency)}</td>
                    <td className="num" data-label="المدفوع">{moneyCell(row.paid_minor_units, row.currency)}</td>
                    <td className="num" data-label="المستحقات">{moneyCell(row.payable_open_minor_units, row.currency)}</td>
                    <td data-label="حالة التحويل">{FX_STATUS_LABEL[row.fx_status] ?? row.fx_status}</td>
                    <td className="num" data-label="النقدية المحولة">
                      {moneyCell(row.converted_cash_balance_minor_units, row.org_reporting_currency)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>

            <Section
        title="عقد المعالجة الضريبية"
      >
        <TaxRegistryTable rows={taxRegistry} />
        {isOwner ? <TaxTreatmentForm organizationId={organizationId} commandNonce={newCommandNonce()} /> : null}
      </Section>
    </section>
  );
}
