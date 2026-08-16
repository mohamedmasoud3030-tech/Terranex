'use client';

import { useActionState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import { recordProjectDecision, recordProjectRisk, resolveProjectRisk } from '@/features/governance/actions';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';

const initial: ActionState = {};
type Context = { organizationId: string; projectId: string; commandNonce: string };
type Member = { user_id: string; label: string };

function Result({ state, pending, label }: { state: ActionState; pending: boolean; label: string }) {
  return <>{state.error ? <p className="error" role="alert">{state.error}</p> : null}{!state.error && (state.successCount ?? 0) > 0 ? <p className="status" role="status">تم الحفظ في السجل غير القابل للتعديل.</p> : null}<button disabled={pending}>{pending ? 'جارٍ الحفظ…' : label}</button></>;
}
function Hidden({ organizationId, projectId, idempotencyKey }: { organizationId: string; projectId: string; idempotencyKey: string }) {
  return <><input type="hidden" name="organizationId" value={organizationId}/><input type="hidden" name="projectId" value={projectId}/><input type="hidden" name="idempotencyKey" value={idempotencyKey}/></>;
}

export function RiskForm({ organizationId, projectId, commandNonce, members }: Context & { members: Member[] }) {
  const [state, action, pending] = useActionState(recordProjectRisk, initial);
  const key = useCommandIdempotencyKey('r2-risk', state, commandNonce);
  return <form action={action} className="form-grid"><Hidden {...{organizationId, projectId, idempotencyKey:key}}/>
    <label>عنوان الخطر<input name="title" required minLength={3} maxLength={160}/></label>
    <label>الخطورة<select name="severity" defaultValue="MEDIUM"><option value="LOW">منخفض</option><option value="MEDIUM">متوسط</option><option value="HIGH">مرتفع</option><option value="CRITICAL">حرج</option></select></label>
    <label className="full">الوصف<textarea name="description" required minLength={3} maxLength={2000}/></label>
    <label>المسؤول<select name="ownerUserId" required defaultValue=""><option value="" disabled>اختر عضوًا نشطًا</option>{members.map(m=><option key={m.user_id} value={m.user_id}>{m.label}</option>)}</select></label>
    <label>تاريخ الاستحقاق<input type="date" name="dueDate"/></label>
    <label className="full">مرجع المصدر (اختياري)<input name="sourceReference" minLength={3} maxLength={200}/></label>
    <div className="full"><Result {...{state,pending}} label="تسجيل الخطر"/></div>
  </form>;
}

export function ResolveRiskForm({ organizationId, projectId, riskItemId, commandNonce }: Context & { riskItemId: string }) {
  const [state, action, pending] = useActionState(resolveProjectRisk, initial);
  const key = useCommandIdempotencyKey(`r2-resolve-${riskItemId}`, state, commandNonce);
  return <form action={action} className="form-grid compact"><Hidden {...{organizationId,projectId,idempotencyKey:key}}/><input type="hidden" name="riskItemId" value={riskItemId}/><label>نتيجة الحسم<textarea name="outcome" required minLength={3} maxLength={1000}/></label><label>مرجع دليل الحسم (اختياري)<input name="evidenceReference" minLength={3} maxLength={200}/></label><div><Result {...{state,pending}} label="حسم الخطر"/></div></form>;
}

export function DecisionForm({ organizationId, projectId, commandNonce }: Context) {
  const [state, action, pending] = useActionState(recordProjectDecision, initial);
  const key = useCommandIdempotencyKey('r2-decision', state, commandNonce);
  return <form action={action} className="form-grid"><Hidden {...{organizationId,projectId,idempotencyKey:key}}/>
    <label>عنوان القرار<input name="title" required minLength={3} maxLength={160}/></label><label>تاريخ القرار<input type="date" name="decisionDate" required/></label>
    <label className="full">نص القرار<textarea name="decisionText" required minLength={3} maxLength={4000}/></label><label className="full">المبرر (اختياري)<textarea name="rationale" minLength={3} maxLength={4000}/></label>
    <label className="full">مرجع الدليل<input name="evidenceReference" required minLength={3} maxLength={200}/></label><p className="muted full">القرار واقعة تاريخية غير قابلة للتعديل أو الحذف. سجّل واقعة جديدة لأي تصحيح لاحق.</p><div className="full"><Result {...{state,pending}} label="تسجيل القرار"/></div>
  </form>;
}
