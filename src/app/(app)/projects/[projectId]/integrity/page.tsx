import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { newCommandNonce } from '@/shared/idempotency';
import { WorkspaceChrome } from '@/features/workspace/chrome';
import { StatusBadge } from '@/shared/ui';
import { RECORD_STATUS_LABEL, severityTone } from '@/features/projects/labels';
import { formatMinorUnits } from '@/shared/money';
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
  const currency = project.reporting_currency;

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
        subtitle={`${project.name} · ${currency}`}
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
        <section className="card stack">
          <h2>الوضع المالي الرسمي (من القيود المرحّلة فقط)</h2>
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th className="num">النقدية</th>
                  <th className="num">ذمم مفتوحة</th>
                  <th className="num">إيراد معترف به</th>
                  <th>مصروفات مرحّلة</th>
                  <th>أعمال تحت التطوير</th>
                  <th className="num">مستحقات مفتوحة</th>
                  <th className="num">المدفوع</th>
                  <th className="num">حجز ضمان قائم</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td className="num" data-label="النقدية">{formatMinorUnits(position.cash_balance_minor_units, currency)}</td>
                  <td className="num" data-label="ذمم مفتوحة">{formatMinorUnits(position.receivable_open_minor_units, currency)}</td>
                  <td className="num" data-label="إيراد معترف به">{formatMinorUnits(position.revenue_recognized_minor_units, currency)}</td>
                  <td data-label="مصروفات مرحّلة">{formatMinorUnits(position.expense_posted_minor_units, currency)}</td>
                  <td data-label="أعمال تحت التطوير">{formatMinorUnits(position.wip_posted_minor_units, currency)}</td>
                  <td className="num" data-label="مستحقات مفتوحة">{formatMinorUnits(position.payable_open_minor_units, currency)}</td>
                  <td className="num" data-label="المدفوع">{formatMinorUnits(position.paid_minor_units, currency)}</td>
                  <td className="num" data-label="حجز ضمان قائم">{formatMinorUnits(position.retention_held_minor_units, currency)}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p className="muted">
            لا يوجد رقم «ربح» غامض: كل رقم يُشتق من القيود غير المعكوسة ويُفصل عن غيره.
          </p>
        </section>
      ) : null}

      <section className="card stack">
        <h2>إشارات نزاهة المشروع</h2>
        {projectSignals.length === 0 ? (
          <p className="muted">لا توجد إشارات لهذا المشروع حاليًا.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th>الخطورة</th>
                  <th>الإشارة</th>
                  <th>العدد</th>
                  <th className="num">المبلغ</th>
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
                        {signal.amount_minor_units
                          ? formatMinorUnits(signal.amount_minor_units, signal.currency ?? currency)
                          : '—'}
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
                <thead>
                  <tr><th>الخطورة</th><th>الإشارة</th><th>العدد</th></tr>
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
      </section>

      <section className="card stack">
        <h2>سياسات الاعتماد</h2>
        {policies.length === 0 ? (
          <p className="muted">
            لا توجد سياسات مخصصة؛ القواعد الأساسية (فصل الصلاحيات + حد المالك) تعمل دائمًا.
          </p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr><th>المجال</th><th>الحد</th><th>العملة</th><th>يتطلب مستندًا</th><th>مفعّلة</th></tr>
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
      </section>

      <section className="card stack">
        <h2>سجل الاستثناءات الموحد</h2>
        {exceptions.length === 0 ? (
          <p className="muted">لا توجد استثناءات مسجلة لهذا المشروع.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr><th>المجال</th><th>النوع</th><th>الخطورة</th><th>الاستحقاق</th><th>الحالة</th><th className="num">المبلغ</th><th>السبب</th><th>القرار</th></tr>
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
                      {exception.amount_minor_units
                        ? formatMinorUnits(exception.amount_minor_units, exception.currency ?? currency)
                        : '—'}
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
      </section>

      <section className="card stack">
        <h2>عقد العملة (سعر الصرف والتحويلات المحددة)</h2>
        {snapshots.length === 0 ? (
          <p className="muted">لا توجد لقطات سعر صرف مسجلة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr><th>الزوج</th><th>الكسر</th><th>التاريخ</th><th>المصدر</th></tr>
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
              <thead>
                <tr><th>المصدر</th><th>الناتج</th><th>الغرض</th><th>التاريخ</th></tr>
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
      </section>

      <section className="card stack">
        <h2>التوحيد على مستوى المنظمة</h2>
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
              <thead>
                <tr>
                  <th>المستوى</th>
                  <th>العملة</th>
                  <th>المشاريع</th>
                  <th className="num">النقدية</th>
                  <th className="num">المدفوع</th>
                  <th className="num">المستحقات</th>
                  <th>حالة التحويل</th>
                  <th className="num">النقدية المحولة</th>
                </tr>
              </thead>
              <tbody>
                {consolidation.map((row) => (
                  <tr key={`${row.level}-${row.currency ?? 'org'}`}>
                    <td data-label="المستوى">{row.level === 'CONSOLIDATED' ? 'موحد' : 'حسب العملة'}</td>
                    <td data-label="العملة">{row.currency ?? '—'}</td>
                    <td data-label="المشاريع">{row.project_count}</td>
                    <td className="num" data-label="النقدية">{row.cash_balance_minor_units ? formatMinorUnits(row.cash_balance_minor_units, row.currency ?? currency) : '—'}</td>
                    <td className="num" data-label="المدفوع">{row.paid_minor_units ? formatMinorUnits(row.paid_minor_units, row.currency ?? currency) : '—'}</td>
                    <td className="num" data-label="المستحقات">{row.payable_open_minor_units ? formatMinorUnits(row.payable_open_minor_units, row.currency ?? currency) : '—'}</td>
                    <td data-label="حالة التحويل">{FX_STATUS_LABEL[row.fx_status] ?? row.fx_status}</td>
                    <td className="num" data-label="النقدية المحولة">
                      {row.converted_cash_balance_minor_units
                        ? formatMinorUnits(row.converted_cash_balance_minor_units, row.org_reporting_currency ?? '')
                        : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="card stack">
        <h2>عقد المعالجة الضريبية</h2>
        {taxRegistry.length === 0 ? (
          <p className="muted">لا توجد معالجات ضريبية مسجلة.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr><th>الضريبة</th><th>النطاق</th><th>المعالجة</th><th>جهة التقدير</th><th>سارية</th></tr>
              </thead>
              <tbody>
                {taxRegistry.map((tax) => (
                  <tr key={tax.tax_registry_id}>
                    <td data-label="الضريبة">{tax.tax_name} ({tax.tax_domain})</td>
                    <td data-label="النطاق">{tax.applies_to}</td>
                    <td data-label="المعالجة">{tax.treatment_status}</td>
                    <td data-label="جهة التقدير">{tax.authority ?? '—'}</td>
                    <td data-label="سارية">{tax.status === 'ACTIVE' ? 'نعم' : 'لا'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {isOwner ? <TaxTreatmentForm organizationId={organizationId} commandNonce={newCommandNonce()} /> : null}
      </section>
    </section>
  );
}
