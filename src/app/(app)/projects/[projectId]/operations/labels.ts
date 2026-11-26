// Plain module: labels used by both server pages and client forms.
// (Constants exported from a use-client file are not readable on the server.)

// One source for asset states: the shared label map.
export { ASSET_STATE_LABEL as ASSET_STATE } from '@/features/assets/labels';

export const STEP_STATE: Record<string, string> = {
  PLANNED: 'مخطط',
  ACTIVE: 'نشط',
  COMPLETED: 'مكتمل',
  CANCELLED: 'ملغى',
};

export const CATEGORY: Record<string, string> = {
  ACQUISITION: 'استحواذ',
  LEGAL_DUE_DILIGENCE: 'فحص قانوني',
  SITE_PREPARATION: 'تجهيز الموقع',
  CONSTRUCTION: 'إنشاءات',
  PROFESSIONAL_FEES: 'أتعاب مهنية',
  HOLDING: 'تكاليف احتفاظ',
  OTHER: 'أخرى',
};
