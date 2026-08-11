'use client';

import { useActionState, useMemo, useState } from 'react';
import type { Contribution, PaymentStatus, BankStatementLineStatus } from '@/features/finance/queries';
import { formatMinorUnits } from '@/shared/money';
import {
  attachContributionCash,
  createCashAccount,
  importBankStatement,
  reconcilePayment,
  reverseJournalBatch,
  voidReconciliation,
} from '@/features/finance/actions';

export function CashAccountForm({
  organizationId,
  projectId,
  currency,
}: {
  organizationId: string;
  projectId: string;
  currency: string;
}) {
  const [state, action, pending] = useActionState(createCashAccount, { error: undefined });
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="currency" value={currency} />
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
}: {
  organizationId: string;
  projectId: string;
  contributions: Contribution[];
  cashAccountId: string;
}) {
  const [state, action, pending] = useActionState(attachContributionCash, { error: undefined });
  const [selected, setSelected] = useState('');
  const idempotencyKey = useMemo(() => `attach-${crypto.randomUUID()}`, []);
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
}: {
  organizationId: string;
  projectId: string;
  cashAccounts: { cash_account_id: string; name: string }[];
}) {
  const [state, action, pending] = useActionState(importBankStatement, { error: undefined });
  const idempotencyKey = useMemo(() => `import-${crypto.randomUUID()}`, []);
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
}: {
  organizationId: string;
  projectId: string;
  line: BankStatementLineStatus;
  payments: PaymentStatus[];
  accountName: string;
}) {
  const [state, action, pending] = useActionState(reconcilePayment, { error: undefined });
  const [selected, setSelected] = useState('');
  const idempotencyKey = useMemo(() => `recon-${crypto.randomUUID()}`, []);
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
}: {
  organizationId: string;
  projectId: string;
  matchId: string;
}) {
  const [state, action, pending] = useActionState(voidReconciliation, { error: undefined });
  const [reason, setReason] = useState('');
  const idempotencyKey = useMemo(() => `void-${crypto.randomUUID()}`, []);
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
}: {
  organizationId: string;
  projectId: string;
  payment: PaymentStatus;
}) {
  const [state, action, pending] = useActionState(reverseJournalBatch, { error: undefined });
  const [reason, setReason] = useState('');
  const idempotencyKey = useMemo(() => `revpay-${crypto.randomUUID()}`, []);
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
