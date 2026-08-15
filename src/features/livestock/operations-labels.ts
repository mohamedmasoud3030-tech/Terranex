export const MEDICINE_PRODUCT_KIND_LABEL: Record<string, string> = {
  MEDICINE: 'دواء/علاج', VACCINE: 'لقاح',
};
export const ANIMAL_IDENTIFIER_TYPE_LABEL: Record<string, string> = {
  EAR_TAG: 'قرط أذن', RFID: 'معرّف RFID', OTHER: 'معرّف آخر',
};
export const ANIMAL_SEX_LABEL: Record<string, string> = {
  MALE: 'ذكر', FEMALE: 'أنثى', UNKNOWN: 'غير محدد',
};
export const HEALTH_EVENT_LABEL: Record<string, string> = {
  OBSERVATION: 'ملاحظة صحية', DIAGNOSIS: 'تشخيص', TREATMENT: 'علاج', VACCINATION: 'تطعيم',
};
export const CONDITION_LABEL: Record<string, string> = {
  INFECTIOUS: 'معدية', PARASITIC: 'طفيلية', INJURY: 'إصابة', RESPIRATORY: 'تنفسية',
  DIGESTIVE: 'هضمية', REPRODUCTIVE: 'تناسلية', NUTRITIONAL: 'تغذوية', OTHER: 'أخرى',
};
export const DOSE_UNIT_LABEL: Record<string, string> = {
  ML: 'مل', MG: 'مجم', G: 'جم', DOSE: 'جرعة', TABLET: 'قرص',
};
export const ADMINISTRATION_ROUTE_LABEL: Record<string, string> = {
  ORAL: 'فموي', INJECTION: 'حقن', TOPICAL: 'موضعي', OTHER: 'أخرى',
};
export const WITHDRAWAL_STATUS_LABEL: Record<string, string> = {
  NONE: 'لا توجد فترة سحب', ACTIVE: 'فترة السحب سارية', ENDED: 'فترة السحب منتهية',
};
export const REPRODUCTION_EVENT_LABEL: Record<string, string> = {
  BREEDING_SERVICE: 'تلقيح/خدمة', PREGNANCY_CHECK: 'فحص حمل',
  BIRTH_OUTCOME: 'نتيجة ولادة', WEANING: 'فطام',
};
export const SERVICE_METHOD_LABEL: Record<string, string> = {
  NATURAL: 'تلقيح طبيعي', ARTIFICIAL_INSEMINATION: 'تلقيح اصطناعي', OTHER: 'طريقة أخرى',
};
export const PREGNANCY_STATUS_LABEL: Record<string, string> = {
  POSITIVE: 'موجب', NEGATIVE: 'سالب', INCONCLUSIVE: 'غير حاسم',
};
export const BIRTH_QUANTITY_EFFECT_LABEL: Record<string, string> = {
  OBSERVATION_ONLY: 'ملاحظة فقط — لا تغيّر العدد',
  GF022_BIRTH: 'مرتبطة بواقعة BIRTH في GF-022 — أثر عددي واحد',
};
export const FEED_CATEGORY_LABEL: Record<string, string> = {
  ROUGHAGE: 'علف خشن', CONCENTRATE: 'مركز', SUPPLEMENT: 'مكمل',
  MINERAL: 'أملاح/معادن', OTHER: 'علف آخر',
};
export const FEED_UNIT_LABEL: Record<string, string> = { KG: 'كجم', LITER: 'لتر' };
export const FCR_STATUS_LABEL: Record<string, string> = {
  AVAILABLE: 'متاح من أدلة مكتملة',
  INSUFFICIENT_WEIGHT_EVENTS: 'غير متاح: يلزم حدثا وزن متتاليان',
  INCOMPARABLE_WEIGHT_BASIS: 'غير متاح: أساسا الوزن غير قابلين للمقارنة كإجمالي دفعة',
  INSUFFICIENT_EVIDENCE: 'غير متاح: دليل الوزن أو العلف غير مكتمل',
  POPULATION_CHANGED: 'غير متاح: تغير عدد الدفعة بين الوزنين',
  NO_FEED_EVIDENCE: 'غير متاح: لا توجد وقائع علف في الفترة',
  INCOMPARABLE_FEED_UNIT: 'غير متاح: تحتوي الفترة على علف بغير الكيلوجرام',
  NO_POSITIVE_WEIGHT_GAIN: 'غير متاح: لا توجد زيادة وزن موجبة',
};
