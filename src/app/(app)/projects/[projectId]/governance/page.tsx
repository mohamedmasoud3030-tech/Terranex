import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getProjectDecisions, getProjectRisks } from '@/features/governance/queries';
import { getCurrentMembership } from '@/features/finance/queries';
import { getOrganizationMembers } from '@/features/portfolios/queries';
import { newCommandNonce } from '@/shared/idempotency';
import { WorkspaceChrome } from '@/features/workspace/chrome';
import { DecisionForm, ResolveRiskForm, RiskForm } from './forms';

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

  const [risks, decisions, membership, organizationMembers] = await Promise.all([
    getProjectRisks(projectId),
    getProjectDecisions(projectId),
    getCurrentMembership(project.organization_id),
    getOrganizationMembers(project.organization_id),
  ]);
  const isOwner = membership?.role === 'OWNER';
  const members = organizationMembers.map((member) => ({ user_id: member.user_id, label: `${member.role} · ${member.user_id}` }));
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

      <details className="card" open={openRisks.length === 0}>
        <summary>تسجيل خطر مشروع</summary>
        <RiskForm organizationId={project.organization_id} projectId={projectId} commandNonce={newCommandNonce()} members={members} />
      </details>

      {isOwner ? (
        <details className="card">
          <summary>تسجيل قرار مادي غير قابل للتعديل</summary>
          <DecisionForm organizationId={project.organization_id} projectId={projectId} commandNonce={newCommandNonce()} />
        </details>
      ) : <p className="muted">تسجيل القرارات المادية وحسم المخاطر مقصوران على مالك المنظمة وفق سلطة قاعدة البيانات.</p>}

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
            <table className="table-stackable">
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
                    <td data-label="الخطورة"><span className="status">{SEVERITY_AR[risk.severity] ?? risk.severity}</span></td>
                    <td data-label="الخطر"><strong>{risk.title}</strong></td>
                    <td data-label="الوصف">{risk.description}</td>
                    <td data-label="المسؤول"><code>{risk.owner_user_id}</code></td>
                    <td data-label="الاستحقاق">{risk.due_date ?? '—'}</td>
                    <td data-label="المصدر">{risk.source_reference ?? '—'}{isOwner ? <details><summary>حسم</summary><ResolveRiskForm organizationId={project.organization_id} projectId={projectId} riskItemId={risk.risk_item_id} commandNonce={newCommandNonce()} /></details> : null}</td>
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
            <table className="table-stackable">
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
                    <td data-label="التاريخ">{decision.decision_date}</td>
                    <td data-label="القرار"><strong>{decision.title}</strong></td>
                    <td data-label="النص">{decision.decision_text}</td>
                    <td data-label="المبرر">{decision.rationale ?? '—'}</td>
                    <td data-label="الدليل"><code>{decision.evidence_reference}</code></td>
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
            <table className="table-stackable">
              <thead>
                <tr><th>الخطر</th><th className="num">النتيجة</th><th>دليل الحسم</th><th>وقت الحسم</th></tr>
              </thead>
              <tbody>
                {resolvedRisks.map((risk) => (
                  <tr key={risk.risk_item_id}>
                    <td data-label="الخطر">{risk.title}</td>
                    <td className="num" data-label="النتيجة">{risk.resolution_outcome ?? '—'}</td>
                    <td data-label="دليل الحسم">{risk.resolution_evidence_reference ?? '—'}</td>
                    <td data-label="وقت الحسم">{risk.resolved_at ?? '—'}</td>
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
