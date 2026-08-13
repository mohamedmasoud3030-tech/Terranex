// Centralized Arabic labels for Agriculture slice.
// Truthful, no fabricated financial terms. Mirrors the canonical
// lifecycle documented in docs/greenfield/04_SECTOR_MODELS.md.

export const SECTOR_LABEL: Record<'REAL_ESTATE' | 'AGRICULTURE', string> = {
  REAL_ESTATE: 'عقارات',
  AGRICULTURE: 'زراعة',
};

export const AREA_UNIT_LABEL: Record<'M2' | 'HECTARE' | 'FEDDAN', string> = {
  M2: 'م²',
  HECTARE: 'هكتار',
  FEDDAN: 'فدان',
};

export const CYCLE_STATE_LABEL: Record<string, string> = {
  PLANNED: 'مخططة',
  ESTABLISHED: 'مُنشأة',
  GROWING: 'قيد النمو',
  HARVESTING: 'قيد الحصاد',
  CLOSED: 'مُغلقة',
  CANCELLED: 'ملغاة',
  FAILED: 'فشلت',
};

export function formatCycleState(state: string | null | undefined): string {
  if (!state) return '—';
  return CYCLE_STATE_LABEL[state] ?? state;
}

export function formatAreaUnit(unit: string | null | undefined): string {
  if (!unit) return '—';
  return AREA_UNIT_LABEL[unit as 'M2' | 'HECTARE' | 'FEDDAN'] ?? unit;
}

export function formatQuantity(value: string | null | undefined, unit: string | null | undefined): string {
  if (!value) return '—';
  return `${value} ${formatAreaUnit(unit)}`.trim();
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return '—';
  return new Date(value).toLocaleDateString('ar-EG');
}
