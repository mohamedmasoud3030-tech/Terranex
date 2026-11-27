import { recordStatusLabel } from '@/features/projects/labels';
import Link from 'next/link';
import { PermissionState, Section } from '@/shared/ui';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership } from '@/features/finance/queries';
import { getActiveVersion, getParticipants } from '@/features/funding/queries';

export const dynamic = 'force-dynamic';

export default async function InvestorsPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();

  const [membership, participants, activeVersion] = await Promise.all([
    getCurrentMembership(project.organization_id),
    getParticipants(projectId),
    getActiveVersion(projectId),
  ]);

  if (!membership) {
    return (
      <PermissionState
        message="عضويتك الحالية لا تسمح بقراءة بيانات المشاركين لهذا المشروع."
        backHref={`/projects/${projectId}`}
        backLabel="العودة للمشروع"
      />
    );
  }

  return (
    <section className="stack">
      <header className="project-context card">
        <div>
          <Link className="back-link" href={`/projects/${projectId}`}>→ مساحة المشروع</Link>
          <h1>شفافية المشاركين</h1>
          <p className="muted">{project.name} · معلومات تعريفية واتفاقية فقط قبل اعتماد سياسة الاستثمار R14.</p>
        </div>
      </header>

      <div className="banner info" role="note">
        <strong>Policy Blocked — BD-003 / BD-004 / BD-006 / BD-008</strong>
        <span>
          لا يعرض Terranex حاليًا نسبة ملكية، حصة ربح أو خسارة، مبلغًا قابلًا للتوزيع، تخصيصًا، أو استحقاقًا للمستثمر كحقيقة نهائية. هذه المعاني تنتظر حزمة سياسة الشركة R14 والمستندات الحاكمة.
        </span>
      </div>

            <Section
        title="المشاركون المسجلون"
        description="الهوية المسجلة لا تعني تلقائيًا ملكية أو استحقاق أو حصة في الربح."
      >
        {participants.length === 0 ? (
          <p className="muted">لا يوجد مشاركون مسجلون لهذا المشروع.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: الاسم القانوني · الصفة المسجلة · حالة الدلالة الاقتصادية</caption>
              <thead>
                <tr><th scope="col">الاسم القانوني</th><th scope="col">الصفة المسجلة</th><th scope="col">حالة الدلالة الاقتصادية</th></tr>
              </thead>
              <tbody>
                {participants.map((participant) => (
                  <tr key={participant.id}>
                    <td data-label="الاسم القانوني">{participant.parties.legal_name}</td>
                    <td data-label="الصفة المسجلة">{participant.role === 'INVESTOR' ? 'مشارك مسجل (INVESTOR)' : participant.role}</td>
                    <td data-label="حالة الدلالة الاقتصادية">غير مستنتجة من الهوية — تنتظر السياسة الحاكمة</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>

            <Section
        title="النسخة الاتفاقية الفعالة"
      >
        {activeVersion ? (
          <dl className="facts">
            <div><dt>الإصدار</dt><dd>v{activeVersion.version_no}</dd></div>
            <div><dt>تاريخ النفاذ</dt><dd>{activeVersion.effective_date}</dd></div>
            <div><dt>الحالة</dt><dd>{recordStatusLabel(activeVersion.status)}</dd></div>
            <div><dt>بصمة الشروط</dt><dd><code>{activeVersion.terms_hash}</code></dd></div>
          </dl>
        ) : (
          <p className="muted">لا توجد نسخة اتفاقية سارية مسجلة لهذا المشروع.</p>
        )}
        <p className="muted">
          وجود اتفاقية فعالة لا يسمح للنظام بافتراض طريقة توزيع الأرباح أو تعريف الملكية. يجب أن تُحل قرارات الأعمال المفتوحة وتُربط بالمستندات الصحيحة قبل تفعيل هذه الأرقام.
        </p>
      </Section>

            <Section
        title="ما يمكن نشره بأمان قبل R14"
      >
        <ul>
          <li>هوية المشارك والطرف القانوني المسجل.</li>
          <li>مرجع النسخة الاتفاقية الفعالة وبصمتها وتاريخ نفاذها.</li>
          <li>مستندات وتحديثات وأدلة منشورة عندما يكتمل مسار النشر المصرح.</li>
          <li>تواريخ as-of وحالة حداثة البيانات في أي read model لاحق.</li>
        </ul>
        <p className="muted">أي حقل استحقاق أو تخصيص أو توزيع يظل غير فعال حتى R14.</p>
      </Section>
    </section>
  );
}
