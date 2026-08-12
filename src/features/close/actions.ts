'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/shared/supabase/server';
import type { ActionState } from '@/features/auth/actions';
import {
  approveCloseSchema,
  approveCorrectionSchema,
  approveExceptionSchema,
  executeCorrectionSchema,
  prepareCloseSchema,
  reopenSchema,
  requestCorrectionSchema,
  requestExceptionSchema,
} from './schema';

function fail(message: string): ActionState {
  return { error: message };
}

function refreshProject(projectId: string) {
  revalidatePath('/');
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/close`);
}

function domainError(message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('idempotency key payload mismatch')) {
    return fail('تعذرت إعادة المحاولة لأن مفتاح العملية استُخدم سابقًا لبيانات مختلفة.');
  }
  if (text.includes('prepare requires an OPEN period')) {
    return fail('لا يمكن بدء التحضير لفترة مغلقة.');
  }
  if (text.includes('an open close run already exists')) {
    return fail('يوجد بالفعل إغلاق مُجهَّز لهذه الفترة. اعتمده أو افتح فترة جديدة.');
  }
  if (text.includes('cannot approve a run with failing gates')) {
    return fail('لا يمكن اعتماد إغلاق يحوي بوابات فاشلة. اعتمد استثناء لكل بوابة أولاً.');
  }
  if (text.includes('only a PREPARED run')) {
    return fail('لا يمكن اعتماد إغلاق غير مُجهَّز.');
  }
  if (text.includes('only a CLOSED period')) {
    return fail('لا يمكن إعادة فتح فترة غير مغلقة.');
  }
  if (text.includes('S4 sale and collection correction requires an APPROVED correction_request')) {
    return fail('تصحيح S4 يتطلب طلب تصحيح معتمدًا.');
  }
  if (text.includes('correction already executed')) {
    return fail('تم تنفيذ هذا التصحيح سابقًا.');
  }
  if (text.includes('only APPROVED correction requests can be executed')) {
    return fail('لا يمكن تنفيذ طلب تصحيح غير معتمد.');
  }
  if (text.includes('closed authoritative period is immutable')) {
    return fail('الفترة المغلقة ثابتة. أعد الفتح لإنشاء فترة جديدة.');
  }
  if (text.includes('no open accounting period covers')) {
    return fail('لا توجد فترة محاسبية مفتوحة لتاريخ الترحيل هذا.');
  }
  return fail(fallback);
}

async function callRpc(functionName: string, args: Record<string, unknown>) {
  const s = await createClient();
  // Supabase rpc returns data with snake_case keys; cast through unknown.
  return s.rpc(functionName, args) as unknown as Promise<{ data: unknown; error: { message: string } | null }>;
}

export async function prepareCloseRunAction(_: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = prepareCloseSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  }
  const input = parsed.data;
  const { error } = await callRpc('s6_prepare_close_run', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_period_id: input.periodId,
    p_notes: input.notes || null,
  });
  if (error) return domainError(error.message, 'تعذّر بدء التحضير');
  refreshProject(input.projectId);
  return {};
}

export async function approveCloseRunAction(_: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = approveCloseSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  const input = parsed.data;
  // Financial RPC: scope is derived from the close run by PostgreSQL.
  const { error } = await callRpc('s6_approve_close_run', {
    p_organization_id: input.organizationId,
    p_close_run_id: input.closeRunId,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذّر اعتماد الإغلاق');
  refreshProject(input.projectId);
  return {};
}

export async function requestCloseExceptionAction(_: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = requestExceptionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  const input = parsed.data;
  const { error } = await callRpc('s6_request_close_run_exception', {
    p_organization_id: input.organizationId,
    p_close_run_id: input.closeRunId,
    p_gate_code: input.gateCode,
    p_reason: input.reason,
    p_evidence_reference: input.evidenceReference,
    p_materiality_comment: input.materialityComment || null,
  });
  if (error) return domainError(error.message, 'تعذّر تسجيل الاستثناء');
  refreshProject(input.projectId);
  return {};
}

export async function approveCloseExceptionAction(_: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = approveExceptionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  const input = parsed.data;
  const { error } = await callRpc('s6_approve_close_run_exception', {
    p_organization_id: input.organizationId,
    p_exception_id: input.exceptionId,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذّر اعتماد الاستثناء');
  refreshProject(input.projectId);
  return {};
}

export async function reopenPeriodAction(_: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = reopenSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  const input = parsed.data;
  const { error } = await callRpc('s6_reopen_period', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_period_id: input.periodId,
    p_reason: input.reason,
    p_evidence_reference: input.evidenceReference,
  });
  if (error) return domainError(error.message, 'تعذّر إعادة فتح الفترة');
  refreshProject(input.projectId);
  return {};
}

export async function requestCorrectionAction(_: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = requestCorrectionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  const input = parsed.data;
  const { error } = await callRpc('s6_request_correction', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_target_batch_id: input.targetBatchId,
    p_source_period_id: input.sourcePeriodId,
    p_correction_period_id: input.correctionPeriodId,
    p_reason: input.reason,
    p_evidence_reference: input.evidenceReference,
  });
  if (error) return domainError(error.message, 'تعذّر تسجيل طلب التصحيح');
  refreshProject(input.projectId);
  return {};
}

export async function approveCorrectionAction(_: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = approveCorrectionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  const input = parsed.data;
  const { error } = await callRpc('s6_approve_correction', {
    p_organization_id: input.organizationId,
    p_correction_request_id: input.correctionRequestId,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذّر اعتماد طلب التصحيح');
  refreshProject(input.projectId);
  return {};
}

export async function executeCorrectionAction(_: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = executeCorrectionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  const input = parsed.data;
  const { error } = await callRpc('s6_execute_correction', {
    p_organization_id: input.organizationId,
    p_correction_request_id: input.correctionRequestId,
    p_correction_date: input.correctionDate,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذّر تنفيذ التصحيح');
  refreshProject(input.projectId);
  return {};
}
