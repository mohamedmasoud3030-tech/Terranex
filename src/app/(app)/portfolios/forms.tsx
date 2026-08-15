'use client';

import { useActionState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import type { PortfolioStatus } from '@/features/portfolios/schema';
import {
  assignProjectToPortfolio,
  createPortfolio,
  moveProjectToPortfolio,
  removeProjectFromPortfolio,
  transitionPortfolio,
  updatePortfolio,
} from '@/features/portfolios/actions';

const initialState: ActionState = {};

type MemberOption = Readonly<{ user_id: string; label: string }>;
type ProjectOption = Readonly<{ id: string; label: string }>;
type PortfolioOption = Readonly<{ id: string; name: string }>;

function SubmitResult({
  state,
  pending,
  label,
  successMessage,
}: Readonly<{ state: ActionState; pending: boolean; label: string; successMessage?: string }>) {
  return (
    <>
      {state.error ? <p className="error" role="alert">{state.error}</p> : null}
      {!state.error && (state.successCount ?? 0) > 0 && successMessage ? (
        <p className="muted" role="status">{successMessage}</p>
      ) : null}
      <button type="submit" disabled={pending}>{pending ? 'جارٍ الحفظ…' : label}</button>
    </>
  );
}

export function PortfolioForm({
  organizationId,
  commandNonce,
  members,
}: Readonly<{ organizationId: string; commandNonce: string; members: readonly MemberOption[] }>) {
  const [state, action, pending] = useActionState(createPortfolio, initialState);
  const idempotencyKey = useCommandIdempotencyKey('pf-create', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        اسم المحفظة
        <input name="name" required minLength={2} maxLength={120} autoFocus />
      </label>
      <label>
        الغرض الإداري <span className="muted">(اختياري)</span>
        <textarea name="description" maxLength={2000} />
      </label>
      <label>
        المدير المسؤول <span className="muted">(اختياري)</span>
        <select name="responsibleManagerId" defaultValue="">
          <option value="">بدون مدير مسؤول</option>
          {members.map((m) => (
            <option key={m.user_id} value={m.user_id}>{m.label}</option>
          ))}
        </select>
      </label>
      <SubmitResult state={state} pending={pending} label="إنشاء المحفظة" />
    </form>
  );
}

export function MetadataForm({
  organizationId,
  portfolioId,
  commandNonce,
  initialName,
  initialDescription,
  initialManagerId,
  members,
}: Readonly<{
  organizationId: string;
  portfolioId: string;
  commandNonce: string;
  initialName: string;
  initialDescription: string;
  initialManagerId: string | null;
  members: readonly MemberOption[];
}>) {
  const [state, action, pending] = useActionState(updatePortfolio, initialState);
  const idempotencyKey = useCommandIdempotencyKey('pf-update', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="portfolioId" value={portfolioId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        اسم المحفظة
        <input name="name" required minLength={2} maxLength={120} defaultValue={initialName} />
      </label>
      <label>
        الغرض الإداري <span className="muted">(اختياري)</span>
        <textarea name="description" maxLength={2000} defaultValue={initialDescription} />
      </label>
      <label>
        المدير المسؤول <span className="muted">(اختياري)</span>
        <select name="responsibleManagerId" defaultValue={initialManagerId ?? ''}>
          <option value="">بدون مدير مسؤول</option>
          {members.map((m) => (
            <option key={m.user_id} value={m.user_id}>{m.label}</option>
          ))}
        </select>
      </label>
      <SubmitResult
        state={state}
        pending={pending}
        label="حفظ البيانات الإدارية"
        successMessage="تم حفظ البيانات الإدارية للمحفظة."
      />
    </form>
  );
}

export function TransitionForm({
  organizationId,
  portfolioId,
  commandNonce,
  expectedStatus,
  newStatus,
  buttonLabel,
}: Readonly<{
  organizationId: string;
  portfolioId: string;
  commandNonce: string;
  expectedStatus: PortfolioStatus;
  newStatus: PortfolioStatus;
  buttonLabel: string;
}>) {
  const [state, action, pending] = useActionState(transitionPortfolio, initialState);
  const idempotencyKey = useCommandIdempotencyKey(`pf-${newStatus.toLowerCase()}`, state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="portfolioId" value={portfolioId} />
      <input type="hidden" name="expectedStatus" value={expectedStatus} />
      <input type="hidden" name="newStatus" value={newStatus} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        سبب تغيير الحالة
        <textarea name="reason" required minLength={3} maxLength={500} />
      </label>
      <SubmitResult
        state={state}
        pending={pending}
        label={buttonLabel}
        successMessage="تم تحديث حالة المحفظة."
      />
    </form>
  );
}

export function AssignProjectForm({
  organizationId,
  portfolioId,
  commandNonce,
  projects,
}: Readonly<{
  organizationId: string;
  portfolioId: string;
  commandNonce: string;
  projects: readonly ProjectOption[];
}>) {
  const [state, action, pending] = useActionState(assignProjectToPortfolio, initialState);
  const idempotencyKey = useCommandIdempotencyKey('pf-assign', state, commandNonce);
  if (projects.length === 0) {
    return (
      <p className="muted">
        لا توجد مشاريع متاحة للإسناد. كل مشاريع المنظمة مُسندة بالفعل إلى محفظة، أو لا توجد
        مشاريع بعد.
      </p>
    );
  }
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="portfolioId" value={portfolioId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        اختر مشروعًا من المنظمة
        <select name="projectId" required defaultValue="">
          <option value="" disabled>اختر مشروعًا…</option>
          {projects.map((p) => (
            <option key={p.id} value={p.id}>{p.label}</option>
          ))}
        </select>
      </label>
      <SubmitResult
        state={state}
        pending={pending}
        label="إسناد المشروع إلى المحفظة"
        successMessage="تم إسناد المشروع إلى المحفظة."
      />
    </form>
  );
}

export function RemoveProjectForm({
  organizationId,
  portfolioId,
  projectId,
  commandNonce,
}: Readonly<{
  organizationId: string;
  portfolioId: string;
  projectId: string;
  commandNonce: string;
}>) {
  const [state, action, pending] = useActionState(removeProjectFromPortfolio, initialState);
  const idempotencyKey = useCommandIdempotencyKey(
    `pf-remove-${projectId}`,
    state,
    commandNonce,
  );
  return (
    <details>
      <summary>إزالة المشروع من المحفظة</summary>
      <form action={action} className="stack" style={{ marginTop: 10 }}>
        <input type="hidden" name="organizationId" value={organizationId} />
        <input type="hidden" name="portfolioId" value={portfolioId} />
        <input type="hidden" name="projectId" value={projectId} />
        <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
        <label>
          سبب الإزالة
          <textarea name="reason" required minLength={3} maxLength={500} />
        </label>
        <SubmitResult
          state={state}
          pending={pending}
          label="تأكيد الإزالة"
          successMessage="تمت إزالة المشروع من المحفظة."
        />
      </form>
    </details>
  );
}

export function MoveProjectForm({
  organizationId,
  projectId,
  commandNonce,
  targetPortfolios,
}: Readonly<{
  organizationId: string;
  projectId: string;
  commandNonce: string;
  targetPortfolios: readonly PortfolioOption[];
}>) {
  const [state, action, pending] = useActionState(moveProjectToPortfolio, initialState);
  const idempotencyKey = useCommandIdempotencyKey(`pf-move-${projectId}`, state, commandNonce);
  if (targetPortfolios.length === 0) {
    return <p className="muted">لا توجد محفظة نشطة أخرى متاحة للنقل.</p>;
  }
  return (
    <details>
      <summary>نقل المشروع إلى محفظة أخرى</summary>
      <form action={action} className="stack" style={{ marginTop: 10 }}>
        <input type="hidden" name="organizationId" value={organizationId} />
        <input type="hidden" name="projectId" value={projectId} />
        <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
        <label>
          المحفظة الوجهة
          <select name="targetPortfolioId" required defaultValue="">
            <option value="" disabled>اختر محفظة…</option>
            {targetPortfolios.map((p) => (
              <option key={p.id} value={p.id}>{p.name}</option>
            ))}
          </select>
        </label>
        <label>
          سبب النقل
          <textarea name="reason" required minLength={3} maxLength={500} />
        </label>
        <SubmitResult
          state={state}
          pending={pending}
          label="تأكيد النقل"
          successMessage="تم نقل المشروع إلى المحفظة الجديدة."
        />
      </form>
    </details>
  );
}
