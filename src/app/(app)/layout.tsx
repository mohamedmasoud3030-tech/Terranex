import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/shared/supabase/server';
import { signOut } from '@/features/auth/actions';
import { getActiveOrganization } from '@/features/organizations/context';
import { OrganizationSwitcher } from '@/features/organizations/switcher';
import { AppNav } from '@/shared/ui/app-nav';
import { BrandMark } from '@/shared/ui/sector';
import { SideNav } from '@/shared/ui/side-nav';
import { ThemeToggle } from '@/shared/ui/theme-toggle';

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
        <button type="submit" className="button secondary sm">تسجيل الخروج</button>
      </form>
    </>
  );
  return (
    <div className="app-frame">
      <a className="skip-link" href="#content">تخطي إلى المحتوى</a>
      <aside className="app-sidebar">
        <Link href="/" className="brand" aria-label="تيرانكس — الصفحة الرئيسية">
          <BrandMark />
          <span className="brand-text">
            <small>بيئة تطوير</small>
            تيرانكس
          </span>
        </Link>
        <SideNav />
        <div id="sidebar-project-slot" />
        <div className="sidebar-foot">
          <ThemeToggle />
          {tools}
        </div>
      </aside>
      <div className="shell app-content">
        <header className="app-topbar app-topbar-mobile">
          <Link href="/" className="brand" aria-label="تيرانكس — الصفحة الرئيسية">
            <BrandMark />
            تيرانكس
          </Link>
          <AppNav tools={<>{tools}<ThemeToggle /></>} />
        </header>
        <main id="content">{children}</main>
      </div>
    </div>
  );
}
