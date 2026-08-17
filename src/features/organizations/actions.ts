'use server';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { createClient } from '@/shared/supabase/server';
import { organizationSchema } from './schema';
import type { ActionState } from '@/features/auth/actions';
import { ACTIVE_ORG_COOKIE, ACTIVE_ORG_COOKIE_MAX_AGE } from './active-org';

export async function createOrganization(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = organizationSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return { error: parsed.error.issues[0]?.message };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_organization', { p_name: parsed.data.name });
  if (error) return { error: 'تعذر إنشاء المنظمة. حاول مرة أخرى.' };
  // The creator becomes OWNER of the new organization; make it the active
  // organization for this browser so the next page operates on it.
  const jar = await cookies();
  jar.set(ACTIVE_ORG_COOKIE, String(data), {
    path: '/',
    maxAge: ACTIVE_ORG_COOKIE_MAX_AGE,
    sameSite: 'lax',
  });
  redirect('/intake');
}
