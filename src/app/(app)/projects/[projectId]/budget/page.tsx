import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { newCommandNonce } from '@/shared/idempotency';
import { WorkspaceChrome } from '@/features/workspace/chrome';
import { formatMinorUnits } from '@/shared/money';
import { getCurrentMembership } from '@/features/finance/queries';
import {
  getBudgetConsumption,
  getProjectBudgetFac,
  getProjectBudgets,
} from '@/features/control/queries';
import type { BudgetConsumption } from '@/features/control/queries';
import {
  ApproveBudgetButton,
  BudgetForm,
  DeleteDraftBudgetButton,
  SupersedeBudgetForm,
  budgetLineTreatmentLabel,
  formatMoney,
} from './forms';

export const dynamic = 'force-dynamic';

const STATUS_LABEL: Record<string, string> = {
  DRAFT: 'مسودة',
  APPROVED: 'معتمدة',
  SUPERSEDED: 'مستبدلة',
};

function consumptionByLine(
  consumption: BudgetConsumption[],
  budgetId: string,
  costTreatment: string,
): BudgetConsumption | undefined {
  return consumption.find(
    (c) => c.budget_id === budgetId && c.cost_treatment === costTreatment,
  );
}

export default async function BudgetPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;

  const [membership, budgets, consumption, facRows] = await Promise.all([
    getCurrentMembership(organizationId),
    getProjectBudgets(projectId),
    getBudgetConsumption(projectId),
    getProjectBudgetFac(projectId),
  ]);
  const isOwner = membership?.role === 'OWNER';
  const budgetFormNonce = newCommandNonce();
  const currency = project.reporting_currency;

  const approved = budgets.filter((b) => b.status === 'APPROVED');
  const drafts = budgets.filter((b) => b.status === 'DRAFT');

  const planExpense = approved.reduce(
    (sum, b) => sum + consumption
      .filter((c) => c.budget_id === b.budget_id && c.cost_treatment === 'EXPENSE')
      .reduce((s, c) => s + BigInt(c.budget_minor_units), 0n),
    0n,
  );
  const planWip = approved.reduce(
    (sum, b) => sum + consumption
      .filter((c) => c.budget_id === b.budget_id && c.cost_treatment === 'CAPITALIZABLE_WIP')
      .reduce((s, c) => s + BigInt(c.budget_minor_units), 0n),
    0n,
  );
  const committedExpense = approved.reduce(
    (sum, b) => sum + consumption
      .filter((c) => c.budget_id === b.budget_id && c.cost_treatment === 'EXPENSE')
      .reduce((s, c) => s + BigInt(c.committed_obligations_minor_units), 0n),
    0n,
  );
  const committedWip = approved.reduce(
    (sum, b) => sum + consumption
      .filter((c) => c.budget_id === b.budget_id && c.cost_treatment === 'CAPITALIZABLE_WIP')
      .reduce((s, c) => s + BigInt(c.committed_obligations_minor_units), 0n),
    0n,
  );

  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="budget"
        title="الموازنة"
        subtitle={`${project.name} · ${currency}`}
        internalReference={project.internal_reference}
        sector={project.sector}
      />

      <section className="grid">
        <div className="card">
          <p className="muted">سقف المصروفات المعتمد</p>
          <strong>{formatMinorUnits(planExpense, currency)}</strong>
        </div>
        <div className="card">
          <p className="muted">سقف الأعمال تحت التطوير</p>
          <strong>{formatMinorUnits(planWip, currency)}</strong>
        </div>
        <div className="card">
          <p className="muted">الالتزامات المسجلة (مصروف)</p>
          <strong>{formatMinorUnits(committedExpense, currency)}</strong>
        </div>
        <div className="card">
          <p className="muted">الالتزامات المسجلة (تطوير)</p>
          <strong>{formatMinorUnits(committedWip, currency)}</strong>
        </div>
      </section>

      <section className="card stack">
        <h2>موازنات المشروع</h2>
        {budgets.length === 0 ? (
          <p className="muted">
            لا توجد موازنات بعد. أنشئ أول موازنة ثم اعتمدها؛ بعد الاعتماد يفرض السقف تلقائيًا
            عند اعتماد الالتزامات حسب معالجة التكلفة.
          </p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th>الفترة</th>
                  <th>النوع / الإصدار</th>
                  <th>الحالة</th>
                  <th>الإجمالي</th>
                  <th>الإجراءات</th>
                </tr>
              </thead>
              <tbody>
                {budgets.map((budget) => (
                  <tr key={budget.budget_id}>
                    <td data-label="الفترة">
                      {budget.period_start} → {budget.period_end}
                    </td>
                    <td data-label="النوع / الإصدار">
                      {budget.budget_type === 'ORIGINAL' ? 'أصلية' : 'مراجعة'} · إصدار {budget.version}
                    </td>
                    <td data-label="الحالة"><span className="status">{STATUS_LABEL[budget.status] ?? budget.status}</span></td>
                    <td data-label="الإجمالي">{formatMoney(budget.total_budget_minor_units, currency)}</td>
                    <td data-label="الإجراءات">
                      <div className="stack" style={{ gap: 8 }}>
                        {budget.status === 'DRAFT' && isOwner && (
                          <>
                            <ApproveBudgetButton
                              organizationId={organizationId}
                              projectId={projectId}
                              budget={budget}
                              commandNonce={newCommandNonce()}
                            />
                            <DeleteDraftBudgetButton
                              organizationId={organizationId}
                              projectId={projectId}
                              budgetId={budget.budget_id}
                              commandNonce={newCommandNonce()}
                            />
                          </>
                        )}
                        {budget.status === 'APPROVED' && isOwner && (
                          <SupersedeBudgetForm
                            organizationId={organizationId}
                            projectId={projectId}
                            budget={budget}
                            commandNonce={newCommandNonce()}
                          />
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {approved.length > 0 && (
        <section className="card stack">
          <h2>الاستهلاك مقابل السقوف (النسخ المعتمدة فقط)</h2>
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th>الإصدار</th>
                  <th>المعالجة</th>
                  <th>السقف</th>
                  <th>الالتزامات</th>
                  <th>المدفوع</th>
                  <th>الفعلية المرحّلة</th>
                  <th>استثناءات معتمدة</th>
                  <th>المتبقي الفعلي</th>
                  <th>FAC للبند</th>
                </tr>
              </thead>
              <tbody>
                {approved.flatMap((budget) => {
                  const expense = consumptionByLine(consumption, budget.budget_id, 'EXPENSE');
                  const wip = consumptionByLine(consumption, budget.budget_id, 'CAPITALIZABLE_WIP');
                  const lines = [expense, wip].filter((c): c is BudgetConsumption => Boolean(c));
                  return lines.map((line) => (
                    <tr key={`${line.budget_id}-${line.cost_treatment}`}>
                      <td data-label="الإصدار">{line.version}</td>
                      <td data-label="المعالجة">{budgetLineTreatmentLabel(line.cost_treatment)}</td>
                      <td data-label="السقف">{formatMoney(line.budget_minor_units, currency)}</td>
                      <td data-label="الالتزامات">{formatMoney(line.committed_obligations_minor_units, currency)}</td>
                      <td data-label="المدفوع">{formatMoney(line.paid_minor_units, currency)}</td>
                      <td data-label="الفعلية المرحّلة">{formatMoney(line.actual_minor_units, currency)}</td>
                      <td data-label="استثناءات معتمدة">{formatMoney(line.approved_exception_minor_units, currency)}</td>
                      <td data-label="المتبقي الفعلي">{formatMoney(line.effective_remaining_minor_units, currency)}</td>
                      <td data-label="FAC للبند">{formatMoney(line.fac_minor_units, currency)}</td>
                    </tr>
                  ));
                })}
              </tbody>
            </table>
          </div>
          <p className="muted">
            FAC للبند = الفعلية المرحّلة + المتبقي المعتمد للتنبؤ. تُفصل الفعلية والالتزامات
            والمتبقي كحقائق مستقلة؛ ولا يُخترع أي رقم توقعي آخر.
          </p>
        </section>
      )}

      {facRows.length > 0 && (
        <section className="card stack">
          <h2>التوقع عند الإنجاز (FAC) على مستوى الموازنة</h2>
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th>الإصدار</th>
                  <th>إجمالي الموازنة</th>
                  <th>استثناءات معتمدة</th>
                  <th>الفعلية (Actual)</th>
                  <th>الالتزامات المفتوحة (PO)</th>
                  <th>المتبقي المعتمد للتنبؤ</th>
                  <th>FAC</th>
                </tr>
              </thead>
              <tbody>
                {facRows.map((fac) => (
                  <tr key={fac.budget_id}>
                    <td data-label="الإصدار">{fac.version}</td>
                    <td data-label="إجمالي الموازنة">{formatMoney(fac.budget_total_minor_units, currency)}</td>
                    <td data-label="استثناءات معتمدة">{formatMoney(fac.approved_exception_total_minor_units, currency)}</td>
                    <td data-label="الفعلية (Actual)">{formatMoney(fac.actual_total_minor_units, currency)}</td>
                    <td data-label="الالتزامات المفتوحة (PO)">{formatMoney(fac.open_commitment_minor_units, currency)}</td>
                    <td data-label="المتبقي المعتمد للتنبؤ">{formatMoney(fac.approved_forecast_remainder_minor_units, currency)}</td>
                    <td data-label="FAC">{formatMoney(fac.fac_minor_units, currency)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="muted">
            FAC = الفعلية + الالتزامات المفتوحة + المتبقي المعتمد للتنبؤ — التعريف المالي
            المرجعي بفصل مكوناته الثلاثة، لا صيغة max مختزلة.
          </p>
        </section>
      )}

      <section className="card stack">
        <h2>إنشاء مسودة موازنة</h2>
        <BudgetForm
          organizationId={organizationId}
          projectId={projectId}
          currency={currency}
          commandNonce={budgetFormNonce}
        />
      </section>
    </section>
  );
}
