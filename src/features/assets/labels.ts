// Arabic labels for the R8 cross-sector asset register.
//
// The *_status vocabulary is the honest core of this slice: where a sector
// owns no fact for a concept, the register says so in words instead of
// emitting a zero. These labels must preserve that distinction in Arabic —
// "not recorded yet" and "does not apply to this asset kind" are different
// statements to an operator, and collapsing them into a dash would put back
// exactly the ambiguity the read model removes.

export const ASSET_KIND_LABEL: Record<string, string> = {
  PROPERTY_ASSET: 'أصل عقاري',
  AGRICULTURAL_LAND_ASSET: 'أرض زراعية',
  FARM: 'مزرعة',
  LIVESTOCK_SITE: 'موقع ثروة حيوانية',
};

export const ASSET_STATE_LABEL: Record<string, string> = {
  CANDIDATE: 'مرشح',
  DUE_DILIGENCE: 'فحص نافي للجهالة',
  ACQUIRING: 'قيد الاستحواذ',
  HELD: 'مُحتفظ به / تحت السيطرة',
  DEVELOPING: 'قيد التطوير',
  EXITING: 'قيد التخارج',
  DISPOSED: 'تم التصرف',
};

/** Real-estate strategy and agricultural control basis both land in the
 * register's single `asset_classification` column; each sector keeps its own
 * vocabulary rather than being flattened into a shared invented enum. */
export const ASSET_CLASSIFICATION_LABEL: Record<string, string> = {
  ACQUIRE_HOLD: 'اقتناء واحتفاظ',
  DEVELOP_SELL: 'تطوير وبيع',
  LAND_TRADE: 'تجارة أراضٍ',
  PURCHASED: 'مشتراة',
  LEASED: 'مستأجرة',
  CONTRIBUTED_IN_KIND: 'مساهمة عينية',
  MANAGED_FOR_OWNER: 'مُدارة لحساب المالك',
  FARM: 'مزرعة',
  BARN: 'حظيرة',
  PASTURE: 'مرعى',
  OTHER: 'أخرى',
};

/** Why a figure is absent. Never rendered as a number or a bare dash. */
export const ABSENCE_REASON_LABEL: Record<string, string> = {
  NOT_RECORDED: 'لم تُسجَّل بعد',
  NOT_APPLICABLE_NO_ACQUISITION_FACT: 'لا ينطبق على هذا النوع من الأصول',
  NOT_MODELLED_FOR_THIS_ASSET_KIND: 'لا توجد دورة حالة لهذا النوع',
  UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY: 'غير متاحة — لا توجد سياسة معتمدة بعد',
  NO_APPROVED_VALUATION: 'لا يوجد تقييم معتمد',
  NO_RECOGNIZED_SALE: 'لا يوجد بيع معترف به',
};

/** Why a figure is present — the basis the operator is reading. */
export const BASIS_LABEL: Record<string, string> = {
  CONTRACTED_CONSIDERATION_AND_CLOSING_COSTS: 'المقابل التعاقدي + تكاليف الإتمام',
  AGREED_CONSIDERATION: 'المقابل المتفق عليه',
  APPROVED_VALUATION: 'تقييم معتمد',
  REALIZED_ON_RECOGNIZED_SALE: 'محقق على بيع معترف به',
  PROPERTY_STATE_HISTORY: 'سجل حالات الأصل',
};

export const FX_STATUS_LABEL: Record<string, string> = {
  NO_REPORTING_CURRENCY: 'لا توجد عملة تقرير للمنظمة',
  SAME_CURRENCY: 'نفس عملة التقرير',
  NO_RATE_SNAPSHOT: 'لا توجد لقطة سعر صرف',
  CONVERTED_AT_RATE: 'محوّلة بسعر مسجّل',
};

export { SECTOR_LABEL } from '@/shared/labels';

/** Resolves any status string to operator Arabic, falling back to the raw
 * token rather than to a dash: an unexplained blank is worse than an
 * untranslated code, because only one of the two is debuggable. */
export function statusLabel(status: string): string {
  return ABSENCE_REASON_LABEL[status] ?? BASIS_LABEL[status] ?? status;
}

/** True when a status means "no such fact exists", i.e. the row must show a
 * reason rather than a figure. */
export function isAbsence(status: string): boolean {
  return status in ABSENCE_REASON_LABEL;
}
