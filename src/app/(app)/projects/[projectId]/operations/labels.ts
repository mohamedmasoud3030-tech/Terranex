// Plain module: labels used by both server pages and client forms.
// (Constants exported from a use-client file are not readable on the server.)

export const ASSET_STATE: Record<string, string> = {
  CANDIDATE: 'مرشح',
  DUE_DILIGENCE: 'فحص نافي للجهالة',
  ACQUIRING: 'قيد الاستحواذ',
  HELD: 'مُحتفظ به / تحت السيطرة',
  DEVELOPING: 'قيد التطوير',
  EXITING: 'قيد التخارج',
  DISPOSED: 'تم التصرف',
};

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
