'use server';
import { redirect } from 'next/navigation';
import { z } from 'zod';
import { createClient } from '@/shared/supabase/server';
export type ActionState = { error?: string };
const credentials = z.object({ email: z.string().email('أدخل بريدًا إلكترونيًا صحيحًا'), password: z.string().min(8, 'كلمة المرور يجب أن تكون 8 أحرف على الأقل') });
export async function signIn(_: ActionState, form: FormData): Promise<ActionState> { const parsed = credentials.safeParse(Object.fromEntries(form)); if (!parsed.success) return { error: parsed.error.issues[0]?.message }; const supabase = await createClient(); const { error } = await supabase.auth.signInWithPassword(parsed.data); if (error) return { error: 'تعذر تسجيل الدخول. تحقق من بيانات الدخول.' }; redirect('/'); }
export async function signOut() { const supabase = await createClient(); await supabase.auth.signOut(); redirect('/login'); }
