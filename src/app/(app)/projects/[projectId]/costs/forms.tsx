'use client';

import { useActionState, useMemo, useState } from 'react';
import type { Party } from '@/features/funding/queries';
import type { CashAccountPosition } from '@/features/finance/queries';
import { formatMinorUnits } from '@/shared/money';
import {
  authorizeObligation,
  createObligation,
  deleteObligationDraft,
  payObligation,
  reverseJournalBatch,
} from '@/features/finance/actions';

export function ObligationForm({
  organizationId,
  projectId,
  currency,
  parties,
}: {
  organizationId: string;
  projectId: string;
  currency: string;
  parties: Party[];
}) {
  const [state, action, pending] = useActionState(createObligation, { error: undefined });
  const idempotencyKey = useMemo(() => `obl-${crypto.randomUUID()}`, []);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        المورد
        <select name="partyId" required>
          <option value="" disabled>اختر المورد</option>
          {parties.map((party) => (
            <option key={party.id} value={party.id}>{party.legal_name}</option>
          ))}
        </select>
      </label>
      <label>
        الوصف
        <textarea name="description" required minLength={3} maxLength={500} placeholder="مثال: أعمال حفر وتجهيز الموقع" />
      </label>
      <label>
        المبلغ ({currency})
        <input name="amount" inputMode="decimal" required placeholder="50000.00" />
      </label>
      <label>
        تاريخ المعاملة
        <input type="date" name="transactionDate" required />
      </label>
      <fieldset style={{ border: 0, padding: 0, margin: 0 }}>
        <legend style={{ fontWeight: 700 }}>المعالجة المحاسبية (اخترها صراحة)</legend>
        <label style={{ fontWeight: 400 }}>
          <input type="radio" name="costTreatment" value="EXPENSE" defaultChecked /> مصروف (يُحمّل على نتائج المشروع)
        </label>
        <label style={{ fontWeight: 400 }}>
          <input type="radio" name="costTreatment" value="CAPITALIZABLE_WIP" /> أعمال تحت التطوير (يُرسمل في أصول المشروع)
        </label>
      </fieldset>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? 'جارٍ الحفظ…' : 'حفظ التزام (مسودة)'}</button>
      <p className="muted">المسودة يعدّها أي عضو نشط؛ اعتمادها وترحيلها قيد يقتصر على مالك المنظمة.</p>
    </form>
  );
}

export function AuthorizeObligationButton({
  organizationId,
  projectId,
  obligationId,
}: {
  organizationId: string;
  projectId: string;
  obligationId: string;
}) {
  const [state, action, pending] = useActionState(authorizeObligation, { error: undefined });
  const idempotencyKey = useMemo(() => `auth-${crypto.randomUUID()}`, []);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="obligationId" value={obligationId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <button className="secondary" disabled={pending}>
        {pending ? 'جارٍ الاعتماد…' : 'اعتماد وترحيل القيد'}
      </button>
      {state.error && <p className="error" role="alert">{state.error}</p>}
    </form>
  );
}

export function DeleteDraftButton({
  organizationId,
  projectId,
  obligationId,
}: {
  organizationId: string;
  projectId: string;
  obligationId: string;
}) {
  const [state, action, pending] = useActionState(deleteObligationDraft, { error: undefined });
  return (
    <form action={action}>
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="obligationId" value={obligationId} />
      <button className="secondary" disabled={pending}>حذف المسودة</button>
      {state.error && <p className="error" role="alert">{state.error}</p>}
    </form>
  );
}

export function PaymentForm({
  organizationId,
  projectId,
  obligationId,
  currency,
  outstandingMinorUnits,
  cashAccounts,
}: {
  organizationId: string;
  projectId: string;
  obligationId: string;
  currency: string;
  outstandingMinorUnits: string;
  cashAccounts: CashAccountPosition[];
}) {
  const [state, action, pending] = useActionState(payObligation, { error: undefined });
  const idempotencyKey = useMemo(() => `pay-${crypto.randomUUID()}`, []);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="obligationId" value={obligationId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        الحساب النقدي
        <select name="cashAccountId" required>
          <option value="" disabled>اختر الحساب</option>
          {cashAccounts.map((account) => (
            <option key={account.cash_account_id} value={account.cash_account_id}>
              {account.name} — رصيد {formatMinorUnits(account.balance_minor_units, account.currency)}
            </option>
          ))}
        </select>
      </label>
      <label>
        المبلغ ({currency}) — المتبقي {formatMinorUnits(outstandingMinorUnits, currency)}
        <input name="amount" inputMode="decimal" required placeholder="10000.00" />
      </label>
      <label>
        تاريخ الدفعة
        <input type="date" name="paymentDate" required />
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? 'جارٍ الترحيل…' : 'ترحيل دفعة من الحساب'}</button>
    </form>
  );
}

export function ReverseBatchForm({
  organizationId,
  projectId,
  batchId,
  label = 'عكس القيد',
}: {
  organizationId: string;
  projectId: string;
  batchId: string;
  label?: string;
}) {
  const [state, action, pending] = useActionState(reverseJournalBatch, { error: undefined });
  const [reason, setReason] = useState('');
  const idempotencyKey = useMemo(() => `rev-${crypto.randomUUID()}`, []);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="batchId" value={batchId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        سبب العكس (إلزامي)
        <input name="reason" required minLength={3} maxLength={500} value={reason}
          onChange={(event) => setReason(event.target.value)} placeholder="مثال: قيد مسجل بالخطأ" />
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button className="secondary" disabled={pending || reason.trim().length < 3}>
        {pending ? 'جارٍ العكس…' : label}
      </button>
    </form>
  );
}
