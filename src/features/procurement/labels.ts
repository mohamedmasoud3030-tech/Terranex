// GF-025 / R4 — Procurement Foundation: Arabic labels & formatters.
// Truthful, no fabricated financial terms (this slice carries quantity only).

export const SUPPLIER_STATUS_LABEL: Record<string, string> = {
  ACTIVE: 'نشط',
  INACTIVE: 'موقوف',
};

export const PURCHASE_DOCUMENT_STATE_LABEL: Record<string, string> = {
  DRAFT: 'مسودة',
  SUBMITTED: 'قيد الاعتماد',
  APPROVED: 'معتمد',
  REJECTED: 'مرفوض',
  CANCELLED: 'ملغي',
};

export function formatSupplierStatus(status: string | null | undefined): string {
  if (!status) return '—';
  return SUPPLIER_STATUS_LABEL[status] ?? status;
}

export function formatDocumentState(state: string | null | undefined): string {
  if (!state) return '—';
  return PURCHASE_DOCUMENT_STATE_LABEL[state] ?? state;
}

export function formatQuantity(value: string | null | undefined, unit: string | null | undefined): string {
  if (!value) return '—';
  return `${value} ${unit ?? ''}`.trim();
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleDateString('ar-EG');
}
