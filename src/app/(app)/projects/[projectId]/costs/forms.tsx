'use client';

import { useActionState, useMemo, useState } from 'react';
import type { Party } from '@/features/funding/queries';
import type { CashAccountPosition } from '@/features/finance/queries';
import type { ActionState } from '@/features/auth/actions';
import { formatMinorUnits } from '@/shared/money';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import {
  approvePayment,
  authorizeObligation,
  createObligation,
  deleteObligationDraft,
  preparePayment,
  reverseJournalBatch,
} from '@/features/finance/actions';
import {
  achieveMilestone,
  createMilestone,
  openDispute,
  releaseRetention,
  resolveDispute,
  setObligationSchedule,
  setObligationTerms,
} from '@/features/control/actions';

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
  const [state, action, pending] = useActionState(preparePayment, { error: undefined });
  const idempotencyKey = useMemo(() => `pay-proposal-${crypto.randomUUID()}`, []);
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
}: {
  organizationId: string;
  projectId: string;
  paymentProposalId: string;
}) {
  const [state, action, pending] = useActionState(approvePayment, { error: undefined });
  const idempotencyKey = useMemo(() => `pay-approval-${crypto.randomUUID()}`, []);
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

// ---------------------------------------------------------------------------
// F3 — Contract finance forms (milestones, payment terms, schedules,
// disputes, retention). Every form owns the canonical idempotency-key
// lifecycle: the key survives failed retries and rotates only after a
// confirmed server success.
// ---------------------------------------------------------------------------

const controlInitialState: ActionState = {};

export function MilestoneForm({
  organizationId,
  projectId,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(createMilestone, controlInitialState);
  const idempotencyKey = useCommandIdempotencyKey('milestone-create', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <div className="grid">
        <label>
          رمز الإنجاز
          <input name="code" required minLength={2} maxLength={40} placeholder="MS-01" />
        </label>
        <label>
          وصف الإنجاز
          <input name="labelAr" required minLength={2} maxLength={200} placeholder="تسليم المرحلة الأولى" />
        </label>
        <label>
          التاريخ المخطط
          <input type="date" name="plannedDate" required />
        </label>
      </div>
      <label>
        مرجع المستند (اختياري)
        <input name="evidenceReference" maxLength={500} />
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? 'جارٍ الإنشاء…' : 'إضافة إنجاز'}</button>
    </form>
  );
}

export function AchieveMilestoneButton({
  organizationId,
  projectId,
  milestoneId,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  milestoneId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(achieveMilestone, controlInitialState);
  const idempotencyKey = useCommandIdempotencyKey('milestone-achieve', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="milestoneId" value={milestoneId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        تاريخ الإنجاز الفعلي
        <input type="date" name="achievedDate" required />
      </label>
      <label>
        مرجع المستند
        <input name="evidenceReference" maxLength={500} placeholder="محضر الاستلام" />
      </label>
      <button className="secondary" disabled={pending}>
        {pending ? 'جارٍ الاعتماد…' : 'اعتماد الإنجاز (يقفل الحقيقة)'}
      </button>
      {state.error && <p className="error" role="alert">{state.error}</p>}
    </form>
  );
}

export function ObligationTermsForm({
  organizationId,
  projectId,
  obligationId,
  currency,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  obligationId: string;
  currency: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(setObligationTerms, controlInitialState);
  const idempotencyKey = useCommandIdempotencyKey('terms-set', state, commandNonce);
  const [termsType, setTermsType] = useState('FIXED_DATE');
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="obligationId" value={obligationId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        نوع شروط الدفع
        <select name="termsType" value={termsType} onChange={(event) => setTermsType(event.target.value)}>
          <option value="FIXED_DATE">تاريخ استحقاق ثابت</option>
          <option value="NET_DAYS">أيام بعد تاريخ المعاملة</option>
          <option value="MILESTONE_SCHEDULE">جدولة مرتبطة بإنجازات</option>
        </select>
      </label>
      {termsType === 'FIXED_DATE' ? (
        <label>
          تاريخ الاستحقاق
          <input type="date" name="dueDate" required />
        </label>
      ) : null}
      {termsType === 'NET_DAYS' ? (
        <label>
          عدد الأيام الصافية
          <input type="number" name="netDays" min={1} max={730} required placeholder="30" />
        </label>
      ) : null}
      <label>
        حجز الضمان ({currency} — اختياري، أقل من إجمالي الالتزام)
        <input name="retention" inputMode="decimal" defaultValue="0" placeholder="0.00" />
      </label>
      <label>
        مرجع المستند (اختياري)
        <input name="evidenceReference" maxLength={500} placeholder="عقد أو أمر شراء" />
      </label>
      <label>
        ملاحظات (اختياري)
        <input name="notes" maxLength={1000} />
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button className="secondary" disabled={pending}>
        {pending ? 'جارٍ الحفظ…' : 'حفظ شروط الدفع'}
      </button>
    </form>
  );
}

export function ObligationScheduleForm({
  organizationId,
  projectId,
  obligationId,
  milestones,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  obligationId: string;
  milestones: { milestone_id: string; code: string; label_ar: string }[];
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(setObligationSchedule, controlInitialState);
  const idempotencyKey = useCommandIdempotencyKey('schedule-set', state, commandNonce);
  const [rows, setRows] = useState([{ lineNumber: 1, dueDate: '', amount: '', milestoneId: '', retention: false }]);
  const linesJson = JSON.stringify(
    rows.filter((row) => row.amount.trim() !== '').map((row) => ({
      line_number: Number(row.lineNumber),
      due_date: row.dueDate || null,
      amount_minor_units: row.amount.trim(),
      milestone_id: row.retention ? null : (row.milestoneId || null),
      is_retention_line: row.retention,
    })),
  );
  const addRow = () => setRows((prev) => [
    ...prev,
    { lineNumber: prev.length + 1, dueDate: '', amount: '', milestoneId: '', retention: false },
  ]);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="obligationId" value={obligationId} />
      <input type="hidden" name="linesJson" value={linesJson} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      {rows.map((row, index) => (
        <div className="grid" key={index}>
          <label>
            الرقم
            <input type="number" value={row.lineNumber} readOnly />
          </label>
          <label>
            تاريخ الاستحقاق
            <input type="date" value={row.dueDate}
              onChange={(event) => setRows((prev) => prev.map((r, i) => (i === index ? { ...r, dueDate: event.target.value } : r)))} />
          </label>
          <label>
            المبلغ (بالوحدات الصغرى)
            <input inputMode="numeric" value={row.amount}
              onChange={(event) => setRows((prev) => prev.map((r, i) => (i === index ? { ...r, amount: event.target.value } : r)))} />
          </label>
          <label>
            الإنجاز المرتبط
            <select value={row.milestoneId} disabled={row.retention}
              onChange={(event) => setRows((prev) => prev.map((r, i) => (i === index ? { ...r, milestoneId: event.target.value } : r)))}>
              <option value="">بدون</option>
              {milestones.map((m) => (
                <option key={m.milestone_id} value={m.milestone_id}>{m.code} — {m.label_ar}</option>
              ))}
            </select>
          </label>
          <label>
            <input type="checkbox" checked={row.retention}
              onChange={(event) => setRows((prev) => prev.map((r, i) => (i === index ? { ...r, retention: event.target.checked } : r)))} />
            سطر حجز ضمان
          </label>
        </div>
      ))}
      <button type="button" className="secondary" onClick={addRow}>إضافة سطر</button>
      <p className="muted">
        استبدال كامل لبنود الجدولة (للالتزام المسود فقط). الإجمالي لا يتجاوز مبلغ الالتزام،
        وبنود الحجز لا تتجاوز الحجز المعلن في الشروط.
      </p>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button className="secondary" disabled={pending || linesJson === '[]'}>
        {pending ? 'جارٍ الحفظ…' : 'حفظ جدولة الدفع'}
      </button>
    </form>
  );
}

export function OpenDisputeForm({
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
  const [state, action, pending] = useActionState(openDispute, controlInitialState);
  const idempotencyKey = useCommandIdempotencyKey('dispute-open', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="obligationId" value={obligationId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        سبب النزاع
        <textarea name="reason" required minLength={3} maxLength={1000} placeholder="خلاف على الكمية أو الجودة" />
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button className="danger" disabled={pending}>
        {pending ? 'جارٍ الفتح…' : 'فتح نزاع (يحظر الدفع مؤقتًا)'}
      </button>
    </form>
  );
}

export function ResolveDisputeForm({
  organizationId,
  projectId,
  disputeId,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  disputeId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(resolveDispute, controlInitialState);
  const idempotencyKey = useCommandIdempotencyKey('dispute-resolve', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="disputeId" value={disputeId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        ملاحظة التسوية
        <textarea name="resolutionNote" required minLength={3} maxLength={1000} placeholder="ما تم الاتفاق عليه" />
      </label>
      <label>
        مرجع المستند (مطلوب إذا كانت سياسة الاعتماد تشترطه)
        <input name="evidenceReference" maxLength={500} />
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button className="secondary" disabled={pending}>
        {pending ? 'جارٍ التسوية…' : 'تسوية النزاع'}
      </button>
    </form>
  );
}

export function RetentionReleaseForm({
  organizationId,
  projectId,
  obligationId,
  currency,
  milestones,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  obligationId: string;
  currency: string;
  milestones: { milestone_id: string; code: string; label_ar: string; status: string }[];
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(releaseRetention, controlInitialState);
  const idempotencyKey = useCommandIdempotencyKey('retention-release', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="obligationId" value={obligationId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        مبلغ الإفراج ({currency})
        <input name="amount" inputMode="decimal" required placeholder="0.00" />
      </label>
      <label>
        تاريخ الإفراج
        <input type="date" name="releaseDate" required />
      </label>
      <label>
        سبب الإفراج
        <input name="reason" required minLength={3} maxLength={1000} placeholder="اكتمال فترة الضمان" />
      </label>
      <label>
        مرجع المستند (مطلوب إذا كانت سياسة الاعتماد تشترطه)
        <input name="evidenceReference" maxLength={500} />
      </label>
      <label>
        الإنجاز المرتبط (اختياري — يجب أن يكون معتمدًا ومن نفس المشروع)
        <select name="milestoneId">
          <option value="">بدون إنجاز</option>
          {milestones.filter((m) => m.status === 'ACHIEVED').map((m) => (
            <option key={m.milestone_id} value={m.milestone_id}>{m.code} — {m.label_ar}</option>
          ))}
        </select>
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button className="secondary" disabled={pending}>
        {pending ? 'جارٍ الإفراج…' : 'الإفراج عن الحجز'}
      </button>
    </form>
  );
}
