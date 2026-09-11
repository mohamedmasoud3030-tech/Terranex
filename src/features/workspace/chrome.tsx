import Link from 'next/link';
import { getProject } from '@/features/projects/queries';
import { SECTOR_LABEL } from '@/features/agriculture/labels';
import { PermissionState, StatusBadge } from '@/shared/ui';
import { SectorChip } from '@/shared/ui/index';
import { SECTOR_THEME_CLASS } from '@/shared/ui/sector';
import { WorkspaceNavGrouped, type WorkspaceSection, type WorkspaceSector } from './nav';
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
 *
 * The header carries the sector twice — as a chip beside the title and as an
 * accent rail on the header edge — because an operator working across
 * portfolios must never have to infer which vertical's rules they are under.
 * The accent is identity only; it never encodes state.
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
  const themeClass = resolvedSector ? SECTOR_THEME_CLASS[resolvedSector] : '';
  return (
    <>
      <header className={`project-context card page-header ${themeClass}`.trim()}>
        <div className="page-header-main">
          <Link className="back-link" href={`/projects/${projectId}`}>
            → مساحة المشروع
          </Link>
          <div className="page-title-row">
            <h1>{title}</h1>
            {resolvedSector ? (
              <SectorChip sector={resolvedSector} label={SECTOR_LABEL[resolvedSector]} />
            ) : null}
            {resolvedLifecycle ? (
              <StatusBadge tone={projectLifecycleTone(resolvedLifecycle)}>
                {PROJECT_LIFECYCLE_LABEL[resolvedLifecycle] ?? resolvedLifecycle}
              </StatusBadge>
            ) : null}
          </div>
          {subtitle ? <p className="muted page-description">{subtitle}</p> : null}
        </div>
        {actions ? <div className="page-actions">{actions}</div> : null}
      </header>
      <DemoBanner internalReference={internalReference} />
      {resolvedSector ? (
        <div className={themeClass}>
          <WorkspaceNavGrouped projectId={projectId} active={active} sector={resolvedSector} />
        </div>
      ) : null}
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
