import { redirect } from 'next/navigation';
import { createClient } from '@/shared/supabase/server';
import { LoginForm } from './login-form';

export const dynamic = 'force-dynamic';

export default async function LoginPage({
  searchParams,
}: {
  searchParams?: Promise<{ reason?: string }>;
}) {
  const params = (await searchParams) ?? {};
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  // A signed-in user landing on /login (bookmark, stale tab, password
  // manager) belongs on the dashboard, not the sign-in form.
  if (user) redirect('/');
  return <LoginForm sessionExpired={params.reason === 'expired'} />;
}
