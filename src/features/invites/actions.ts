'use server';

import { cookies } from 'next/headers';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import type { ActionState } from '@/features/auth/actions';
import { commandFailureState } from '@/shared/idempotency';
import { createClient } from '@/shared/supabase/server';
import { ACTIVE_ORG_COOKIE, ACTIVE_ORG_COOKIE_MAX_AGE } from '@/features/organizations/active-org';
import { acceptInviteSchema, createInviteSchema, revokeInviteSchema } from './schema';

/** Successful creation carries the one-time raw token for the copyable link. */
export type InviteActionState = ActionState & { token?: string };

function fail(prev: ActionState, error: string): ActionState {
  return commandFailureState(prev, error);
}

function domainError(prev: ActionState, message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('authentication required')) return fail(prev, 'انتهت جلسة الدخول. سجّل الدخول ثم أعد المحاولة.');
  if (text.includes('organization owner required')) return fail(prev, 'هذا الإجراء يتطلب صلاحية مالك المنظمة.');
  if (text.includes('forbidden')) return fail(prev, 'لا تملك صلاحية تنفيذ هذا الإجراء على هذه المنظمة.');
  if (text.includes('idempotency key payload mismatch')) return fail(prev, 'مفتاح العملية استُخدم لبيانات مختلفة. حدّث الصفحة وأعد المحاولة.');
  if (text.includes('invite not found')) return fail(prev, 'رابط الدعوة غير صحيح أو لم تعد الدعوة موجودة.');
  if (text.includes('invite revoked')) return fail(prev, 'أُلغيت هذه الدعوة. اطلب رابطًا جديدًا من مالك المنظمة.');
  if (text.includes('invite expired')) return fail(prev, 'انتهت صلاحية هذه الدعوة. اطلب رابطًا جديدًا من مالك المنظمة.');
  if (text.includes('invite already used')) return fail(prev, 'استُخدمت هذه الدعوة بالفعل من حساب آخر.');
  if (text.includes('already closed')) return fail(prev, 'هذه الدعوة مغلقة بالفعل.');
  return fail(prev, fallback);
}

export async function createInvite(prev: InviteActionState, form: FormData): Promise<InviteActionState> {
  const parsed = createInviteSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(prev, parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة');
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_organization_invite', {
    p_organization_id: parsed.data.organizationId,
    p_note: parsed.data.note,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر إنشاء الدعوة. حاول مرة أخرى.');
  if (!data) {
    return fail(prev, 'أُنشئت هذه الدعوة سابقًا بنفس مفتاح العملية. حدّث الصفحة لعرضها أو أنشئ دعوة جديدة.');
  }
  revalidatePath('/settings');
  return { successCount: (prev.successCount ?? 0) + 1, token: data };
}

export async function revokeInvite(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = revokeInviteSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(prev, parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('revoke_organization_invite', {
    p_organization_id: parsed.data.organizationId,
    p_invite_id: parsed.data.inviteId,
  });
  if (error) return domainError(prev, error.message, 'تعذر إلغاء الدعوة. حاول مرة أخرى.');
  revalidatePath('/settings');
  return { successCount: (prev.successCount ?? 0) + 1 };
}

export async function acceptInvite(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = acceptInviteSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(prev, parsed.error.issues[0]?.message ?? 'رابط الدعوة غير صالح');
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('accept_organization_invite', {
    p_token: parsed.data.token,
  });
  if (error) return domainError(prev, error.message, 'تعذر قبول الدعوة. حاول مرة أخرى.');
  // Make the joined organization active so the member lands inside it.
  const jar = await cookies();
  jar.set(ACTIVE_ORG_COOKIE, String(data), {
    path: '/',
    maxAge: ACTIVE_ORG_COOKIE_MAX_AGE,
    sameSite: 'lax',
  });
  redirect('/');
}
