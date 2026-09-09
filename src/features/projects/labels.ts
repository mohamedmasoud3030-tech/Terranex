import type { BadgeTone } from '@/shared/ui';

/**
 * Arabic operator labels for project lifecycle states. The database currently
 * constrains `lifecycle_state` to DRAFT | FUNDING; unknown values fall back to
 * the raw code so nothing is hidden.
 */
export const PROJECT_LIFECYCLE_LABEL: Record<string, string> = {
  DRAFT: 'مسودة',
  FUNDING: 'مرحلة التمويل',
};

export function projectLifecycleTone(state: string): BadgeTone {
  if (state === 'FUNDING') return 'success';
  if (state === 'DRAFT') return 'neutral';
  return 'info';
}

export const SECTOR_LABEL: Record<string, string> = {
  REAL_ESTATE: 'عقارات',
  AGRICULTURE: 'زراعة',
  LIVESTOCK: 'ثروة حيوانية',
};

/** Arabic labels + tones for integrity-signal severity. */
export const SEVERITY_LABEL: Record<string, string> = {
  CRITICAL: 'حرج',
  WARNING: 'تحذير',
  INFO: 'معلومة',
};

export function severityTone(severity: string): BadgeTone {
  if (severity === 'CRITICAL') return 'danger';
  if (severity === 'WARNING') return 'warning';
  return 'info';
}
