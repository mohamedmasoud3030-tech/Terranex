import { z } from 'zod';

const uuid = z.string().uuid('معرّف غير صالح');
const idempotencyKey = z.string().trim().min(8).max(120);
const context = { organizationId: uuid, projectId: uuid, idempotencyKey };
const optionalUuid = z.preprocess(
  (value) => typeof value === 'string' && value.trim() === '' ? null : value,
  uuid.nullable().optional(),
);
const optionalText = (max: number) => z.preprocess(
  (value) => typeof value === 'string' && value.trim() === '' ? null : value,
  z.string().trim().max(max).nullable().optional(),
);
const optionalDate = z.preprocess(
  (value) => typeof value === 'string' && value.trim() === '' ? null : value,
  z.string().nullable().optional(),
);
const optionalPositiveInteger = z.preprocess(
  (value) => typeof value === 'string' && value.trim() === '' ? null : value,
  z.string().trim().regex(/^[1-9]\d*$/, 'أدخل عددًا صحيحًا أكبر من صفر').nullable().optional(),
);
const optionalNonNegativeInteger = z.preprocess(
  (value) => typeof value === 'string' && value.trim() === '' ? null : value,
  z.string().trim().regex(/^\d+$/, 'أدخل عددًا صحيحًا لا يقل عن صفر').nullable().optional(),
);
const optionalPositiveDecimal = z.preprocess(
  (value) => typeof value === 'string' && value.trim() === '' ? null : value,
  z.string().trim().regex(/^(?:[1-9]\d{0,14})(?:\.\d{1,3})?$/, 'أدخل كمية موجبة حتى 3 خانات عشرية').nullable().optional(),
);

export const MEDICINE_PRODUCT_KINDS = ['MEDICINE', 'VACCINE'] as const;
export const ANIMAL_IDENTIFIER_TYPES = ['EAR_TAG', 'RFID', 'OTHER'] as const;
export const ANIMAL_SEXES = ['MALE', 'FEMALE', 'UNKNOWN'] as const;
export const HEALTH_EVENT_TYPES = ['OBSERVATION', 'DIAGNOSIS', 'TREATMENT', 'VACCINATION'] as const;
export const CONDITION_CLASSIFICATIONS = [
  'INFECTIOUS', 'PARASITIC', 'INJURY', 'RESPIRATORY',
  'DIGESTIVE', 'REPRODUCTIVE', 'NUTRITIONAL', 'OTHER',
] as const;
export const DOSE_UNITS = ['ML', 'MG', 'G', 'DOSE', 'TABLET'] as const;
export const ADMINISTRATION_ROUTES = ['ORAL', 'INJECTION', 'TOPICAL', 'OTHER'] as const;
export const REPRODUCTION_EVENT_TYPES = ['BREEDING_SERVICE', 'PREGNANCY_CHECK', 'BIRTH_OUTCOME', 'WEANING'] as const;
export const SERVICE_METHODS = ['NATURAL', 'ARTIFICIAL_INSEMINATION', 'OTHER'] as const;
export const PREGNANCY_STATUSES = ['POSITIVE', 'NEGATIVE', 'INCONCLUSIVE'] as const;
export const BIRTH_QUANTITY_EFFECTS = ['OBSERVATION_ONLY', 'GF022_BIRTH'] as const;
export const FEED_CATEGORIES = ['ROUGHAGE', 'CONCENTRATE', 'SUPPLEMENT', 'MINERAL', 'OTHER'] as const;
export const FEED_UNITS = ['KG', 'LITER'] as const;

export const medicineProductSchema = z.object({
  ...context,
  productReference: z.string().trim().min(1, 'مرجع المنتج مطلوب').max(80),
  name: z.string().trim().min(2, 'اسم المنتج مطلوب').max(160),
  productKind: z.enum(MEDICINE_PRODUCT_KINDS),
  activeIngredient: optionalText(200),
  defaultWithdrawalDays: z.string().trim().regex(/^\d{1,4}$/, 'فترة السحب يجب أن تكون عدد أيام من صفر إلى 3650')
    .refine((value) => Number(value) <= 3650, 'فترة السحب يجب ألا تتجاوز 3650 يومًا'),
  notes: optionalText(2000),
});

export const identifyAnimalSchema = z.object({
  ...context,
  cohortId: uuid,
  identifierType: z.enum(ANIMAL_IDENTIFIER_TYPES),
  identifierValue: z.string().trim().min(1, 'المعرّف مطلوب').max(100),
  sex: z.enum(ANIMAL_SEXES),
  birthDate: optionalDate,
  breedDescriptor: optionalText(120),
  identifiedAt: z.string().min(1, 'تاريخ ووقت التعريف مطلوب'),
  evidenceReference: optionalText(200),
  notes: optionalText(2000),
});

export const healthEventSchema = z.object({
  ...context,
  cohortId: uuid,
  animalId: optionalUuid,
  eventType: z.enum(HEALTH_EVENT_TYPES),
  conditionClassification: z.preprocess(
    (value) => value === '' ? null : value,
    z.enum(CONDITION_CLASSIFICATIONS).nullable().optional(),
  ),
  conditionName: optionalText(200),
  medicineProductId: optionalUuid,
  doseQuantity: optionalPositiveDecimal,
  doseUnit: z.preprocess((value) => value === '' ? null : value, z.enum(DOSE_UNITS).nullable().optional()),
  administrationRoute: z.preprocess(
    (value) => value === '' ? null : value,
    z.enum(ADMINISTRATION_ROUTES).nullable().optional(),
  ),
  effectiveAt: z.string().min(1, 'تاريخ ووقت الواقعة مطلوب'),
  practitionerName: z.string().trim().min(2, 'اسم المنفذ/المختص مطلوب').max(160),
  evidenceReference: optionalText(200),
  notes: optionalText(2000),
}).superRefine((data, ctx) => {
  const isAdministration = data.eventType === 'TREATMENT' || data.eventType === 'VACCINATION';
  if (!isAdministration && !data.conditionName) {
    ctx.addIssue({ code: 'custom', path: ['conditionName'], message: 'وصف الحالة مطلوب للملاحظة أو التشخيص' });
  }
  if (data.eventType === 'DIAGNOSIS' && !data.conditionClassification) {
    ctx.addIssue({ code: 'custom', path: ['conditionClassification'], message: 'تصنيف الحالة مطلوب للتشخيص' });
  }
  if (isAdministration && (!data.medicineProductId || !data.doseQuantity || !data.doseUnit || !data.administrationRoute)) {
    ctx.addIssue({ code: 'custom', path: ['medicineProductId'], message: 'العلاج أو التطعيم يتطلب المنتج والجرعة والوحدة وطريق الإعطاء' });
  }
});

export const reproductionEventSchema = z.object({
  ...context,
  cohortId: uuid,
  subjectAnimalId: optionalUuid,
  eventType: z.enum(REPRODUCTION_EVENT_TYPES),
  subjectCount: z.string().trim().regex(/^[1-9]\d*$/, 'عدد الحالات يجب أن يكون أكبر من صفر'),
  serviceMethod: z.preprocess((value) => value === '' ? null : value, z.enum(SERVICE_METHODS).nullable().optional()),
  pregnancyStatus: z.preprocess((value) => value === '' ? null : value, z.enum(PREGNANCY_STATUSES).nullable().optional()),
  expectedBirthDate: optionalDate,
  observedLiveBirthCount: optionalNonNegativeInteger,
  stillbirthCount: optionalNonNegativeInteger,
  birthQuantityEffect: z.preprocess((value) => value === '' ? null : value, z.enum(BIRTH_QUANTITY_EFFECTS).nullable().optional()),
  weanedCount: optionalPositiveInteger,
  damAnimalId: optionalUuid,
  sireAnimalId: optionalUuid,
  effectiveAt: z.string().min(1, 'تاريخ ووقت الواقعة مطلوب'),
  performedByName: z.string().trim().min(2, 'اسم المنفذ مطلوب').max(160),
  evidenceReference: optionalText(200),
  notes: optionalText(2000),
}).superRefine((data, ctx) => {
  if (data.subjectAnimalId && data.subjectCount !== '1') {
    ctx.addIssue({ code: 'custom', path: ['subjectCount'], message: 'عند اختيار حيوان معرّف يكون عدد الحالات واحدًا' });
  }
  if (data.eventType === 'BREEDING_SERVICE' && !data.serviceMethod) {
    ctx.addIssue({ code: 'custom', path: ['serviceMethod'], message: 'طريقة التلقيح/الخدمة مطلوبة' });
  }
  if (data.eventType === 'PREGNANCY_CHECK' && !data.pregnancyStatus) {
    ctx.addIssue({ code: 'custom', path: ['pregnancyStatus'], message: 'نتيجة فحص الحمل مطلوبة' });
  }
  if (data.eventType === 'BIRTH_OUTCOME') {
    if (data.observedLiveBirthCount == null || data.stillbirthCount == null || !data.birthQuantityEffect) {
      ctx.addIssue({ code: 'custom', path: ['observedLiveBirthCount'], message: 'نتيجة الولادة تتطلب أعداد الحي والميت وتحديد أثر العدد' });
    }
    if (data.birthQuantityEffect === 'GF022_BIRTH' && Number(data.observedLiveBirthCount ?? '0') <= 0) {
      ctx.addIssue({ code: 'custom', path: ['birthQuantityEffect'], message: 'ربط GF-022 يتطلب عدد مواليد أحياء أكبر من صفر' });
    }
  }
  if (data.eventType === 'WEANING' && !data.weanedCount) {
    ctx.addIssue({ code: 'custom', path: ['weanedCount'], message: 'عدد المفطوم مطلوب' });
  }
});

export const feedItemSchema = z.object({
  ...context,
  itemReference: z.string().trim().min(1, 'مرجع العلف مطلوب').max(80),
  name: z.string().trim().min(2, 'اسم العلف مطلوب').max(160),
  feedCategory: z.enum(FEED_CATEGORIES),
  issueUnit: z.enum(FEED_UNITS),
  notes: optionalText(2000),
});

export const feedIssueSchema = z.object({
  ...context,
  cohortId: uuid,
  feedItemId: uuid,
  quantity: z.string().trim().regex(/^(?:[1-9]\d{0,14})(?:\.\d{1,3})?$/, 'كمية العلف يجب أن تكون موجبة حتى 3 خانات عشرية'),
  unit: z.enum(FEED_UNITS),
  effectiveAt: z.string().min(1, 'تاريخ ووقت الصرف مطلوب'),
  feedingPeriodStart: optionalDate,
  feedingPeriodEnd: optionalDate,
  issuedByName: z.string().trim().min(2, 'اسم منفذ الصرف مطلوب').max(160),
  evidenceReference: optionalText(200),
  notes: optionalText(2000),
}).superRefine((data, ctx) => {
  if (Boolean(data.feedingPeriodStart) !== Boolean(data.feedingPeriodEnd)) {
    ctx.addIssue({ code: 'custom', path: ['feedingPeriodStart'], message: 'بداية ونهاية فترة التغذية تُدخلان معًا' });
  }
  if (data.feedingPeriodStart && data.feedingPeriodEnd && data.feedingPeriodStart > data.feedingPeriodEnd) {
    ctx.addIssue({ code: 'custom', path: ['feedingPeriodEnd'], message: 'نهاية فترة التغذية تسبق بدايتها' });
  }
});

export type MedicineProductInput = z.infer<typeof medicineProductSchema>;
export type IdentifyAnimalInput = z.infer<typeof identifyAnimalSchema>;
export type HealthEventInput = z.infer<typeof healthEventSchema>;
export type ReproductionEventInput = z.infer<typeof reproductionEventSchema>;
export type FeedItemInput = z.infer<typeof feedItemSchema>;
export type FeedIssueInput = z.infer<typeof feedIssueSchema>;
