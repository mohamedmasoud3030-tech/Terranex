import { notFound } from 'next/navigation';
import { WorkspaceChrome } from '@/features/workspace/chrome';
import { Section, SectionTabs } from '@/shared/ui';
import { getProject } from '@/features/projects/queries';
import { newCommandNonce } from '@/shared/idempotency';
import { getCurrentMembership, getOrganizationLedger } from '@/features/finance/queries';
import { JournalTrace } from '@/features/finance/journal-trace';
import { AdjustmentForm } from './forms';

export const dynamic = 'force-dynamic';

export default async function AdjustmentsPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;
  const [membership, ledger] = await Promise.all([
    getCurrentMembership(organizationId),
    getOrganizationLedger(organizationId, 500),
  ]);
  const isOwner = membership?.role === 'OWNER';
  const lines = ledger.filter((l) => l.project_id === projectId && l.source_type === 'MANUAL_ADJUSTMENT');

  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="costs-cash"
        title="قيود التسوية اليدوية"
        subtitle={`${project.name} · ${project.reporting_currency}`}
        internalReference={project.internal_reference}
        sector={project.sector}
        lifecycleState={project.lifecycle_state}
      />
      <SectionTabs
        label="التكاليف والنقدية"
        items={[
          { href: `/projects/${projectId}/costs`, label: 'التكاليف والالتزامات' },
          { href: `/projects/${projectId}/cash`, label: 'النقدية والبنك' },
          { href: `/projects/${projectId}/adjustments`, label: 'قيود التسوية', current: true },
        ]}
      />
      <Section title="قيد تسوية جديد" description="إعادة تصنيف مبلغ بين حسابات التكلفة بقيد متوازن وبدليل موثق.">
        {isOwner ? (
          <AdjustmentForm
            organizationId={organizationId}
            projectId={projectId}
            currency={project.reporting_currency}
            commandNonce={newCommandNonce()}
          />
        ) : (
          <p className="muted">ترحيل قيود التسوية متاح لمالك المنظمة فقط.</p>
        )}
      </Section>
      <Section title="القيود المرحّلة">
        <JournalTrace lines={lines} />
      </Section>
    </section>
  );
}
