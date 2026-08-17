'use client';

import { useActionState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import {
  createAccountingPeriodAction,
  prepareCloseRunAction,
  reopenPeriodAction,
  requestCloseExceptionAction,
  requestCorrectionAction,
} from '@/features/close/actions';
import {
  approveCloseExceptionAction,
  approveCloseRunAction,
  approveCorrectionAction,
  executeCorrectionAction,
} from '@/features/close/command-actions';
import { commandIdempotencyKey } from '@/shared/idempotency';
import { useResolvedCommandNonce } from '@/shared/idempotency/use-resolved-command-nonce';

const initial: ActionState = {};

function useCommandKey(prefix: string, state: ActionState): string | null {
  const nonce = useResolvedCommandNonce();
  if (!nonce) return null;
  return commandIdempotencyKey(prefix, nonce, state.successCount ?? 0);
}

function Submit({
  label,
  pending,
  disabled = false,
}: {
  label: string;
  pending: boolean;
  disabled?: boolean;
}) {
  return (
    <button type="submit" className="button" disabled={pending || disabled}>
      {pending ? 'جارٍ التنفيذ…' : label}
    </button>
  );
}

function ErrorBanner({ state }: { state: ActionState }) {
  if (!state.error) return null;
  return <p className="error" role="alert">{state.error}</p>;
}

function CommandKey({ value }: { value: string | null }) {
  if (!value) return null;
  return <input type="hidden" name="idempotencyKey" value={value} />;
}

export function CreateAccountingPeriodForm({
  organizationId, projectId, startDate, endDate, disabled,
}: {
  organizationId: string;
  projectId: string;
  startDate?: string;
  endDate?: string;
  disabled?: boolean;
}) {
  const [state, action, pending] = useActionState(createAccountingPeriodAction, initial);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <label>
        <span>بداية الفترة</span>
        <input type="date" name="startDate" required defaultValue={startDate} />
      </label>
      <label>
        <span>نهاية الفترة</span>
        <input type="date" name="endDate" required defaultValue={endDate} />
      </label>
      <p className="muted">الفترة المفتوحة هي النافذة الوحيدة المسموح بالترحيل داخلها، بما في ذلك القيد الافتتاحي.</p>
      <ErrorBanner state={state} />
      <Submit label="فتح فترة محاسبية" pending={pending} disabled={disabled} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function PrepareCloseForm({
  organizationId, projectId, periodId, disabled,
}: { organizationId: string; projectId: string; periodId: string; disabled?: boolean }) {
  const [state, action, pending] = useActionState(prepareCloseRunAction, initial);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="periodId" value={periodId} />
      <label>
        <span>ملاحظات (اختياري)</span>
        <textarea name="notes" rows={2} maxLength={2000} />
      </label>
      <p className="muted">تحضير الإغلاق محمي حاليًا بقيود قاعدة البيانات، لكنه لا يملك بعد عقد replay بمفتاح idempotency. لا تعرض الواجهة مفتاحًا وهميًا.</p>
      <ErrorBanner state={state} />
      <Submit label="بدء تحضير الإغلاق" pending={pending} disabled={disabled} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function ApproveCloseForm({
  organizationId, projectId, closeRunId, disabled,
}: { organizationId: string; projectId: string; closeRunId: string; disabled?: boolean }) {
  const [state, action, pending] = useActionState(approveCloseRunAction, initial);
  const key = useCommandKey('close-approve', state);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="closeRunId" value={closeRunId} />
      <CommandKey value={key} />
      <ErrorBanner state={state} />
      <Submit label="اعتماد الإغلاق وقفل الفترة" pending={pending} disabled={Boolean(disabled) || !key} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function RequestExceptionForm({
  organizationId, projectId, closeRunId, gateCode, disabled,
}: { organizationId: string; projectId: string; closeRunId: string; gateCode: string; disabled?: boolean }) {
  const [state, action, pending] = useActionState(requestCloseExceptionAction, initial);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="closeRunId" value={closeRunId} />
      <input type="hidden" name="gateCode" value={gateCode} />
      <label>
        <span>السبب (5 أحرف على الأقل)</span>
        <textarea name="reason" rows={2} minLength={5} maxLength={2000} required />
      </label>
      <label>
        <span>مرجع الدليل (3 أحرف على الأقل)</span>
        <input name="evidenceReference" type="text" minLength={3} maxLength={200} required />
      </label>
      <label>
        <span>تعليق الأهمية (اختياري)</span>
        <textarea name="materialityComment" rows={2} maxLength={2000} />
      </label>
      <ErrorBanner state={state} />
      <Submit label="طلب استثناء للبوابة" pending={pending} disabled={disabled} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function ApproveExceptionForm({
  organizationId, projectId, exceptionId, disabled,
}: { organizationId: string; projectId: string; exceptionId: string; disabled?: boolean }) {
  const [state, action, pending] = useActionState(approveCloseExceptionAction, initial);
  const key = useCommandKey('close-exception-approve', state);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="exceptionId" value={exceptionId} />
      <CommandKey value={key} />
      <ErrorBanner state={state} />
      <Submit label="اعتماد الاستثناء" pending={pending} disabled={Boolean(disabled) || !key} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function ReopenForm({
  organizationId, projectId, periodId, disabled,
}: { organizationId: string; projectId: string; periodId: string; disabled?: boolean }) {
  const [state, action, pending] = useActionState(reopenPeriodAction, initial);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="periodId" value={periodId} />
      <label>
        <span>سبب إعادة الفتح (5 أحرف على الأقل)</span>
        <textarea name="reason" rows={2} minLength={5} maxLength={2000} required />
      </label>
      <label>
        <span>مرجع الدليل (3 أحرف على الأقل)</span>
        <input name="evidenceReference" type="text" minLength={3} maxLength={200} required />
      </label>
      <ErrorBanner state={state} />
      <Submit label="إعادة فتح الفترة كنسخة جديدة" pending={pending} disabled={disabled} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function RequestCorrectionForm({
  organizationId, projectId, targetBatchId, sourcePeriodId, correctionPeriodId, disabled,
}: {
  organizationId: string; projectId: string; targetBatchId: string;
  sourcePeriodId: string; correctionPeriodId: string; disabled?: boolean;
}) {
  const [state, action, pending] = useActionState(requestCorrectionAction, initial);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="targetBatchId" value={targetBatchId} />
      <input type="hidden" name="sourcePeriodId" value={sourcePeriodId} />
      <input type="hidden" name="correctionPeriodId" value={correctionPeriodId} />
      <label>
        <span>السبب (5 أحرف على الأقل)</span>
        <textarea name="reason" rows={2} minLength={5} maxLength={2000} required />
      </label>
      <label>
        <span>مرجع الدليل (3 أحرف على الأقل)</span>
        <input name="evidenceReference" type="text" minLength={3} maxLength={200} required />
      </label>
      <ErrorBanner state={state} />
      <Submit label="تسجيل طلب التصحيح" pending={pending} disabled={disabled} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function ApproveCorrectionForm({
  organizationId, projectId, correctionRequestId, disabled,
}: { organizationId: string; projectId: string; correctionRequestId: string; disabled?: boolean }) {
  const [state, action, pending] = useActionState(approveCorrectionAction, initial);
  const key = useCommandKey('close-correction-approve', state);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="correctionRequestId" value={correctionRequestId} />
      <CommandKey value={key} />
      <ErrorBanner state={state} />
      <Submit label="اعتماد طلب التصحيح" pending={pending} disabled={Boolean(disabled) || !key} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function ExecuteCorrectionForm({
  organizationId, projectId, correctionRequestId, disabled,
}: { organizationId: string; projectId: string; correctionRequestId: string; disabled?: boolean }) {
  const [state, action, pending] = useActionState(executeCorrectionAction, initial);
  const key = useCommandKey('close-correction-execute', state);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="correctionRequestId" value={correctionRequestId} />
      <label>
        <span>تاريخ التصحيح (داخل الفترة المفتوحة)</span>
        <input name="correctionDate" type="date" required />
      </label>
      <CommandKey value={key} />
      <ErrorBanner state={state} />
      <Submit label="تنفيذ التصحيح" pending={pending} disabled={Boolean(disabled) || !key} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}
