'use server';
import { redirect } from 'next/navigation';
import { createClient } from '@/shared/supabase/server';
import { commandFailureState } from '@/shared/idempotency';
import { projectSchema } from './schema';
import type { ActionState } from '@/features/auth/actions';

export async function createProject(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = projectSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) {
    return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة');
  }
  const p = parsed.data;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_investment_project', {
    p_organization_id: p.organizationId,
    p_name: p.name,
    p_internal_reference: p.internalReference || null,
    p_description: p.description || null,
    p_sector: p.sector,
    p_idempotency_key: p.idempotencyKey,
  });
  if (error || !data) {
    if (error?.message?.includes('invalid sector')) {
      return commandFailureState(
        prev,
        'القطاع المحدد غير مدعوم. اختر عقارات أو زراعة أو ثروة حيوانية.',
      );
    }
    if (error?.message?.includes('idempotency key payload mismatch')) {
      return commandFailureState(
        prev,
        'بيانات محاولة إنشاء المشروع تغيّرت بعد إرسالها. أعد فتح نموذج مشروع جديد لبدء عملية جديدة.',
      );
    }
    return commandFailureState(prev, 'تعذر إنشاء المشروع. تأكد من صلاحياتك وحاول مجددًا.');
  }
  // Agriculture goes to its own sector workspace; Real Estate keeps the
  // existing intake path.
  if (p.sector === 'AGRICULTURE') {
    redirect(`/projects/${data}/agriculture`);
  } else if (p.sector === 'LIVESTOCK') {
    redirect(`/projects/${data}/livestock`);
  } else {
    redirect(`/projects/${data}/intake`);
  }
}
