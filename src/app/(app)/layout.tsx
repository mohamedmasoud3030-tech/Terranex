import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/shared/supabase/server';
import { signOut } from '@/features/auth/actions';
import { getActiveOrganization } from '@/features/organizations/context';
import { OrganizationSwitcher } from '@/features/organizations/switcher';

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const s = await createClient();
  const { data: { user } } = await s.auth.getUser();
  if (!user) redirect('/login');
  const { organization, organizations } = await getActiveOrganization();
  return (
    <main className="shell">
      <header className="top">
        <Link href="/" className="brand">تيرانكس</Link>
        <nav aria-label="التنقل الرئيسي">
          <Link className="button secondary" href="/portfolios">المحافظ</Link>
          <Link className="button secondary" href="/">المشاريع</Link>
          <Link className="button secondary" href="/assets">الأصول</Link>
          <Link className="button secondary" href="/intake">إدخال المشروع</Link>
        </nav>
        <OrganizationSwitcher organizations={organizations} activeId={organization?.id ?? null} />
        <form action={signOut}><button className="button secondary">تسجيل الخروج</button></form>
      </header>
      {children}
    </main>
  );
}
