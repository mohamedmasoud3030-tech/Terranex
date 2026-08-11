import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getActiveVersion, getProjectCapitalPosition } from '@/features/funding/queries';
import { getProjectRealizedResult } from '@/features/real-estate/queries';
import { formatMinorUnits } from '@/features/funding/money';

export const dynamic = 'force-dynamic';

const STATE_LABEL: Record<string, string> = {
  DRAFT: 'مسودة',
  FUNDING: 'مرحلة التمويل',
  OPERATING: 'مرحلة التشغيل',
  EXITING: 'مرحلة الخروج',
  CLOSED: 'مغلق',
};

export default async function ProjectShell({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const [activeVersion, position, result] = await Promise.all([
    getActiveVersion(projectId),
    getProjectCapitalPosition(projectId),
    getProjectRealizedResult(projectId),
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
          <Link className="card" href={`/projects/${projectId}/property`}>
            <strong>الأصول العقارية</strong>
            <p className="muted">إدارة العقارات والتكاليف والتقييمات</p>
          </Link>
          <Link className="card" href={`/projects/${projectId}/disposition`}>
            <strong>التصرف والمبيعات</strong>
            <p className="muted">بيع العقارات والتحصيل</p>
          </Link>
          <Link className="card" href={`/projects/${projectId}/result`}>
            <strong>النتيجة المحققة</strong>
            <p className="muted">
              {result && BigInt(result.realized_result_minor_units) !== 0n
                ? `نتيجة ${formatMinorUnits(result.realized_result_minor_units, result.currency)}`
                : 'لا توجد مبيعات معترف بها'}
            </p>
          </Link>
        </nav>
      </section>
    </section>
  );
}
