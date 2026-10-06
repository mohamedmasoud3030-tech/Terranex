import { notFound } from 'next/navigation';
import { Section } from '@/shared/ui';
import { getProject } from '@/features/projects/queries';
import { newCommandNonce } from '@/shared/idempotency';
import { WorkspaceChrome } from '@/features/workspace/chrome';
import {
  totalsByCurrency,
  presentRollup,
  type CurrencyRollupResult,
} from '@/shared/money/by-currency';
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

/**
 * One line per currency, each carrying its own currency. A ceiling with no
 * consumption rows renders an explicit absence rather than a manufactured zero,
 * and nothing here can place two currencies on the same line.
 */
function rollupLines(result: CurrencyRollupResult) {
  if (result.totals.length === 0) return <strong>—</strong>;
  return (
    <>
      {result.totals.map((total) => (
        <strong className="num" key={total.currency}>
          {presentRollup(total)}
        </strong>
      ))}
    </>
  );
}

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

  // `budget_consumption_read` carries its own currency, so a budget ceiling is
  // one figure per currency. These are partitioned rather than summed, and no
  // row is ever stamped with the project's reporting currency.
  const approvedIds = new Set(approved.map((b) => b.budget_id));
  const approvedConsumption = consumption.filter((c) => approvedIds.has(c.budget_id));
  const expenseConsumption = approvedConsumption.filter((c) => c.cost_treatment === 'EXPENSE');
  const wipConsumption = approvedConsumption.filter((c) => c.cost_treatment === 'CAPITALIZABLE_WIP');

  const planExpense = totalsByCurrency(
    expenseConsumption,
    (c) => c.currency,
    (c) => c.budget_minor_units,
  );
  const planWip = totalsByCurrency(wipConsumption, (c) => c.currency, (c) => c.budget_minor_units);
  const committedExpense = totalsByCurrency(
    expenseConsumption,
    (c) => c.currency,
    (c) => c.committed_obligations_minor_units,
  );
  const committedWip = totalsByCurrency(
    wipConsumption,
    (c) => c.currency,
    (c) => c.committed_obligations_minor_units,
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
          {rollupLines(planExpense)}
        </div>
        <div className="card">
          <p className="muted">سقف الأعمال تحت التطوير</p>
          {rollupLines(planWip)}
        </div>
        <div className="card">
          <p className="muted">الالتزامات المسجلة (مصروف)</p>
          {rollupLines(committedExpense)}
        </div>
        <div className="card">
          <p className="muted">الالتزامات المسجلة (تطوير)</p>
          {rollupLines(committedWip)}
        </div>
      </section>

            <Section
        title="موازنات المشروع"
      >
        {budgets.length === 0 ? (
          <p className="muted">
            لا توجد موازنات بعد. أنشئ أول موازنة ثم اعتمدها؛ بعد الاعتماد يفرض السقف تلقائيًا
            عند اعتماد الالتزامات حسب معالجة التكلفة.
          </p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: الفترة · النوع / الإصدار · الحالة · الإجمالي · الإجراءات</caption>
              <thead>
                <tr>
                  <th scope="col">الفترة</th>
                  <th scope="col">النوع / الإصدار</th>
                  <th scope="col">الحالة</th>
                  <th scope="col" className="num">الإجمالي</th>
                  <th scope="col">الإجراءات</th>
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
                    <td className="num" data-label="الإجمالي">{formatMoney(budget.total_budget_minor_units, budget.currency)}</td>
                    <td data-label="الإجراءات">
                      <div className="stack-xs">
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
      </Section>

      {approved.length > 0 && (
                <Section
          title="الاستهلاك مقابل السقوف (النسخ المعتمدة فقط)"
        >
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: الإصدار · المعالجة · السقف · الالتزامات · المدفوع · الفعلية المرحّلة · استثناءات معتمدة · المتبقي الفعلي · FAC للبند</caption>
              <thead>
                <tr>
                  <th scope="col">الإصدار</th>
                  <th scope="col">المعالجة</th>
                  <th scope="col">السقف</th>
                  <th scope="col" className="num">الالتزامات</th>
                  <th scope="col" className="num">المدفوع</th>
                  <th scope="col" className="num">الفعلية المرحّلة</th>
                  <th scope="col" className="num">استثناءات معتمدة</th>
                  <th scope="col" className="num">المتبقي الفعلي</th>
                  <th scope="col" className="num">FAC للبند</th>
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
                      <td data-label="السقف">{formatMoney(line.budget_minor_units, line.currency)}</td>
                      <td className="num" data-label="الالتزامات">{formatMoney(line.committed_obligations_minor_units, line.currency)}</td>
                      <td className="num" data-label="المدفوع">{formatMoney(line.paid_minor_units, line.currency)}</td>
                      <td className="num" data-label="الفعلية المرحّلة">{formatMoney(line.actual_minor_units, line.currency)}</td>
                      <td className="num" data-label="استثناءات معتمدة">{formatMoney(line.approved_exception_minor_units, line.currency)}</td>
                      <td className="num" data-label="المتبقي الفعلي">{formatMoney(line.effective_remaining_minor_units, line.currency)}</td>
                      <td className="num" data-label="FAC للبند">{formatMoney(line.fac_minor_units, line.currency)}</td>
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
        </Section>
      )}

      {facRows.length > 0 && (
                <Section
          title="التوقع عند الإنجاز (FAC) على مستوى الموازنة"
        >
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: الإصدار · إجمالي الموازنة · استثناءات معتمدة · الفعلية (Actual) · الالتزامات المفتوحة (PO) · المتبقي المعتمد للتنبؤ · FAC</caption>
              <thead>
                <tr>
                  <th scope="col">الإصدار</th>
                  <th scope="col">إجمالي الموازنة</th>
                  <th scope="col" className="num">استثناءات معتمدة</th>
                  <th scope="col" className="num">الفعلية (Actual)</th>
                  <th scope="col" className="num">الالتزامات المفتوحة (PO)</th>
                  <th scope="col" className="num">المتبقي المعتمد للتنبؤ</th>
                  <th scope="col" className="num">FAC</th>
                </tr>
              </thead>
              <tbody>
                {facRows.map((fac) => (
                  <tr key={fac.budget_id}>
                    <td data-label="الإصدار">{fac.version}</td>
                    <td data-label="إجمالي الموازنة">{formatMoney(fac.budget_total_minor_units, fac.currency)}</td>
                    <td className="num" data-label="استثناءات معتمدة">{formatMoney(fac.approved_exception_total_minor_units, fac.currency)}</td>
                    <td className="num" data-label="الفعلية (Actual)">{formatMoney(fac.actual_total_minor_units, fac.currency)}</td>
                    <td className="num" data-label="الالتزامات المفتوحة (PO)">{formatMoney(fac.open_commitment_minor_units, fac.currency)}</td>
                    <td className="num" data-label="المتبقي المعتمد للتنبؤ">{formatMoney(fac.approved_forecast_remainder_minor_units, fac.currency)}</td>
                    <td className="num" data-label="FAC">{formatMoney(fac.fac_minor_units, fac.currency)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="muted">
            FAC = الفعلية + الالتزامات المفتوحة + المتبقي المعتمد للتنبؤ — التعريف المالي
            المرجعي بفصل مكوناته الثلاثة، لا صيغة max مختزلة.
          </p>
        </Section>
      )}

            <Section
        title="إنشاء مسودة موازنة"
      >
        <BudgetForm
          organizationId={organizationId}
          projectId={projectId}
          currency={currency}
          commandNonce={budgetFormNonce}
        />
      </Section>
    </section>
  );
}
