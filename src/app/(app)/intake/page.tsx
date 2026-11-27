import Link from 'next/link';
import { Section } from '@/shared/ui';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { SECTOR_LABEL } from '@/features/agriculture/labels';
import { JourneySteps } from '@/features/plain-language/journey-steps';
import { PlainIntro } from '@/features/plain-language/plain-intro';
import { NextStep } from '@/features/plain-language/next-step';
import { NEXT_STEP_COPY } from '@/features/plain-language/copy';

export const dynamic = 'force-dynamic';

export default async function IntakeStartPage() {
  const { organization } = await getActiveOrganization();
  if (!organization) {
    return (
      <section className="card stack shell-form-lg">
        <JourneySteps current={1} />
        <h1>إدخال أول مشروع حقيقي</h1>
        <p>ابدأ بالمنظمة. عملة المشاريع: جنيه مصري (EGP). القطاعات المدعومة: عقارات، زراعة، ثروة حيوانية.</p>
        <p className="muted">لا نعرض بيانات تجريبية. المسار يستخدم أوامر المنتج الحالية فقط.</p>
        <Link className="button" href="/onboarding">إنشاء المنظمة</Link>
      </section>
    );
  }

  const projects = await getProjects(organization.id);

  return (
    <section className="stack">
      <JourneySteps current={projects.length === 0 ? 2 : 3} />
      <div>
        <p className="muted">{organization.name}</p>
        <h1>إدخال المشروع الحقيقي</h1>
        <p className="muted">مسار موجّه: الإعداد → الأطراف والاتفاقية → رأس المال → البنك → حقائق القطاع → المركز الافتتاحي → التحقق.</p>
      </div>
      <PlainIntro page="intake" />
      {projects.length === 0 ? (
        <Section
          title="لا يوجد مشروع بعد"
        >
          <p>أنشئ مشروعًا بقطاعه المحدد (عقارات، زراعة، أو ثروة حيوانية) ضمن نطاق التشغيل التجريبي المتفق عليه.</p>
          <NextStep
            title={NEXT_STEP_COPY.createFirstProject.title}
            description={NEXT_STEP_COPY.createFirstProject.description}
            href="/projects/new"
            actionLabel={NEXT_STEP_COPY.createFirstProject.actionLabel}
          />
        </Section>
      ) : (
        <div className="grid">
          {projects.map((project) => (
            <Link key={project.id} href={`/projects/${project.id}/intake`} className="project">
              <strong>{project.name}</strong>
              <p className="muted">{project.internal_reference || 'بدون مرجع داخلي'}</p>
              <span className="status">{SECTOR_LABEL[project.sector] ?? project.sector} · متابعة الإدخال</span>
            </Link>
          ))}
          <Link href="/projects/new" className="project">
            <strong>مشروع إضافي</strong>
            <p className="muted">فقط إذا كان داخل نطاق التشغيل التجريبي الموقّع.</p>
            <span className="status">مشروع جديد</span>
          </Link>
        </div>
      )}
    </section>
  );
}
