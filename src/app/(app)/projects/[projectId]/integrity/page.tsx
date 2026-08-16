import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { newCommandNonce } from '@/shared/idempotency';
import { WorkspaceChrome } from '@/features/workspace/chrome';
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
            <table>
              <thead>
                <tr>
                  <th>النقدية</th>
                  <th>ذمم مفتوحة</th>
                  <th>إيراد معترف به</th>
                  <th>مصروفات مرحّلة</th>
                  <th>أعمال تحت التطوير</th>
                  <th>مستحقات مفتوحة</th>
                  <th>المدفوع</th>
                  <th>حجز ضمان قائم</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>{formatMinorUnits(position.cash_balance_minor_units, currency)}</td>
                  <td>{formatMinorUnits(position.receivable_open_minor_units, currency)}</td>
                  <td>{formatMinorUnits(position.revenue_recognized_minor_units, currency)}</td>
                  <td>{formatMinorUnits(position.expense_posted_minor_units, currency)}</td>
                  <td>{formatMinorUnits(position.wip_posted_minor_units, currency)}</td>
                  <td>{formatMinorUnits(position.payable_open_minor_units, currency)}</td>
                  <td>{formatMinorUnits(position.paid_minor_units, currency)}</td>
                  <td>{formatMinorUnits(position.retention_held_minor_units, currency)}</td>
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
            <table>
              <thead>
                <tr>
                  <th>الخطورة</th>
                  <th>الإشارة</th>
                  <th>العدد</th>
                  <th>المبلغ</th>
                </tr>
              </thead>
              <tbody>
                {projectSignals.map((signal) => {
                  const severity = SEVERITY_LABEL[signal.severity] ?? { label: signal.severity, className: '' };
                  return (
                    <tr key={`${signal.signal_code}-${signal.currency ?? ''}`}>
                      <td><span className={`status ${severity.className}`}>{severity.label}</span></td>
                      <td>{signal.signal_label_ar}</td>
                      <td>{signal.subject_count}</td>
                      <td>
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
              <table>
                <thead>
                  <tr><th>الخطورة</th><th>الإشارة</th><th>العدد</th></tr>
                </thead>
                <tbody>
                  {orgSignals.map((signal) => {
                    const severity = SEVERITY_LABEL[signal.severity] ?? { label: signal.severity, className: '' };
                    return (
                      <tr key={signal.signal_code}>
                        <td><span className={`status ${severity.className}`}>{severity.label}</span></td>
                        <td>{signal.signal_label_ar}</td>
                        <td>{signal.subject_count}</td>
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
            <table>
              <thead>
                <tr><th>المجال</th><th>الحد</th><th>العملة</th><th>يتطلب مستندًا</th><th>مفعّلة</th></tr>
              </thead>
              <tbody>
                {policies.map((policy) => (
                  <tr key={policy.policy_id}>
                    <td>{policy.policy_domain}</td>
                    <td>{policy.threshold_minor_units ?? '—'}</td>
                    <td>{policy.currency ?? 'أي عملة'}</td>
                    <td>{policy.evidence_required ? 'نعم' : 'لا'}</td>
                    <td>{policy.active ? 'نعم' : 'لا'}</td>
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
            <table>
              <thead>
                <tr><th>المجال</th><th>النوع</th><th>الخطورة</th><th>الاستحقاق</th><th>الحالة</th><th>المبلغ</th><th>السبب</th><th>القرار</th></tr>
              </thead>
              <tbody>
                {exceptions.map((exception) => (
                  <tr key={exception.exception_id}>
                    <td>{exception.domain}</td>
                    <td>{exception.exception_kind}</td>
                    <td>{exception.severity}</td>
                    <td>{exception.due_date ?? '—'}</td>
                    <td><span className="status">{exception.status}</span></td>
                    <td>
                      {exception.amount_minor_units
                        ? formatMinorUnits(exception.amount_minor_units, exception.currency ?? currency)
                        : '—'}
                    </td>
                    <td>{exception.reason}</td>
                    <td>
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
            <table>
              <thead>
                <tr><th>الزوج</th><th>الكسر</th><th>التاريخ</th><th>المصدر</th></tr>
              </thead>
              <tbody>
                {snapshots.map((snapshot) => (
                  <tr key={snapshot.snapshot_id}>
                    <td>{snapshot.base_currency} → {snapshot.quote_currency}</td>
                    <td>{snapshot.rate_numerator} / {snapshot.rate_denominator}</td>
                    <td>{snapshot.rate_date}</td>
                    <td>{snapshot.rate_source}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {conversions.length > 0 ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>المصدر</th><th>الناتج</th><th>الغرض</th><th>التاريخ</th></tr>
              </thead>
              <tbody>
                {conversions.map((conversion) => (
                  <tr key={conversion.conversion_id}>
                    <td>{conversion.source_amount_minor_units} {conversion.source_currency}</td>
                    <td>{conversion.converted_amount_minor_units} {conversion.target_currency}</td>
                    <td>{conversion.purpose}</td>
                    <td>{conversion.conversion_date}</td>
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
            <table>
              <thead>
                <tr>
                  <th>المستوى</th>
                  <th>العملة</th>
                  <th>المشاريع</th>
                  <th>النقدية</th>
                  <th>المدفوع</th>
                  <th>المستحقات</th>
                  <th>حالة التحويل</th>
                  <th>النقدية المحولة</th>
                </tr>
              </thead>
              <tbody>
                {consolidation.map((row) => (
                  <tr key={`${row.level}-${row.currency ?? 'org'}`}>
                    <td>{row.level === 'CONSOLIDATED' ? 'موحد' : 'حسب العملة'}</td>
                    <td>{row.currency ?? '—'}</td>
                    <td>{row.project_count}</td>
                    <td>{row.cash_balance_minor_units ? formatMinorUnits(row.cash_balance_minor_units, row.currency ?? currency) : '—'}</td>
                    <td>{row.paid_minor_units ? formatMinorUnits(row.paid_minor_units, row.currency ?? currency) : '—'}</td>
                    <td>{row.payable_open_minor_units ? formatMinorUnits(row.payable_open_minor_units, row.currency ?? currency) : '—'}</td>
                    <td>{FX_STATUS_LABEL[row.fx_status] ?? row.fx_status}</td>
                    <td>
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
            <table>
              <thead>
                <tr><th>الضريبة</th><th>النطاق</th><th>المعالجة</th><th>جهة التقدير</th><th>سارية</th></tr>
              </thead>
              <tbody>
                {taxRegistry.map((tax) => (
                  <tr key={tax.tax_registry_id}>
                    <td>{tax.tax_name} ({tax.tax_domain})</td>
                    <td>{tax.applies_to}</td>
                    <td>{tax.treatment_status}</td>
                    <td>{tax.authority ?? '—'}</td>
                    <td>{tax.status === 'ACTIVE' ? 'نعم' : 'لا'}</td>
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
