import Link from 'next/link';
import { PageHeader, Section, Stat, StatGrid } from '@/shared/ui';
import { ThemeToggle } from '@/shared/ui/theme-toggle';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { signOut } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';

export const dynamic = 'force-dynamic';

/** الإعدادات: الحساب والمنظمة والمظهر. قراءة فقط ما عدا المظهر وتسجيل الخروج. */
export default async function SettingsPage() {
  const supabase = await createClient();
  const [{ data: auth }, { organization, organizations }] = await Promise.all([
    supabase.auth.getUser(),
    getActiveOrganization(),
  ]);
  const projects = organization ? await getProjects(organization.id) : [];
  return (
    <section className="stack-lg">
      <PageHeader eyebrow={organization?.name} title="الإعدادات" description="بيانات الحساب والمنظمة النشطة والمظهر." />
      <StatGrid label="ملخص الحساب">
        <Stat label="البريد الإلكتروني" value={auth.user?.email ?? '—'} />
        <Stat label="المنظمة النشطة" value={organization?.name ?? 'لا توجد'} hint={`${organizations.length} منظمة متاحة`} />
        <Stat label="المشاريع" value={projects.length} href="/projects" />
      </StatGrid>
      <Section title="المظهر" description="الفاتح أو الداكن. يُحفظ على هذا الجهاز.">
        <ThemeToggle />
      </Section>
      <Section title="المنظمات" description="بدّل المنظمة من القائمة الجانبية.">
        <ul className="stack-sm">
          {organizations.map((o) => (
            <li key={o.id}>{o.name}{o.id === organization?.id ? ' (النشطة)' : ''}</li>
          ))}
        </ul>
        <p className="muted">إدارة الأعضاء والصلاحيات ليست متاحة من الواجهة بعد.</p>
      </Section>
      <Section title="الجلسة">
        <form action={signOut}>
          <button type="submit" className="button secondary">تسجيل الخروج</button>
        </form>
        <p className="muted"><Link href="/forgot-password">تغيير كلمة المرور</Link></p>
      </Section>
    </section>
  );
}
