'use server';

import { redirect } from 'next/navigation';
import { z } from 'zod';
import { createClient } from '@/shared/supabase/server';
import { recoveryRedirectUrl } from './recovery-url';

export type ActionState = {
  error?: string;
  /**
   * Monotonic count of confirmed successful submissions completed by this
   * action. Absent for actions that never report success (for example sign-in
   * redirects on success). Clients use it to distinguish the initial state and
   * a failure from a confirmed success without relying on the absence of an
   * error, and to rotate per-command idempotency keys only after a confirmed
   * success. Failures must carry the previous value forward unchanged.
   */
  successCount?: number;
};

export type PasswordResetState = {
  error?: string;
  sent?: boolean;
};

const credentials = z.object({
  email: z.string().email('أدخل بريدًا إلكترونيًا صحيحًا'),
  password: z.string().min(8, 'كلمة المرور يجب أن تكون 8 أحرف على الأقل'),
});

const resetRequest = z.object({
  email: z.string().email('أدخل بريدًا إلكترونيًا صحيحًا'),
});

const passwordUpdate = z.object({
  password: z.string().min(8, 'كلمة المرور يجب أن تكون 8 أحرف على الأقل'),
  confirmPassword: z.string().min(8, 'تأكيد كلمة المرور مطلوب'),
});

export async function signIn(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = credentials.safeParse(Object.fromEntries(form));
  if (!parsed.success) return { error: parsed.error.issues[0]?.message };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  if (error) return { error: 'تعذر تسجيل الدخول. تحقق من بيانات الدخول.' };
  redirect('/');
}

export async function requestPasswordReset(
  _: PasswordResetState,
  form: FormData,
): Promise<PasswordResetState> {
  const parsed = resetRequest.safeParse(Object.fromEntries(form));
  if (!parsed.success) return { error: parsed.error.issues[0]?.message };

  const redirectTo = recoveryRedirectUrl();
  if (!redirectTo) {
    return { error: 'إعداد رابط الاسترجاع غير مكتمل لهذه البيئة. تواصل مع المسؤول.' };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, {
    redirectTo,
  });

  if (error) {
    return { error: 'تعذر إرسال رابط إعادة التعيين الآن. حاول مجددًا بعد قليل.' };
  }

  return { sent: true };
}

export async function updatePassword(
  _: PasswordResetState,
  form: FormData,
): Promise<PasswordResetState> {
  const parsed = passwordUpdate.safeParse(Object.fromEntries(form));
  if (!parsed.success) return { error: parsed.error.issues[0]?.message };
  if (parsed.data.password !== parsed.data.confirmPassword) {
    return { error: 'كلمتا المرور غير متطابقتين.' };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return { error: 'انتهت صلاحية جلسة إعادة التعيين. اطلب رابطًا جديدًا.' };
  }

  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) {
    return { error: 'تعذر تحديث كلمة المرور الآن. حاول مجددًا.' };
  }

  redirect('/');
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect('/login');
}
