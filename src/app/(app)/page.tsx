import Link from 'next/link';
import { getOrganizations } from '@/features/organizations/queries';
import { getProjects } from '@/features/projects/queries';
import { sectorLandingHref } from '@/features/workspace/nav';
import { SECTOR_LABEL } from '@/features/agriculture/labels';

export default async function Home() {
  const orgs = await getOrganizations();
  if (!orgs.length) {
    return (
      <section className="card stack">
        <h1>لنبدأ بإنشاء منظمتك</h1>
        <p className="muted">المنظمة هي الحدود الآمنة لبيانات الاستثمار الخاصة بفريقك.</p>
        <Link className="button" href="/onboarding">إنشاء منظمة</Link>
      </section>
    );
  }
  const org = orgs[0];
  const projects = await getProjects(org.id);
  return (
    <section className="stack">
      <div className="top">
        <div>
          <p className="muted">{org.name}</p>
          <h1>المشاريع الاستثمارية</h1>
        </div>
        <div className="stack" style={{ justifyItems: 'end' }}>
          <Link className="button" href="/intake">إدخال مشروع حقيقي</Link>
          <Link className="button secondary" href="/projects/new">مشروع جديد</Link>
        </div>
      </div>
      {projects.length === 0 ? (
        <section className="card stack">
          <h2>لا توجد مشاريع بعد</h2>
          <p className="muted">أدخل أول مشروع عبر المسار الموجّه. لن نعرض أرقامًا أو بيانات تجريبية.</p>
          <Link className="button" href="/intake">بدء إدخال المشروع</Link>
        </section>
      ) : (
        <div className="grid">
          {projects.map((p) => (
            <Link key={p.id} href={sectorLandingHref(p.sector, p.id)} className="project">
              <strong>{p.name}</strong>
              <p className="muted">{p.internal_reference || 'بدون مرجع داخلي'}</p>
              <span className="status">
                {SECTOR_LABEL[p.sector] ?? p.sector} · {p.reporting_currency}
              </span>
            </Link>
          ))}
        </div>
      )}
    </section>
  );
}
