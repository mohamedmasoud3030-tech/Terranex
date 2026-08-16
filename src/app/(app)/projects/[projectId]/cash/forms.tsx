'use client';

import { useActionState, useState } from 'react';
import type { Contribution, PaymentStatus, BankStatementLineStatus } from '@/features/finance/queries';
import { formatMinorUnits } from '@/shared/money';
import {
  attachContributionCashCommand,
  createCashAccountCommand,
  importBankStatementCommand,
  reconcilePaymentCommand,
  reverseJournalBatchCommand,
  voidReconciliationCommand,
} from '@/features/finance/command-actions';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';

export function CashAccountForm({
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
  const [state, action, pending] = useActionState(createCashAccountCommand, { error: undefined, successCount: 0 });
  const idempotencyKey = useCommandIdempotencyKey('cash-account', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        اسم الحساب
        <input name="name" required minLength={2} maxLength={120} placeholder="مثال: البنك الأهلي — حساب المشروع" />
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? 'جارٍ الإنشاء…' : 'إنشاء حساب نقدي'}</button>
      <p className="muted">رصيد الحساب يُشتق دائمًا من القيود المرحلة ولا يمكن تعديله يدويًا.</p>
    </form>
  );
}

export function ContributionAttributionForm({
  organizationId,
  projectId,
  contributions,
  cashAccountId,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  contributions: Contribution[];
  cashAccountId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(attachContributionCashCommand, { error: undefined, successCount: 0 });
  const [selected, setSelected] = useState('');
  const idempotencyKey = useCommandIdempotencyKey('attach', state, commandNonce);
  if (contributions.length === 0) {
    return <p className="muted">لا توجد مساهمات غير مُسنَدة للحساب النقدي.</p>;
  }
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="cashAccountId" value={cashAccountId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        المساهمة
        <select name="contributionId" required value={selected} onChange={(event) => setSelected(event.target.value)}>
          <option value="" disabled>اختر المساهمة</option>
          {contributions.map((contribution) => (
            <option key={contribution.id} value={contribution.id}>
              {contribution.occurred_on} — {formatMinorUnits(contribution.contribution_minor_units, contribution.currency)}
            </option>
          ))}
        </select>
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending || !selected}>{pending ? 'جارٍ الترحيل…' : 'ترحيل إسناد المساهمة'}</button>
      <p className="muted">القيد: مدين نقدية البنك / دائن رأس المال المساهم. تُرحَّل كل مساهمة مرة واحدة ما لم يوجد عكس مرتبط بها.</p>
    </form>
  );
}

export function BankImportForm({
  organizationId,
  projectId,
  cashAccounts,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  cashAccounts: { cash_account_id: string; name: string }[];
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(importBankStatementCommand, { error: undefined, successCount: 0 });
  const idempotencyKey = useCommandIdempotencyKey('import', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        الحساب النقدي
        <select name="cashAccountId" required>
          <option value="" disabled>اختر الحساب</option>
          {cashAccounts.map((account) => (
            <option key={account.cash_account_id} value={account.cash_account_id}>{account.name}</option>
          ))}
        </select>
      </label>
      <label>
        كشف الحساب (CSV)
        <textarea
          name="csv"
          required
          placeholder={'date,amount,currency,description,provider_reference\n2026-08-25,-150000,EGP,دفعة للمورد الأول,TXN-1001'}
          dir="ltr"
        />
      </label>
      <p className="muted">
        صيغة ثابتة: سطر لكل حركة، الأعمدة: التاريخ، المبلغ (سالب = خروج من الحساب)، العملة، الوصف، المرجع الخارجي (اختياري).
        الاستيراد يسجّل الحركات فقط ولا ينشئ أي قيد محاسبي؛ المطابقة تتم يدويًا لاحقًا.
      </p>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? 'جارٍ الاستيراد…' : 'استيراد كشف الحساب'}</button>
    </form>
  );
}

export function ReconcileForm({
  organizationId,
  projectId,
  line,
  payments,
  accountName,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  line: BankStatementLineStatus;
  payments: PaymentStatus[];
  accountName: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(reconcilePaymentCommand, { error: undefined, successCount: 0 });
  const [selected, setSelected] = useState('');
  const idempotencyKey = useCommandIdempotencyKey('recon', state, commandNonce);
  const candidates = payments.filter(
    (payment) =>
      !payment.is_reversed &&
      !payment.is_reconciled &&
      payment.cash_account_id === line.cash_account_id &&
      payment.currency === line.currency,
  );
  return (
    <details className="stack">
      <summary>مطابقة سطر بنكي</summary>
      <form action={action} className="stack">
        <input type="hidden" name="organizationId" value={organizationId} />
        <input type="hidden" name="projectId" value={projectId} />
        <input type="hidden" name="statementLineId" value={line.line_id} />
        <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
        <label>
          الدفعة المطابقة ({accountName})
          <select name="paymentId" required value={selected} onChange={(event) => setSelected(event.target.value)}>
            <option value="" disabled>اختر الدفعة</option>
            {candidates.map((payment) => (
              <option key={payment.payment_id} value={payment.payment_id}>
                {payment.payment_date} — {formatMinorUnits(payment.amount_minor_units, payment.currency)}
              </option>
            ))}
          </select>
        </label>
        {candidates.length === 0 && (
          <p className="muted">لا توجد دفعات نشطة غير مطابقة بنفس الحساب والعملة.</p>
        )}
        {state.error && <p className="error" role="alert">{state.error}</p>}
        <button className="secondary" disabled={pending || !selected}>
          {pending ? 'جارٍ المطابقة…' : 'مطابقة واحدة-بواحد'}
        </button>
      </form>
    </details>
  );
}

export function VoidMatchForm({
  organizationId,
  projectId,
  matchId,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  matchId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(voidReconciliationCommand, { error: undefined, successCount: 0 });
  const [reason, setReason] = useState('');
  const idempotencyKey = useCommandIdempotencyKey('void', state, commandNonce);
  return (
    <details className="stack">
      <summary>إلغاء المطابقة</summary>
      <form action={action} className="stack">
        <input type="hidden" name="organizationId" value={organizationId} />
        <input type="hidden" name="projectId" value={projectId} />
        <input type="hidden" name="matchId" value={matchId} />
        <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
        <label>
          سبب الإلغاء
          <input name="reason" required minLength={3} maxLength={500} value={reason}
            onChange={(event) => setReason(event.target.value)} placeholder="مثال: مطابقة خاطئة" />
        </label>
        {state.error && <p className="error" role="alert">{state.error}</p>}
        <button className="secondary" disabled={pending || reason.trim().length < 3}>
          {pending ? 'جارٍ الإلغاء…' : 'إلغاء المطابقة'}
        </button>
      </form>
    </details>
  );
}

export function ReversePaymentForm({
  organizationId,
  projectId,
  payment,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  payment: PaymentStatus;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(reverseJournalBatchCommand, { error: undefined, successCount: 0 });
  const [reason, setReason] = useState('');
  const idempotencyKey = useCommandIdempotencyKey('revpay', state, commandNonce);
  return (
    <details className="stack">
      <summary>عكس الدفعة</summary>
      <form action={action} className="stack">
        <input type="hidden" name="organizationId" value={organizationId} />
        <input type="hidden" name="projectId" value={projectId} />
        <input type="hidden" name="batchId" value={payment.batch_id} />
        <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
        <label>
          سبب العكس
          <input name="reason" required minLength={3} maxLength={500} value={reason}
            onChange={(event) => setReason(event.target.value)} placeholder="مثال: دفعة مسجلة بالخطأ" />
        </label>
        {state.error && <p className="error" role="alert">{state.error}</p>}
        <button className="secondary" disabled={pending || reason.trim().length < 3}>
          {pending ? 'جارٍ العكس…' : 'عكس الدفعة'}
        </button>
      </form>
    </details>
  );
}
