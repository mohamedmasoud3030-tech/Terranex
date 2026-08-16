import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getProjectDecisions, getProjectRisks } from '@/features/governance/queries';
import { WorkspaceChrome } from '@/features/workspace/chrome';

export const dynamic = 'force-dynamic';

const SEVERITY_AR: Record<string, string> = {
  LOW: 'منخفض',
  MEDIUM: 'متوسط',
  HIGH: 'مرتفع',
  CRITICAL: 'حرج',
};

export default async function GovernancePage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();

  const [risks, decisions] = await Promise.all([
    getProjectRisks(projectId),
    getProjectDecisions(projectId),
  ]);
  const openRisks = risks.filter((risk) => risk.status === 'OPEN');
  const resolvedRisks = risks.filter((risk) => risk.status === 'RESOLVED');
  const criticalOpen = openRisks.filter((risk) => risk.severity === 'CRITICAL').length;

  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="governance"
        title="المخاطر والقرارات"
        subtitle={`${project.name} · سجل حوكمة المشروع`}
        internalReference={project.internal_reference}
        sector={project.sector}
      />

      <div className="overview-kpis" aria-label="ملخص حوكمة المشروع">
        <div className={`overview-kpi${criticalOpen ? ' negative' : ''}`}>
          <span>مخاطر مفتوحة</span>
          <strong>{openRisks.length}</strong>
          <small>{criticalOpen ? `${criticalOpen} حرجة` : 'لا توجد مخاطر حرجة مفتوحة'}</small>
        </div>
        <div className="overview-kpi">
          <span>مخاطر تم حسمها</span>
          <strong>{resolvedRisks.length}</strong>
          <small>الحسم محفوظ كواقعة مستقلة</small>
        </div>
        <div className="overview-kpi">
          <span>قرارات موثقة</span>
          <strong>{decisions.length}</strong>
          <small>سجل غير قابل لإعادة كتابة التاريخ</small>
        </div>
      </div>

      <div className="banner info">
        هذه الصفحة تعرض حقائق حوكمة المشروع فقط. تسجيل خطر أو قرار لا ينشئ قيدًا ماليًا ولا يغيّر ملكية أصل أو استحقاق مستثمر.
      </div>

      <section className="card stack" aria-labelledby="open-risks-heading">
        <div className="section-heading">
          <div>
            <h2 id="open-risks-heading">المخاطر المفتوحة</h2>
            <p className="muted">المسؤول وتاريخ الاستحقاق ومصدر المعلومة محفوظة على Project boundary.</p>
          </div>
        </div>
        {openRisks.length === 0 ? (
          <p className="muted">لا توجد مخاطر مفتوحة مسجلة لهذا المشروع.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>الخطورة</th>
                  <th>الخطر</th>
                  <th>الوصف</th>
                  <th>المسؤول</th>
                  <th>الاستحقاق</th>
                  <th>المصدر</th>
                </tr>
              </thead>
              <tbody>
                {openRisks.map((risk) => (
                  <tr key={risk.risk_item_id}>
                    <td><span className="status">{SEVERITY_AR[risk.severity] ?? risk.severity}</span></td>
                    <td><strong>{risk.title}</strong></td>
                    <td>{risk.description}</td>
                    <td><code>{risk.owner_user_id}</code></td>
                    <td>{risk.due_date ?? '—'}</td>
                    <td>{risk.source_reference ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="card stack" aria-labelledby="decisions-heading">
        <div className="section-heading">
          <div>
            <h2 id="decisions-heading">سجل القرارات</h2>
            <p className="muted">قرارات مادية مسجلة بالدليل، لا تُستبدل بتعديل صامت.</p>
          </div>
        </div>
        {decisions.length === 0 ? (
          <p className="muted">لا توجد قرارات موثقة لهذا المشروع بعد.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>التاريخ</th>
                  <th>القرار</th>
                  <th>النص</th>
                  <th>المبرر</th>
                  <th>الدليل</th>
                </tr>
              </thead>
              <tbody>
                {decisions.map((decision) => (
                  <tr key={decision.id}>
                    <td>{decision.decision_date}</td>
                    <td><strong>{decision.title}</strong></td>
                    <td>{decision.decision_text}</td>
                    <td>{decision.rationale ?? '—'}</td>
                    <td><code>{decision.evidence_reference}</code></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {resolvedRisks.length ? (
        <section className="card stack" aria-labelledby="resolved-risks-heading">
          <h2 id="resolved-risks-heading">مخاطر تم حسمها</h2>
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>الخطر</th><th>النتيجة</th><th>دليل الحسم</th><th>وقت الحسم</th></tr>
              </thead>
              <tbody>
                {resolvedRisks.map((risk) => (
                  <tr key={risk.risk_item_id}>
                    <td>{risk.title}</td>
                    <td>{risk.resolution_outcome ?? '—'}</td>
                    <td>{risk.resolution_evidence_reference ?? '—'}</td>
                    <td>{risk.resolved_at ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}
    </section>
  );
}
