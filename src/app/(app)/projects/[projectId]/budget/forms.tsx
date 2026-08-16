'use client';

import { useActionState } from 'react';
import { formatMinorUnits } from '@/shared/money';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import type { ActionState } from '@/features/auth/actions';
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

const initialState: ActionState = {};

export function BudgetForm({
  organizationId,
  projectId,
  currency,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  currency: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(createBudget, initialState);
  const idempotencyKey = useCommandIdempotencyKey('budget-create', state, commandNonce);
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
        المبالغ بالوحدات الصغرى للعملة لتجنب أي تقريب؛ مثال: 100.00 من عملة المشروع = 10000 وحدة صغرى.
        أي بند غير صالح يرفض الموازنة كاملة — لا يُسقط أي بند بصمت.
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
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  budget: BudgetRow;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(approveBudget, initialState);
  const idempotencyKey = useCommandIdempotencyKey('budget-approve', state, commandNonce);
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
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  budget: BudgetRow;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(supersedeBudget, initialState);
  const idempotencyKey = useCommandIdempotencyKey('budget-supersede', state, commandNonce);
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
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  budgetId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(deleteDraftBudget, initialState);
  const idempotencyKey = useCommandIdempotencyKey('budget-delete', state, commandNonce);
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
