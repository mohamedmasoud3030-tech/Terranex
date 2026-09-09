import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/shared/supabase/server';
import { signOut } from '@/features/auth/actions';
import { getActiveOrganization } from '@/features/organizations/context';
import { OrganizationSwitcher } from '@/features/organizations/switcher';
import { AppNav } from '@/shared/ui/app-nav';

/**
 * AppShell: authentication gate + one-row top bar + `main#content` landmark.
 * Page actions never live here; only global navigation and session tools.
 */
export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const s = await createClient();
  const { data: { user } } = await s.auth.getUser();
  if (!user) redirect('/login');
  const { organization, organizations } = await getActiveOrganization();
  const tools = (
    <>
      <OrganizationSwitcher organizations={organizations} activeId={organization?.id ?? null} />
      <form action={signOut}>
        <button className="button secondary sm">تسجيل الخروج</button>
      </form>
    </>
  );
  return (
    <div className="shell">
      <a className="skip-link" href="#content">تخطي إلى المحتوى</a>
      <header className="app-topbar">
        <Link href="/" className="brand">تيرانكس</Link>
        <AppNav tools={tools} />
      </header>
      <main id="content">{children}</main>
    </div>
  );
}
