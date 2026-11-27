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

export { SECTOR_LABEL } from '@/shared/labels';

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

/**
 * Arabic labels for the record-status codes the schema actually permits.
 *
 * Every key below is a value from a CHECK constraint in supabase/migrations,
 * not an invented state:
 *   memberships.status                 ACTIVE | INACTIVE
 *   property_controls.status           PENDING | PASSED | FAILED | EXPIRED
 *   close_runs.status                  PREPARED | APPROVED | REJECTED
 *   close_run_exceptions.status        PENDING | APPROVED | REJECTED
 *   agreement_versions.status          DRAFT | ACTIVE | SUPERSEDED
 *   s7_opening_imports.status          DRAFT | VALIDATED | READY_FOR_APPROVAL
 *                                      | APPROVED | POSTED | REJECTED | FAILED
 * plus the finance workspace codes already labelled here.
 *
 * Codes that appear in more than one domain take the wording that is true in
 * all of them; a caller needing a domain-specific phrasing passes its own.
 */
export const RECORD_STATUS_LABEL: Record<string, string> = {
  OPEN: 'مفتوح',
  RESOLVED: 'مُعالج',
  REQUESTED: 'مطلوب',
  APPROVED: 'معتمد',
  REJECTED: 'مرفوض',
  EXECUTED: 'منفّذ',
  VOID: 'ملغى',
  PENDING: 'قيد الانتظار',
  ACTIVE: 'نشط',
  INACTIVE: 'غير نشط',
  DRAFT: 'مسودة',
  POSTED: 'مُرحّل',
  REVERSED: 'معكوس',
  PASSED: 'ناجح',
  FAILED: 'فاشل',
  EXPIRED: 'منتهي الصلاحية',
  SUPERSEDED: 'مُستبدَل',
  PREPARED: 'مُعدّ',
  VALIDATED: 'مُتحقَّق منه',
  READY_FOR_APPROVAL: 'جاهز للاعتماد',
};

/**
 * Renders a status code in Arabic, falling back to the raw code rather than
 * to a guess. An untranslated code reaching the UI is a defect; a visible raw
 * code is at least honest, and this fallback keeps it from becoming a blank
 * or a wrong label.
 */
export function recordStatusLabel(code: string | null | undefined): string {
  if (!code) return '—';
  return RECORD_STATUS_LABEL[code] ?? code;
}

/** Membership roles. The schema permits exactly OWNER and MEMBER. */
export const ROLE_LABEL: Record<string, string> = {
  OWNER: 'مالك المنظمة',
  MEMBER: 'عضو',
};

export function roleLabel(role: string | null | undefined): string {
  if (!role) return '—';
  return ROLE_LABEL[role] ?? role;
}
