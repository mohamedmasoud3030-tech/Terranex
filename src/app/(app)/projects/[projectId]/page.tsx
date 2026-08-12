import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getActiveVersion, getProjectCapitalPosition } from '@/features/funding/queries';
import { formatMinorUnits } from '@/shared/money';

export const dynamic = 'force-dynamic';

const STATE_LABEL: Record<string, string> = {
  DRAFT: 'مسودة',
  FUNDING: 'مرحلة التمويل',
};

export default async function ProjectShell({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const [activeVersion, position] = await Promise.all([
    getActiveVersion(projectId),
    getProjectCapitalPosition(projectId),
  ]);

  return (
    <section className="stack">
      <div>
        <Link className="muted" href="/">
          ← المشاريع
        </Link>
        <span className="status">{STATE_LABEL[project.lifecycle_state] ?? project.lifecycle_state}</span>
        <h1>{project.name}</h1>
        <p className="muted">
          مشروع عقاري · {project.reporting_currency}
          {project.internal_reference ? ` · ${project.internal_reference}` : ''}
        </p>
      </div>

      <section className="card stack">
        <h2>مساحة عمل المشروع</h2>
        <p>{project.description || 'لم يُضف وصف للمشروع بعد.'}</p>
        <nav className="grid">
          <Link className="card" href={`/projects/${projectId}/terms`}>
            <strong>الشروط والاتفاقية</strong>
            <p className="muted">
              {activeVersion
                ? `النسخة ${activeVersion.version_no} مفعّلة`
                : 'لا توجد اتفاقية مفعّلة'}
            </p>
          </Link>
          <Link className="card" href={`/projects/${projectId}/funding`}>
            <strong>التمويل ورأس المال</strong>
            <p className="muted">
              {activeVersion
                ? `مستلم ${formatMinorUnits(position?.contributed_minor_units ?? 0, project.reporting_currency)}`
                : 'فعّل الاتفاقية أولًا'}
            </p>
          </Link>
          <Link className="card" href={`/projects/${projectId}/operations`}>
            <strong>العمليات العقارية</strong>
            <p className="muted">الأصول والسيطرة والتطوير والتكلفة والتصرف والبيع والتحصيل والنتيجة المحققة</p>
          </Link>
          <Link className="card" href={`/projects/${projectId}/costs`}>
            <strong>التكاليف والالتزامات</strong>
            <p className="muted">سجّل الالتزامات واعتمدها وادفعها</p>
          </Link>
          <Link className="card" href={`/projects/${projectId}/cash`}>
            <strong>النقدية والبنك</strong>
            <p className="muted">الحسابات، كشوف البنك، والمطابقة</p>
          </Link>
          <Link className="card" href={`/projects/${projectId}/close`}>
            <strong>الإغلاق المالي والتصحيح</strong>
            <p className="muted">فترات محاسبية، بوابات الإغلاق، لقطات مجمدة، تصحيح مرتبط</p>
          </Link>
          <Link className="card" href={`/projects/${projectId}/investors`}>
            <strong>المستثمرون والتخصيص والتوزيعات</strong>
            <p className="muted">قواعد حاكمة، تخصيص نتيجة مغلقة، مستحقات توزيع، دفع، وكشف رأس المال</p>
          </Link>
          <Link className="card" href={`/projects/${projectId}/pilot`}>
            <strong>تجهيز التشغيل التجريبي</strong>
            <p className="muted">الاستيراد الافتتاحي، مجاميع الرقابة، فروق المطابقة، اختبار القبول، والوصول</p>
          </Link>
        </nav>
      </section>
    </section>
  );
}
