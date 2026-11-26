'use server';

import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import { parseMajorUnitsToMinor } from '@/shared/money';
import { createClient } from '@/shared/supabase/server';
import { adjustmentSchema } from './schema';

function domainMessage(text: string): string {
  if (text.includes('organization owner required')) return 'قيد التسوية اليدوي يتطلب صلاحية مالك المنظمة.';
  if (text.includes('idempotency key payload mismatch')) return 'مفتاح العملية استُخدم لبيانات مختلفة. حدّث الصفحة وأعد المحاولة.';
  if (text.includes('entry must balance')) return 'القيد غير متوازن.';
  if (text.includes('currency must match')) return 'عملة القيد يجب أن تطابق عملة المشروع.';
  if (text.includes('closed') || text.includes('period')) return 'الفترة المحاسبية لهذا التاريخ مقفلة؛ اختر تاريخًا في فترة مفتوحة.';
  if (text.includes('forbidden')) return 'لا تملك صلاحية تنفيذ هذا الإجراء.';
  return 'تعذر ترحيل قيد التسوية.';
}

/** Posts one balanced reclassification: debit `toRole`, credit `fromRole`, same amount. */
export async function postAdjustment(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = adjustmentSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة');
  const v = parsed.data;
  const minor = parseMajorUnitsToMinor(v.amount, v.currency);
  const supabase = await createClient();
  const { error } = await supabase.rpc('post_manual_adjustment', {
    p_organization_id: v.organizationId,
    p_project_id: v.projectId,
    p_entry_date: v.entryDate,
    p_currency: v.currency,
    p_memo: v.memo,
    p_evidence_reference: v.evidenceReference,
    p_lines: [
      { account_role: v.toRole, side: 'DEBIT', amount_minor_units: Number(minor) },
      { account_role: v.fromRole, side: 'CREDIT', amount_minor_units: Number(minor) },
    ],
    p_idempotency_key: v.idempotencyKey,
  });
  if (error) return commandFailureState(prev, domainMessage(error.message ?? ''));
  revalidatePath('/');
  revalidatePath('/journal');
  revalidatePath(`/projects/${v.projectId}`);
  revalidatePath(`/projects/${v.projectId}/adjustments`);
  revalidatePath(`/projects/${v.projectId}/costs`);
  return commandSuccessState(prev);
}
