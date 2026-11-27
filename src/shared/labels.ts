// Shared Arabic labels for vocabularies used by more than one feature.
//
// Single source of truth: pages and feature label modules import from here
// instead of redefining the same Record locally. A label map may only move
// here when two or more independent surfaces render the same vocabulary;
// sector-specific wording stays in the owning feature's labels module.

/** Investment sectors. Rendered identically everywhere the sector appears. */
export const SECTOR_LABEL: Record<'REAL_ESTATE' | 'AGRICULTURE' | 'LIVESTOCK', string> = {
  REAL_ESTATE: 'عقارات',
  AGRICULTURE: 'زراعة',
  LIVESTOCK: 'ثروة حيوانية',
};

/** Human acceptance (UAT) lifecycle, shared by the pilot and controls pages. */
export const UAT_STATUS_LABEL: Record<string, string> = {
  NOT_STARTED: 'لم يبدأ',
  PENDING: 'قيد التنفيذ — لم يُقبل بعد',
  ACCEPTED: 'مقبول بدليل بشري',
  REJECTED: 'مرفوض',
};

/** Asset disposition lifecycle, shared by the revenue and operations pages. */
export const DISPOSITION_STATUS_LABEL: Record<string, string> = {
  DRAFT: 'مسودة اتفاق',
  APPROVED: 'اتفاق معتمد',
  CONTROL_TRANSFERRED: 'انتقلت السيطرة',
};

/** Cost treatment, shared by the costs page and the budget forms. */
export const COST_TREATMENT_LABEL: Record<string, string> = {
  EXPENSE: 'مصروف',
  CAPITALIZABLE_WIP: 'أعمال تحت التطوير',
};
