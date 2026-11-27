import Link from 'next/link';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { getIntegritySignals, getProjectPosition } from '@/features/control/queries';
import { getUnreconciledPositiveStatementLines } from '@/features/revenue/queries';
import { projectIssues, signalIssues, sortIssues, verdictAr, type HealthIssue } from '@/features/health/checks';
import { EmptyState, PageHeader, Section, StatusBadge } from '@/shared/ui';

export const dynamic = 'force-dynamic';

const SEVERITY_TONE: Record<HealthIssue['severity'], 'danger' | 'warning' | 'info'> = {
  CRITICAL: 'danger',
  WARNING: 'warning',
  INFO: 'info',
};

const SEVERITY_AR: Record<HealthIssue['severity'], string> = {
  CRITICAL: 'حرج',
  WARNING: 'تنبيه',
  INFO: 'معلومة',
};

/**
 * Company health check: one screen that answers "what is wrong or missing?"
 * in plain Arabic, each item one tap away from the page that fixes it.
 * Read-only: every fact comes from an existing read model.
 */
export default async function HealthPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="فحص الصحة يقرأ سجلات المنظمة، فأنشئ المنظمة أولًا."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }

  const [projects, signals] = await Promise.all([
    getProjects(org.id),
    getIntegritySignals(org.id),
  ]);

  const perProject = await Promise.all(
    projects.map(async (project) => {
      const [position, unreconciled] = await Promise.all([
        getProjectPosition(project.id),
        getUnreconciledPositiveStatementLines(project.id),
      ]);
      return {
        projectId: project.id,
        projectName: project.name,
        overdueObligations: position?.overdue_obligations ?? 0,
        disputedObligations: position?.disputed_obligations ?? 0,
        unreconciledInflowCount: unreconciled.length,
        unreconciledInflowCurrency: unreconciled[0]?.currency ?? null,
      };
    }),
  );

  const issues = sortIssues([
    ...signalIssues(
      signals.map((signal) => ({
        projectId: signal.project_id,
        signalLabelAr: signal.signal_label_ar,
        severity: signal.severity,
        subjectCount: signal.subject_count,
      })),
    ),
    ...perProject.flatMap(projectIssues),
  ]);

  return (
    <>
      <PageHeader
        title="فحص صحة الشركة"
        description={verdictAr(issues)}
      />
      <Section title={`المشاكل والنواقص (${issues.length})`}>
        {issues.length === 0 ? (
          <EmptyState
            title="كل شيء سليم"
            description="لا التزامات متأخرة، لا حركات بنكية غير مطابَقة، ولا إشارات سلامة مفتوحة."
          />
        ) : (
          <ul className="health-issues">
            {issues.map((issue, index) => (
              <li key={index} className="health-issue">
                <StatusBadge tone={SEVERITY_TONE[issue.severity]}>{SEVERITY_AR[issue.severity]}</StatusBadge>
                <span className="health-issue-message">{issue.messageAr}</span>
                <Link className="button" href={issue.href}>{issue.actionAr}</Link>
              </li>
            ))}
          </ul>
        )}
      </Section>
    </>
  );
}
