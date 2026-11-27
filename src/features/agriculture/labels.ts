// Centralized Arabic labels for Agriculture slice.
// Truthful, no fabricated financial terms. Mirrors the canonical
// lifecycle documented in docs/greenfield/04_SECTOR_MODELS.md.

export { SECTOR_LABEL } from '@/shared/labels';

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

export const FIELD_ACTIVITY_TYPE_LABEL: Record<string, string> = {
  PREPARE: 'تجهيز',
  PLANT: 'زراعة',
  IRRIGATE: 'ري',
  FERTILIZE: 'تسميد',
  SPRAY: 'رش',
  SCOUT: 'معاينة',
  WEED: 'تعشيب',
  OTHER: 'أخرى',
};

export function formatFieldActivityType(type: string | null | undefined): string {
  if (!type) return '—';
  return FIELD_ACTIVITY_TYPE_LABEL[type] ?? type;
}

// GF-015 — Field Input Application. Only the three field-applied
// categories this slice supports are labelled; fuel/packaging are not
// modelled and must not appear as if they were.
export const INPUT_CATEGORY_LABEL: Record<string, string> = {
  SEED: 'تقاوي',
  FERTILIZER: 'سماد',
  CHEMICAL: 'مبيد/كيماوي',
};

export const LOT_EXPIRY_STATUS_LABEL: Record<string, string> = {
  VALID: 'سارية',
  EXPIRED: 'منتهية',
  NO_EXPIRY: 'بدون تاريخ انتهاء',
};

export function formatInputCategory(category: string | null | undefined): string {
  if (!category) return '—';
  return INPUT_CATEGORY_LABEL[category] ?? category;
}

export function formatLotExpiryStatus(status: string | null | undefined): string {
  if (!status) return '—';
  return LOT_EXPIRY_STATUS_LABEL[status] ?? status;
}

/** Quantity plus a free-text input unit (كجم، لتر…), not an area unit. */
export function formatInputQuantity(
  value: string | null | undefined,
  unit: string | null | undefined,
): string {
  if (!value) return '—';
  return `${value} ${unit ?? ''}`.trim();
}

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

// GF-016 — Harvest & Inventory movement labels, extended by GF-018 with the
// bounded physical SALE_ISSUE. No valuation term is fabricated here.
export const HARVEST_MOVEMENT_TYPE_LABEL: Record<string, string> = {
  HARVEST_RECEIPT: 'استلام حصاد',
  TRANSFER: 'تحويل',
  ADJUSTMENT_IN: 'تعديل زيادة',
  ADJUSTMENT_OUT: 'تعديل نقص',
  SPOILAGE: 'تالف/هالك',
  SALE_ISSUE: 'صرف بيع/تسليم',
};

export function formatHarvestMovementType(type: string | null | undefined): string {
  if (!type) return '—';
  return HARVEST_MOVEMENT_TYPE_LABEL[type] ?? type;
}

/** Harvest quantity plus a free-text quantity unit (كجم، طن…). */
export function formatHarvestQuantity(
  value: string | null | undefined,
  unit: string | null | undefined,
): string {
  if (!value) return '—';
  return `${value} ${unit ?? ''}`.trim();
}

// GF-017 — legal/economic control wording. None of the non-purchase labels
// claims ownership, and purchase still does not imply title or payment.
export const LAND_CONTROL_BASIS_LABEL: Record<string, string> = {
  PURCHASED: 'مشتراة — مقابل متفق عليه منفصل عن السداد',
  LEASED: 'مؤجرة — حق تشغيل بعقد، وليست مملوكة',
  CONTRIBUTED_IN_KIND: 'مساهمة عينية معتمدة — دون إثبات نقدي تلقائي',
  MANAGED_FOR_OWNER: 'تُدار لحساب المالك — ليست مملوكة للمشروع',
};

export function formatLandControlBasis(basis: string | null | undefined): string {
  if (!basis) return '—';
  return LAND_CONTROL_BASIS_LABEL[basis] ?? basis;
}

// GF-018 — sale/control transfer and collection remain distinct in wording.
export const AGRICULTURE_SALE_STATE_LABEL: Record<string, string> = {
  DRAFT: 'مسودة — لا مخزون ولا إيراد',
  APPROVED: 'معتمد — بانتظار التسليم',
  CONTROL_TRANSFERRED: 'تم التسليم والاعتراف بالإيراد',
  SETTLED: 'محصّل بالكامل',
};

export function formatAgricultureSaleState(state: string | null | undefined): string {
  if (!state) return '—';
  return AGRICULTURE_SALE_STATE_LABEL[state] ?? state;
}

// GF-019 — operator-facing result and cost labels.
export const CROP_CYCLE_COST_CATEGORY_LABEL: Record<string, string> = {
  INPUTS: 'مدخلات زراعية',
  LABOR: 'عمالة',
  EQUIPMENT: 'معدات وتشغيل',
  IRRIGATION: 'ري',
  HARVEST: 'حصاد',
  STORAGE: 'تخزين',
  OTHER: 'تشغيل أخرى',
};

export const EVIDENCE_COMPLETENESS_LABEL: Record<string, string> = {
  COMPLETE: 'المصادر والأدلة مكتملة',
  PARTIAL: 'بعض الأدلة المرجعية غير مسجلة',
  INCOMPLETE: 'أساس النتيجة غير مكتمل',
};

export function formatCostCategory(category: string): string {
  return CROP_CYCLE_COST_CATEGORY_LABEL[category] ?? category;
}

export function formatEvidenceCompleteness(status: string): string {
  return EVIDENCE_COMPLETENESS_LABEL[status] ?? status;
}
