import Link from 'next/link';
import { getProject } from '@/features/projects/queries';
import { SECTOR_LABEL } from '@/features/agriculture/labels';
import { PermissionState, StatusBadge } from '@/shared/ui';
import { WorkspaceNav, type WorkspaceSection, type WorkspaceSector } from './nav';
import { PROJECT_LIFECYCLE_LABEL, projectLifecycleTone } from '@/features/projects/labels';

export function DemoBanner({ internalReference }: { internalReference: string | null | undefined }) {
  if (!internalReference?.startsWith('DEMO')) return null;
  return (
    <div
      className="banner info compact"
      role="note"
      title="تُستخدم للمعاينة والتدريب والتحقق، ولا تُحتسب كدليل عميل حقيقي أو إغلاق لأي بوابة مرحلَة ثانية أو ثالثة."
    >
      بيانات توضيحية اصطناعية ({internalReference}) — ليست دليل عميل حقيقي.
    </div>
  );
}

/**
 * Project workspace header + section navigation shared by every project
 * route. The section nav is always rendered: when the caller does not pass
 * `sector`/`lifecycleState` (older pages), they are resolved from the project
 * record so no workspace page loses its navigation.
 */
export async function WorkspaceChrome({
  projectId,
  active,
  title,
  subtitle,
  internalReference,
  sector,
  lifecycleState,
  actions,
}: {
  projectId: string;
  active: WorkspaceSection;
  title: string;
  subtitle?: string;
  internalReference?: string | null;
  sector?: WorkspaceSector;
  lifecycleState?: string | null;
  actions?: React.ReactNode;
}) {
  let resolvedSector = sector;
  let resolvedLifecycle = lifecycleState;
  if (!resolvedSector || resolvedLifecycle === undefined) {
    const project = await getProject(projectId);
    resolvedSector = resolvedSector ?? project?.sector;
    resolvedLifecycle = resolvedLifecycle ?? project?.lifecycle_state ?? null;
  }
  return (
    <>
      <header className="project-context card page-header">
        <div className="page-header-main">
          <Link className="muted back-link" href={`/projects/${projectId}`}>← مساحة المشروع</Link>
          <div className="page-title-row">
            <h1>{title}</h1>
            {resolvedLifecycle ? (
              <StatusBadge tone={projectLifecycleTone(resolvedLifecycle)}>
                {PROJECT_LIFECYCLE_LABEL[resolvedLifecycle] ?? resolvedLifecycle}
              </StatusBadge>
            ) : null}
            {resolvedSector ? <StatusBadge>{SECTOR_LABEL[resolvedSector] ?? resolvedSector}</StatusBadge> : null}
          </div>
          {subtitle ? <p className="muted page-description">{subtitle}</p> : null}
        </div>
        {actions ? <div className="page-actions">{actions}</div> : null}
      </header>
      <DemoBanner internalReference={internalReference} />
      {resolvedSector ? <WorkspaceNav projectId={projectId} active={active} sector={resolvedSector} /> : null}
    </>
  );
}

/** Kept for existing consumers; canonical component is `PermissionState`. */
export function ForbiddenCard({ projectId, message }: { projectId: string; message: string }) {
  return <PermissionState message={message} backHref={`/projects/${projectId}`} backLabel="العودة للمشروع" />;
}

export function memberDisplayLabel(role: string, index: number) {
  const rank = index + 1;
  return role === 'OWNER' ? `مالك المنظمة ${rank}` : `عضو تشغيلي ${rank}`;
}
