'use client';

import { useActionState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import { postAdjustment } from '@/features/adjustments/actions';
import { ADJUSTMENT_ROLES, ADJUSTMENT_ROLE_LABEL } from '@/features/adjustments/schema';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import { Field, FormActions, FormError } from '@/shared/ui/form';

const initial: ActionState = {};

export function AdjustmentForm(props: {
  organizationId: string;
  projectId: string;
  currency: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(postAdjustment, initial);
  const key = useCommandIdempotencyKey('manual-adjustment', state, props.commandNonce);
  const roles = ADJUSTMENT_ROLES.map((role) => (
    <option key={role} value={role}>{ADJUSTMENT_ROLE_LABEL[role]}</option>
  ));
  return (
    <form action={action} className="form-grid">
      <input type="hidden" name="organizationId" value={props.organizationId} />
      <input type="hidden" name="projectId" value={props.projectId} />
      <input type="hidden" name="currency" value={props.currency} />
      <input type="hidden" name="idempotencyKey" value={key} />
      <Field label="من حساب (دائن)">
        <select name="fromRole" required defaultValue="">
          <option value="" disabled>اختر الحساب</option>
          {roles}
        </select>
      </Field>
      <Field label="إلى حساب (مدين)">
        <select name="toRole" required defaultValue="">
          <option value="" disabled>اختر الحساب</option>
          {roles}
        </select>
      </Field>
      <Field label={`المبلغ (${props.currency})`}>
        <input name="amount" inputMode="decimal" required />
      </Field>
      <Field label="تاريخ القيد">
        <input type="date" name="entryDate" required />
      </Field>
      <Field label="البيان" className="full">
        <input name="memo" required minLength={5} maxLength={500} />
      </Field>
      <Field label="مرجع الدليل" className="full">
        <input name="evidenceReference" required minLength={3} maxLength={200} />
      </Field>
      <p className="muted full">
        قيد تسوية متوازن بين حسابات التكلفة فقط. النقدية والإيرادات والذمم لها مساراتها المستقلة.
      </p>
      <div className="full">
        <FormError error={state.error} />
        {!state.error && (state.successCount ?? 0) > 0 ? (
          <p className="status" role="status">تم ترحيل القيد بنجاح.</p>
        ) : null}
        <FormActions>
          <button disabled={pending}>{pending ? 'جارٍ الترحيل…' : 'ترحيل قيد التسوية'}</button>
        </FormActions>
      </div>
    </form>
  );
}
