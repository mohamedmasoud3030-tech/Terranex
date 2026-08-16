'use server';

import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import { createClient } from '@/shared/supabase/server';
import { projectDecisionSchema, projectRiskSchema, riskResolutionSchema } from './schema';

function message(raw?: string): string {
  const text = raw ?? '';
  if (text.includes('organization owner required')) return 'يتطلب حسم الخطر وتسجيل القرار صلاحية مالك المنظمة.';
  if (text.includes('risk owner must be')) return 'يجب أن يكون مسؤول الخطر عضوًا نشطًا في المنظمة.';
  if (text.includes('already resolved')) return 'تم حسم هذا الخطر بالفعل.';
  if (text.includes('idempotency key payload mismatch')) return 'أُعيد استخدام مفتاح الطلب لبيانات مختلفة. حدّث الصفحة ثم أعد المحاولة.';
  if (text.includes('forbidden')) return 'لا تملك صلاحية تنفيذ هذا الإجراء.';
  if (text.includes('authentication required')) return 'انتهت جلسة الدخول. سجّل الدخول ثم أعد المحاولة.';
  return 'تعذر حفظ واقعة الحوكمة. لم يتم تغيير السجل.';
}

async function invoke(
  prev: ActionState,
  form: FormData,
  schema: typeof projectRiskSchema | typeof riskResolutionSchema | typeof projectDecisionSchema,
  rpcName: string,
  args: (value: Record<string, unknown>) => Record<string, unknown>,
): Promise<ActionState> {
  const parsed = schema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة');
  const value = parsed.data as unknown as Record<string, unknown>;
  const { error } = await (await createClient()).rpc(rpcName, args(value));
  if (error) return commandFailureState(prev, message(error.message));
  const projectId = String(value.projectId);
  revalidatePath(`/projects/${projectId}/governance`);
  revalidatePath(`/projects/${projectId}`);
  revalidatePath('/portfolios');
  return commandSuccessState(prev);
}

export async function recordProjectRisk(prev: ActionState, form: FormData): Promise<ActionState> {
  return invoke(prev, form, projectRiskSchema, 'record_project_risk', (v) => ({
    p_organization_id: v.organizationId, p_project_id: v.projectId, p_title: v.title,
    p_description: v.description, p_severity: v.severity, p_owner_user_id: v.ownerUserId,
    p_due_date: v.dueDate, p_source_reference: v.sourceReference, p_idempotency_key: v.idempotencyKey,
  }));
}

export async function resolveProjectRisk(prev: ActionState, form: FormData): Promise<ActionState> {
  return invoke(prev, form, riskResolutionSchema, 'resolve_project_risk', (v) => ({
    p_organization_id: v.organizationId, p_risk_item_id: v.riskItemId,
    p_outcome: v.outcome, p_evidence_reference: v.evidenceReference,
    p_idempotency_key: v.idempotencyKey,
  }));
}

export async function recordProjectDecision(prev: ActionState, form: FormData): Promise<ActionState> {
  return invoke(prev, form, projectDecisionSchema, 'record_project_decision', (v) => ({
    p_organization_id: v.organizationId, p_project_id: v.projectId, p_title: v.title,
    p_decision_text: v.decisionText, p_rationale: v.rationale, p_decision_date: v.decisionDate,
    p_evidence_reference: v.evidenceReference, p_idempotency_key: v.idempotencyKey,
  }));
}
