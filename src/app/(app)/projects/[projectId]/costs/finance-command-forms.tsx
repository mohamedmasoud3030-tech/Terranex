'use client';

import { useActionState, useState } from 'react';
import type { Party } from '@/features/funding/queries';
import type { CashAccountPosition } from '@/features/finance/queries';
import { formatMinorUnits } from '@/shared/money';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import {
  approvePaymentCommand,
  authorizeObligationCommand,
  createObligationCommand,
  preparePaymentCommand,
  reverseJournalBatchCommand,
} from '@/features/finance/command-actions';

export function ObligationForm({
  organizationId,
  projectId,
  currency,
  parties,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  currency: string;
  parties: Party[];
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(createObligationCommand, { error: undefined, successCount: 0 });
  const idempotencyKey = useCommandIdempotencyKey('obl', state, commandNonce);
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
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  obligationId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(authorizeObligationCommand, { error: undefined, successCount: 0 });
  const idempotencyKey = useCommandIdempotencyKey('auth', state, commandNonce);
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

export function PaymentForm({
  organizationId,
  projectId,
  obligationId,
  currency,
  outstandingMinorUnits,
  cashAccounts,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  obligationId: string;
  currency: string;
  outstandingMinorUnits: string;
  cashAccounts: CashAccountPosition[];
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(preparePaymentCommand, { error: undefined, successCount: 0 });
  const idempotencyKey = useCommandIdempotencyKey('pay-proposal', state, commandNonce);
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
      <button disabled={pending}>{pending ? 'جارٍ الإعداد…' : 'إعداد مقترح دفع'}</button>
      <p className="muted">يُفحص الرصيد المتاح الآن، ثم يعيد مالك مختلف فحصه عند الاعتماد والترحيل.</p>
    </form>
  );
}

export function ApprovePaymentProposalButton({
  organizationId,
  projectId,
  paymentProposalId,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  paymentProposalId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(approvePaymentCommand, { error: undefined, successCount: 0 });
  const idempotencyKey = useCommandIdempotencyKey('pay-approval', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="paymentProposalId" value={paymentProposalId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <button className="secondary" disabled={pending}>
        {pending ? 'جارٍ الاعتماد والترحيل…' : 'اعتماد المقترح وترحيل الدفع'}
      </button>
      {state.error && <p className="error" role="alert">{state.error}</p>}
    </form>
  );
}

export function ReverseBatchForm({
  organizationId,
  projectId,
  batchId,
  commandNonce,
  label = 'عكس القيد',
}: {
  organizationId: string;
  projectId: string;
  batchId: string;
  commandNonce: string;
  label?: string;
}) {
  const [state, action, pending] = useActionState(reverseJournalBatchCommand, { error: undefined, successCount: 0 });
  const [reason, setReason] = useState('');
  const idempotencyKey = useCommandIdempotencyKey('rev', state, commandNonce);
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
