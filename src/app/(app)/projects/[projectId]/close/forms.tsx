'use client';

import { useActionState, useId } from 'react';
import { useFormStatus } from 'react-dom';
import type { ActionState } from '@/features/auth/actions';
import {
  approveCloseExceptionAction,
  approveCloseRunAction,
  approveCorrectionAction,
  executeCorrectionAction,
  prepareCloseRunAction,
  reopenPeriodAction,
  requestCloseExceptionAction,
  requestCorrectionAction,
} from '@/features/close/actions';

const initial: ActionState = {};

function useStableIdempotencyKey(prefix: string): string {
  // useId is render-stable; combined with a form prefix it gives a key the
  // user can replace before submit. The key is at least 8 characters.
  const reactId = useId().replace(/[^a-zA-Z0-9]/g, '');
  return `${prefix}-${reactId}-idempotency-key`.slice(0, 120);
}

function useTodayDate(): string {
  // Render-stable placeholder; the actual date is set by the server when
  // the form is rendered. The operator can correct it before submit.
  return '2026-08-11';
}

function Submit({ label, pending }: { label: string; pending: boolean }) {
  return (
    <button type="submit" className="button" disabled={pending}>
      {pending ? 'جارٍ التنفيذ…' : label}
    </button>
  );
}

function ErrorBanner({ state }: { state: ActionState }) {
  if (!state.error) return null;
  return <p className="error" role="alert">{state.error}</p>;
}

function useFormActionState(action: (state: ActionState, fd: FormData) => Promise<ActionState>) {
  const [state, dispatch] = useActionState(action, initial);
  const { pending } = useFormStatus();
  return { state, dispatch, pending };
}

export function PrepareCloseForm({
  organizationId, projectId, periodId, disabled,
}: { organizationId: string; projectId: string; periodId: string; disabled?: boolean }) {
  const { state, dispatch, pending } = useFormActionState(prepareCloseRunAction);
  const defaultKey = useStableIdempotencyKey('prep');
  return (
    <form action={dispatch} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="periodId" value={periodId} />
      <label>
        <span>ملاحظات (اختياري)</span>
        <textarea name="notes" rows={2} maxLength={2000} />
      </label>
      <label>
        <span>مفتاح إعادة المحاولة</span>
        <input name="idempotencyKey" type="text" minLength={8} maxLength={120} required defaultValue={defaultKey} />
      </label>
      <ErrorBanner state={state} />
      <Submit label="بدء تحضير الإغلاق" pending={pending} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function ApproveCloseForm({
  organizationId, projectId, closeRunId, disabled,
}: { organizationId: string; projectId: string; closeRunId: string; disabled?: boolean }) {
  const { state, dispatch, pending } = useFormActionState(approveCloseRunAction);
  const defaultKey = useStableIdempotencyKey('approve');
  return (
    <form action={dispatch} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="closeRunId" value={closeRunId} />
      <label>
        <span>مفتاح إعادة المحاولة</span>
        <input name="idempotencyKey" type="text" minLength={8} maxLength={120} required defaultValue={defaultKey} />
      </label>
      <ErrorBanner state={state} />
      <Submit label="اعتماد الإغلاق وقفل الفترة" pending={pending} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function RequestExceptionForm({
  organizationId, projectId, closeRunId, gateCode, disabled,
}: { organizationId: string; projectId: string; closeRunId: string; gateCode: string; disabled?: boolean }) {
  const { state, dispatch, pending } = useFormActionState(requestCloseExceptionAction);
  return (
    <form action={dispatch} className="stack">
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
      <Submit label="طلب استثناء للبوابة" pending={pending} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function ApproveExceptionForm({
  organizationId, projectId, exceptionId, disabled,
}: { organizationId: string; projectId: string; exceptionId: string; disabled?: boolean }) {
  const { state, dispatch, pending } = useFormActionState(approveCloseExceptionAction);
  const defaultKey = useStableIdempotencyKey('exc');
  return (
    <form action={dispatch} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="exceptionId" value={exceptionId} />
      <label>
        <span>مفتاح إعادة المحاولة</span>
        <input name="idempotencyKey" type="text" minLength={8} maxLength={120} required defaultValue={defaultKey} />
      </label>
      <ErrorBanner state={state} />
      <Submit label="اعتماد الاستثناء" pending={pending} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function ReopenForm({
  organizationId, projectId, periodId, disabled,
}: { organizationId: string; projectId: string; periodId: string; disabled?: boolean }) {
  const { state, dispatch, pending } = useFormActionState(reopenPeriodAction);
  return (
    <form action={dispatch} className="stack">
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
      <Submit label="إعادة فتح الفترة كنسخة جديدة" pending={pending} />
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
  const { state, dispatch, pending } = useFormActionState(requestCorrectionAction);
  return (
    <form action={dispatch} className="stack">
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
      <Submit label="تسجيل طلب التصحيح" pending={pending} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function ApproveCorrectionForm({
  organizationId, projectId, correctionRequestId, disabled,
}: { organizationId: string; projectId: string; correctionRequestId: string; disabled?: boolean }) {
  const { state, dispatch, pending } = useFormActionState(approveCorrectionAction);
  const defaultKey = useStableIdempotencyKey('corr');
  return (
    <form action={dispatch} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="correctionRequestId" value={correctionRequestId} />
      <label>
        <span>مفتاح إعادة المحاولة</span>
        <input name="idempotencyKey" type="text" minLength={8} maxLength={120} required defaultValue={defaultKey} />
      </label>
      <ErrorBanner state={state} />
      <Submit label="اعتماد طلب التصحيح" pending={pending} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}

export function ExecuteCorrectionForm({
  organizationId, projectId, correctionRequestId, disabled,
}: { organizationId: string; projectId: string; correctionRequestId: string; disabled?: boolean }) {
  const { state, dispatch, pending } = useFormActionState(executeCorrectionAction);
  const defaultKey = useStableIdempotencyKey('exec');
  const today = useTodayDate();
  return (
    <form action={dispatch} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="correctionRequestId" value={correctionRequestId} />
      <label>
        <span>تاريخ التصحيح (داخل الفترة المفتوحة)</span>
        <input name="correctionDate" type="date" required defaultValue={today} />
      </label>
      <label>
        <span>مفتاح إعادة المحاولة</span>
        <input name="idempotencyKey" type="text" minLength={8} maxLength={120} required defaultValue={defaultKey} />
      </label>
      <ErrorBanner state={state} />
      <Submit label="تنفيذ التصحيح" pending={pending} />
      {disabled && <p className="muted">الإجراء متاح لمالك المنظمة فقط.</p>}
    </form>
  );
}
