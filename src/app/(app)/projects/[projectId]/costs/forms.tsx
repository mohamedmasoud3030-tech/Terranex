'use client';

import { useActionState, useState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import { deleteObligationDraft } from '@/features/finance/actions';
import {
  achieveMilestone,
  createMilestone,
  openDispute,
  releaseRetention,
  resolveDispute,
  setObligationSchedule,
  setObligationTerms,
} from '@/features/control/actions';

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
