import type { DOCUMENT_CATEGORIES } from './schema';

export const DOCUMENT_CATEGORY_LABEL: Record<(typeof DOCUMENT_CATEGORIES)[number], string> = {
  CONTRACT: 'عقد',
  LICENSE: 'ترخيص',
  CERTIFICATE: 'شهادة',
  CORRESPONDENCE: 'مراسلات',
  FINANCIAL: 'مالي',
  GENERAL: 'عام',
};
