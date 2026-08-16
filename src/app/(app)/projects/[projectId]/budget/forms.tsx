'use client';

import { useActionState, useMemo } from 'react';
import { formatMinorUnits } from '@/shared/money';
import type { BudgetRow } from '@/features/control/queries';
import {
  approveBudget,
  createBudget,
  deleteDraftBudget,
  supersedeBudget,
} from '@/features/control/actions';

const TREATMENT_LABEL: Record<string, string> = {
  EXPENSE: 'مصروف',
  CAPITALIZABLE_WIP: 'أعمال تحت التطوير',
};

export function BudgetForm({
  organizationId,
  projectId,
  currency,
}: {
  organizationId: string;
  projectId: string;
  currency: string;
}) {
  const [state, action, pending] = useActionState(createBudget, { error: undefined });
  const idempotencyKey = useMemo(() => `budget-${crypto.randomUUID()}`, []);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="budgetType" value="ORIGINAL" />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <div className="grid">
        <label>
          بداية الفترة
          <input type="date" name="periodStart" required />
        </label>
        <label>
          نهاية الفترة
          <input type="date" name="periodEnd" required />
        </label>
      </div>
      <label>
        وصف الموازنة
        <input name="description" required minLength={3} maxLength={1000} placeholder="مثال: موازنة النصف الأول" />
      </label>
      <label>
        مرجع المستند (اختياري، مطلوب إذا كانت سياسة الاعتماد تشترطه)
        <input name="evidenceReference" maxLength={500} placeholder="مثال: قرار اعتماد الموازنة رقم ١" />
      </label>
      <label>
        بنود الموازنة — صفيف JSON (cost_treatment + amount_minor_units + notes)
        <textarea
          name="linesJson"
          required
          rows={5}
          placeholder={'[{"cost_treatment":"EXPENSE","amount_minor_units":20000000,"notes":"أعمال تنفيذ"}]'}
          defaultValue='[{"cost_treatment":"EXPENSE","amount_minor_units":0}]'
        />
      </label>
      <p className="muted">
        المبالغ بالوحدات الصغرى للعملة (مليمات/هللات) لتجنب أي تقريب؛ مثال: 100.00 {currency} = {currency === 'EGP' ? '10000' : '10000'}.
      </p>
      {state.error ? <p className="error">{state.error}</p> : null}
      <button disabled={pending} type="submit" className="button">
        {pending ? 'جارٍ الحفظ…' : 'إنشاء مسودة الموازنة'}
      </button>
    </form>
  );
}

export function ApproveBudgetButton({
  organizationId,
  projectId,
  budget,
}: {
  organizationId: string;
  projectId: string;
  budget: BudgetRow;
}) {
  const [state, action, pending] = useActionState(approveBudget, { error: undefined });
  const idempotencyKey = useMemo(() => `budget-approve-${crypto.randomUUID()}`, []);
  return (
    <form action={action} className="inline">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="budgetId" value={budget.budget_id} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <button disabled={pending} type="submit" className="button">
        اعتماد الموازنة
      </button>
      {state.error ? <span className="error">{state.error}</span> : null}
    </form>
  );
}

export function SupersedeBudgetForm({
  organizationId,
  projectId,
  budget,
}: {
  organizationId: string;
  projectId: string;
  budget: BudgetRow;
}) {
  const [state, action, pending] = useActionState(supersedeBudget, { error: undefined });
  const idempotencyKey = useMemo(() => `budget-supersede-${crypto.randomUUID()}`, []);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="budgetId" value={budget.budget_id} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        وصف المراجعة
        <input name="description" required minLength={3} maxLength={1000} placeholder="سبب فتح مراجعة جديدة" />
      </label>
      <button disabled={pending} type="submit" className="button">
        {pending ? 'جارٍ الفتح…' : 'فتح مراجعة (إصدار جديد)'}
      </button>
      {state.error ? <p className="error">{state.error}</p> : null}
    </form>
  );
}

export function DeleteDraftBudgetButton({
  organizationId,
  projectId,
  budgetId,
}: {
  organizationId: string;
  projectId: string;
  budgetId: string;
}) {
  const [state, action, pending] = useActionState(deleteDraftBudget, { error: undefined });
  const idempotencyKey = useMemo(() => `budget-delete-${crypto.randomUUID()}`, []);
  return (
    <form action={action} className="inline">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="budgetId" value={budgetId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <button disabled={pending} type="submit" className="button danger">
        حذف المسودة
      </button>
      {state.error ? <span className="error">{state.error}</span> : null}
    </form>
  );
}

export function budgetLineTreatmentLabel(costTreatment: string): string {
  return TREATMENT_LABEL[costTreatment] ?? costTreatment;
}

export function formatMoney(minorUnits: string | null | undefined, currency: string): string {
  if (minorUnits === null || minorUnits === undefined) return '—';
  return formatMinorUnits(minorUnits, currency);
}
