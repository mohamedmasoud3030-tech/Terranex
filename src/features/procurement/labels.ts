export const SUPPLIER_STATUS_LABEL: Record<string, string> = { ACTIVE: 'نشط', INACTIVE: 'موقوف' };
export const PURCHASE_DOCUMENT_STATE_LABEL: Record<string, string> = {
  DRAFT: 'مسودة', SUBMITTED: 'قيد الاعتماد', APPROVED: 'معتمد', REJECTED: 'مرفوض', CANCELLED: 'ملغي',
};
export const PAYMENT_STATE_LABEL: Record<string, string> = {
  PAYABLE_REVERSED: 'تم عكس المستحق', UNPAID: 'غير مدفوع',
  PARTIALLY_PAID: 'مدفوع جزئيًا', FULLY_PAID: 'مدفوع بالكامل',
};
export const RECONCILIATION_STATE_LABEL: Record<string, string> = {
  NOT_PAID: 'لم يُدفع', PAID_UNRECONCILED: 'مدفوع وغير مطابق بنكيًا',
  PARTIALLY_RECONCILED: 'مطابق جزئيًا', RECONCILED: 'تمت المطابقة البنكية',
};
export function formatSupplierStatus(status?: string | null) { return status ? (SUPPLIER_STATUS_LABEL[status] ?? status) : '—'; }
export function formatDocumentState(status?: string | null) { return status ? (PURCHASE_DOCUMENT_STATE_LABEL[status] ?? status) : '—'; }
export function formatPaymentState(status?: string | null) { return status ? (PAYMENT_STATE_LABEL[status] ?? status) : '—'; }
export function formatReconciliationState(status?: string | null) { return status ? (RECONCILIATION_STATE_LABEL[status] ?? status) : '—'; }
export function formatQuantity(value?: string | null, unit?: string | null) { return value ? `${value} ${unit ?? ''}`.trim() : '—'; }
export function formatDate(value?: string | null) {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleDateString('ar-EG');
}
export const EVIDENCE_CLASSIFICATION_LABEL: Record<string, string> = {
  CONTRACT: 'عقد تجاري', PURCHASE_ORDER: 'أمر شراء', RECEIPT: 'دليل استلام', SUPPLIER_INVOICE: 'فاتورة مورد',
};
