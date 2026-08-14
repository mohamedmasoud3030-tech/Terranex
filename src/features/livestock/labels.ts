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
