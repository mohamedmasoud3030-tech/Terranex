import { redirect } from 'next/navigation';
import { createClient } from '@/shared/supabase/server';
import { ResetPasswordForm } from './reset-password-form';

export const dynamic = 'force-dynamic';

export default async function ResetPasswordPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect('/forgot-password?recovery_error=1');

  return <ResetPasswordForm />;
}
