export const SITE_TYPE_LABEL: Record<string, string> = {
  FARM: 'مزرعة تشغيل',
  BARN: 'حظيرة',
  PASTURE: 'مرعى',
  OTHER: 'موقع آخر',
};

export const SPECIES_LABEL: Record<string, string> = {
  CATTLE: 'أبقار',
  BUFFALO: 'جاموس',
  SHEEP: 'أغنام',
  GOAT: 'ماعز',
};

export const PURPOSE_LABEL: Record<string, string> = {
  MEAT: 'تسمين/لحوم',
  BREEDING: 'إكثار',
  MIXED: 'مختلط',
};

export const ORIGIN_LABEL: Record<string, string> = {
  PURCHASED: 'شراء — دون إثبات سداد أو قيمة محاسبية',
  BORN: 'مولودة داخل التشغيل',
  CONTRIBUTED_IN_KIND: 'مساهمة عينية — دون مساهمة نقدية',
  TRANSFERRED_IN: 'محولة إلى التشغيل',
  OPENING_BALANCE: 'رصيد تشغيلي افتتاحي',
  SPLIT_FROM_COHORT: 'ناتجة عن تقسيم دفعة — لا يوجد عدد افتتاحي',
  MERGED_FROM_COHORTS: 'ناتجة عن دمج دفعات — لا يوجد عدد افتتاحي',
};

export const SEX_LABEL: Record<string, string> = {
  MALE: 'ذكور',
  FEMALE: 'إناث',
  MIXED: 'مختلط',
};

export const WEIGHT_BASIS_LABEL: Record<string, string> = {
  INDIVIDUAL_MEASURED: 'قياس فردي موثق',
  COHORT_TOTAL: 'إجمالي الدفعة',
  ESTIMATED: 'تقديري',
};

export const COHORT_STATE_LABEL: Record<string, string> = {
  PLANNED: 'مخططة',
  ACTIVE: 'نشطة',
};

/**
 * GF-021 weight-method labels.
 *
 * The Arabic wording must keep a measured figure, a sampled figure, and an
 * estimate visibly distinct; an estimate is never phrased as a measurement.
 */
export const WEIGHT_METHOD_LABEL: Record<string, string> = {
  INDIVIDUAL_MEASURED: 'وزن مقاس فرديًا',
  COHORT_TOTAL: 'وزن مقاس لإجمالي الدفعة',
  SAMPLED_AVERAGE: 'وزن بالعينة (متوسط)',
  ESTIMATED: 'وزن تقديري',
};

/** What the stored number actually MEANS for each method. */
export const WEIGHT_MEANING_LABEL: Record<string, string> = {
  TOTAL_OF_MEASURED_ANIMALS: 'إجمالي وزن الحيوانات المقاسة',
  COHORT_TOTAL_MEASURED: 'إجمالي وزن الدفعة المقاس',
  AVERAGE_PER_ANIMAL_SAMPLED: 'متوسط وزن الرأس في العينة',
  COHORT_TOTAL_ESTIMATED: 'إجمالي وزن الدفعة تقديريًا',
};

/** Where the derived current placement came from. */
export const PLACEMENT_SOURCE_LABEL: Record<string, string> = {
  OPENING: 'من الوضع الافتتاحي (لم تُسجَّل حركة بعد)',
  MOVEMENT: 'من آخر حركة مسجلة',
};

/** How a movement changed the placement. */
export function movementChangeLabel(
  siteChanged: boolean,
  herdChanged: boolean,
): string {
  if (siteChanged && herdChanged) return 'نقل الموقع وإعادة تصنيف القطيع';
  if (siteChanged) return 'نقل بين مواقع التشغيل';
  return 'إعادة تصنيف بين القطعان';
}

/** GF-022 quantity event classes. */
export const QUANTITY_EVENT_LABEL: Record<string, string> = {
  BIRTH: 'ولادات',
  MORTALITY: 'نفوق',
  SPLIT_OUT: 'صادر إلى تقسيم',
  SPLIT_IN: 'وارد من تقسيم',
  MERGE_OUT: 'صادر إلى دمج',
  MERGE_IN: 'وارد من دمج',
};

/** GF-022 mortality cause categories. */
export const MORTALITY_CAUSE_LABEL: Record<string, string> = {
  DISEASE: 'مرض',
  INJURY: 'إصابة',
  PREDATION: 'افتراس',
  WEATHER: 'إجهاد مناخي',
  BIRTH_COMPLICATION: 'مضاعفات ولادة',
  UNKNOWN: 'غير معروف',
  OTHER: 'سبب آخر',
};

/** Disposal is operational evidence, not a Finance posting decision. */
export const DISPOSAL_METHOD_LABEL: Record<string, string> = {
  BURIAL: 'دفن',
  INCINERATION: 'حرق/إتلاف حراري',
  RENDERING: 'تصنيع/تحويل مرخّص',
  COMPOSTING: 'تحلل عضوي',
  OTHER: 'طريقة أخرى',
  PENDING: 'لم تُحدَّد بعد',
};

/** Qualitative only; this is not a statistical confidence interval. */
export const WEIGHT_CONFIDENCE_LABEL: Record<string, string> = {
  UNASSESSED: 'غير مُقيّمة',
  LOW: 'منخفضة',
  MEDIUM: 'متوسطة',
  HIGH: 'مرتفعة',
};

export const OPERATION_TYPE_LABEL: Record<string, string> = {
  SPLIT: 'تقسيم دفعة',
  MERGE: 'دمج دفعات',
};

/** Origins introduced by GF-022 for Cohorts produced by an operation. */
export const DERIVED_ORIGIN_LABEL: Record<string, string> = {
  SPLIT_FROM_COHORT: 'ناتجة عن تقسيم دفعة — لا يوجد عدد افتتاحي',
  MERGED_FROM_COHORTS: 'ناتجة عن دمج دفعات — لا يوجد عدد افتتاحي',
};
