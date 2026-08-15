import { z } from 'zod';
import { isValidMajorMoney } from '@/shared/money';

const uuid = z.string().uuid('معرّف غير صالح');
const idempotencyKey = z.string().trim().min(8).max(120);
const context = {
  organizationId: uuid,
  projectId: uuid,
  idempotencyKey,
};

function optionalText(max: number) {
  return z.preprocess(
    (value) => typeof value === 'string' && value.trim() === '' ? null : value,
    z.string().trim().max(max).nullable().optional(),
  );
}

const dateRequired = z.string().min(1, 'التاريخ مطلوب');
const majorMoney = (message: string) =>
  z.string().trim().refine((value) => isValidMajorMoney(value, 'EGP'), message);
const positiveCount = (message: string) =>
  z.string().trim().regex(/^[1-9]\d*$/, message);

export const SITE_TYPES = ['FARM', 'BARN', 'PASTURE', 'OTHER'] as const;
export const SPECIES = ['CATTLE', 'BUFFALO', 'SHEEP', 'GOAT'] as const;
export const HERD_PURPOSES = ['MEAT', 'BREEDING', 'MIXED'] as const;
export const COHORT_ORIGINS = [
  'PURCHASED',
  'BORN',
  'CONTRIBUTED_IN_KIND',
  'TRANSFERRED_IN',
  'OPENING_BALANCE',
] as const;
export const SEX_COMPOSITIONS = ['MALE', 'FEMALE', 'MIXED'] as const;
export const WEIGHT_BASES = [
  'INDIVIDUAL_MEASURED',
  'COHORT_TOTAL',
  'ESTIMATED',
] as const;

export const livestockProfileSchema = z.object({
  ...context,
  notes: optionalText(2000),
});

export const livestockSiteSchema = z.object({
  ...context,
  name: z.string().trim().min(2, 'اسم موقع التشغيل مطلوب').max(160),
  internalReference: z.string().trim().min(1, 'مرجع الموقع مطلوب').max(80),
  siteType: z.enum(SITE_TYPES, { message: 'نوع موقع التشغيل غير صالح' }),
  locationDescription: optionalText(500),
  notes: optionalText(2000),
});

export const livestockHerdSchema = z.object({
  ...context,
  name: z.string().trim().min(2, 'اسم القطيع مطلوب').max(160),
  internalReference: z.string().trim().min(1, 'مرجع القطيع مطلوب').max(80),
  species: z.enum(SPECIES, { message: 'نوع الحيوان غير صالح' }),
  purpose: z.enum(HERD_PURPOSES, { message: 'غرض القطيع غير صالح' }),
  breedDescriptor: optionalText(120),
});

const positiveWeight = z.preprocess(
  (value) => typeof value === 'string' && value.trim() === '' ? null : value,
  z.string()
    .trim()
    .regex(
      /^(?:[1-9]\d{0,14})(?:\.\d{1,3})?$/,
      'أدخل وزنًا موجبًا حتى 3 خانات عشرية',
    )
    .nullable()
    .optional(),
);

export const livestockCohortSchema = z.object({
  ...context,
  herdId: uuid,
  initialSiteId: uuid,
  cohortReference: z.string().trim().min(1, 'مرجع الدفعة مطلوب').max(100),
  originType: z.enum(COHORT_ORIGINS, { message: 'مصدر الدفعة غير صالح' }),
  originDate: z.string().min(1, 'تاريخ دخول الدفعة مطلوب'),
  openingHeadcount: z.string().regex(
    /^[1-9]\d*$/,
    'العدد عند بداية الدفعة يجب أن يكون عددًا صحيحًا أكبر من صفر',
  ),
  sexComposition: z.preprocess(
    (value) => value === '' ? null : value,
    z.enum(SEX_COMPOSITIONS).nullable().optional(),
  ),
  breedDescriptor: optionalText(120),
  openingWeightValue: positiveWeight,
  openingWeightUnit: z.preprocess(
    (value) => value === '' ? null : value,
    z.literal('KG').nullable().optional(),
  ),
  openingWeightBasis: z.preprocess(
    (value) => value === '' ? null : value,
    z.enum(WEIGHT_BASES).nullable().optional(),
  ),
  originEvidenceReference: optionalText(200),
  notes: optionalText(2000),
}).superRefine((data, context) => {
  const weightParts = [
    data.openingWeightValue,
    data.openingWeightUnit,
    data.openingWeightBasis,
  ];
  const suppliedParts = weightParts.filter((value) => value != null).length;
  if (suppliedParts !== 0 && suppliedParts !== weightParts.length) {
    context.addIssue({
      code: 'custom',
      path: ['openingWeightValue'],
      message: 'قيمة الوزن ووحدته وأساسه يجب إدخالها معًا',
    });
  }
});

/**
 * GF-021 weight measurement methods.
 *
 * `SAMPLED_AVERAGE` is available here — unlike the GF-020 opening-weight basis —
 * precisely because a WeightEvent can carry the sample size and evidence that
 * make a sampled figure honest instead of false precision.
 */
export const WEIGHT_METHODS = [
  'INDIVIDUAL_MEASURED',
  'COHORT_TOTAL',
  'SAMPLED_AVERAGE',
  'ESTIMATED',
] as const;

/** Qualitative operational quality only; never a statistical interval. */
export const WEIGHT_CONFIDENCE_LEVELS = ['UNASSESSED', 'LOW', 'MEDIUM', 'HIGH'] as const;

const optionalPositiveInteger = z.preprocess(
  (value) => typeof value === 'string' && value.trim() === '' ? null : value,
  z.string().trim().regex(/^[1-9]\d*$/, 'أدخل عددًا صحيحًا أكبر من صفر')
    .nullable()
    .optional(),
);

export const livestockMovementSchema = z.object({
  ...context,
  cohortId: uuid,
  /**
   * The source placement the operator was looking at. It is NOT trusted as
   * truth: the command re-derives the current placement server-side and
   * rejects the request when the two disagree.
   */
  sourceSiteId: uuid,
  sourceHerdId: uuid,
  destinationSiteId: uuid,
  destinationHerdId: uuid,
  effectiveAt: z.string().min(1, 'تاريخ ووقت النقل مطلوب'),
  reason: z.string().trim().min(3, 'سبب النقل مطلوب').max(500),
  evidenceReference: optionalText(200),
  notes: optionalText(2000),
}).superRefine((data, ctx) => {
  if (
    data.destinationSiteId === data.sourceSiteId &&
    data.destinationHerdId === data.sourceHerdId
  ) {
    ctx.addIssue({
      code: 'custom',
      path: ['destinationSiteId'],
      message: 'يجب أن يتغير الموقع أو القطيع؛ لا تُسجَّل حركة بدون تغيير.',
    });
  }
});

export const livestockWeightEventSchema = z.object({
  ...context,
  cohortId: uuid,
  effectiveAt: z.string().min(1, 'تاريخ ووقت القياس مطلوب'),
  method: z.enum(WEIGHT_METHODS, { message: 'أسلوب قياس الوزن غير صالح' }),
  weightValue: z.string()
    .trim()
    .regex(
      /^(?:[1-9]\d{0,14})(?:\.\d{1,3})?$/,
      'أدخل وزنًا موجبًا حتى 3 خانات عشرية',
    ),
  weightUnit: z.literal('KG'),
  measuredAnimalCount: optionalPositiveInteger,
  sampleSize: optionalPositiveInteger,
  confidenceLevel: z.preprocess(
    (value) => value === '' ? null : value,
    z.enum(WEIGHT_CONFIDENCE_LEVELS).nullable().optional(),
  ),
  evidenceReference: optionalText(200),
  notes: optionalText(2000),
}).superRefine((data, ctx) => {
  if (data.method === 'INDIVIDUAL_MEASURED') {
    if (!data.measuredAnimalCount) {
      ctx.addIssue({
        code: 'custom',
        path: ['measuredAnimalCount'],
        message: 'القياس الفردي يتطلب عدد الحيوانات التي شملها الوزن.',
      });
    }
    if (data.sampleSize) {
      ctx.addIssue({
        code: 'custom',
        path: ['sampleSize'],
        message: 'القياس الفردي لا يقبل حجم عينة.',
      });
    }
    return;
  }
  if (data.method === 'SAMPLED_AVERAGE') {
    if (!data.sampleSize) {
      ctx.addIssue({
        code: 'custom',
        path: ['sampleSize'],
        message: 'الوزن بالعينة يتطلب حجم العينة حتى لا يُقرأ كدقة زائفة.',
      });
    }
    if (data.measuredAnimalCount) {
      ctx.addIssue({
        code: 'custom',
        path: ['measuredAnimalCount'],
        message: 'الوزن بالعينة لا يقبل عدد حيوانات مقاسة.',
      });
    }
    if (!data.evidenceReference) {
      ctx.addIssue({
        code: 'custom',
        path: ['evidenceReference'],
        message: 'الوزن بالعينة يتطلب مرجع دليل.',
      });
    }
    return;
  }
  if (data.measuredAnimalCount || data.sampleSize) {
    ctx.addIssue({
      code: 'custom',
      path: ['sampleSize'],
      message: 'هذا الأسلوب لا يقبل بيانات عينة أو عدد حيوانات مقاسة.',
    });
  }
});


/** GF-022 mortality cause categories. */
export const MORTALITY_CAUSES = [
  'DISEASE',
  'INJURY',
  'PREDATION',
  'WEATHER',
  'BIRTH_COMPLICATION',
  'UNKNOWN',
  'OTHER',
] as const;

/** Constrained disposal state; PENDING is explicit, not an omitted field. */
export const DISPOSAL_METHODS = [
  'BURIAL',
  'INCINERATION',
  'RENDERING',
  'COMPOSTING',
  'OTHER',
  'PENDING',
] as const;

export const livestockBirthSchema = z.object({
  ...context,
  cohortId: uuid,
  quantity: positiveCount('عدد الولادات يجب أن يكون عددًا صحيحًا أكبر من صفر'),
  effectiveAt: z.string().min(1, 'تاريخ ووقت الواقعة مطلوب'),
  evidenceReference: optionalText(200),
  notes: optionalText(2000),
});

export const livestockMortalitySchema = z.object({
  ...context,
  cohortId: uuid,
  quantity: positiveCount('عدد النفوق يجب أن يكون عددًا صحيحًا أكبر من صفر'),
  effectiveAt: z.string().min(1, 'تاريخ ووقت الواقعة مطلوب'),
  causeCategory: z.enum(MORTALITY_CAUSES, { message: 'سبب النفوق غير صالح' }),
  causeDetail: optionalText(500),
  disposalMethod: z.preprocess(
    (value) => value === '' ? null : value,
    z.enum(DISPOSAL_METHODS).nullable().optional(),
  ),
  evidenceReference: optionalText(200),
  notes: optionalText(2000),
});

export const livestockSplitSchema = z.object({
  ...context,
  sourceCohortId: uuid,
  quantity: positiveCount('العدد المُقسَّم يجب أن يكون عددًا صحيحًا أكبر من صفر'),
  effectiveAt: z.string().min(1, 'تاريخ ووقت العملية مطلوب'),
  destinationCohortReference: z.string().trim().min(1, 'مرجع الدفعة الناتجة مطلوب').max(100),
  destinationHerdId: uuid,
  destinationSiteId: uuid,
  destinationSexComposition: z.preprocess(
    (value) => value === '' ? null : value,
    z.enum(SEX_COMPOSITIONS).nullable().optional(),
  ),
  destinationBreedDescriptor: optionalText(120),
  reason: z.string().trim().min(3, 'سبب التقسيم مطلوب').max(500),
  evidenceReference: optionalText(200),
  notes: optionalText(2000),
});

/**
 * GF-022 merge.
 *
 * At least two DISTINCT source Cohorts, each with its own consumed quantity.
 * The quantities are positional: entry `i` is drawn from source `i`.
 */
export const livestockMergeSchema = z.object({
  ...context,
  sourceCohortIds: z.array(uuid).min(2, 'اختر دفعتين على الأقل للدمج'),
  quantities: z.array(positiveCount('كل عدد مدموج يجب أن يكون أكبر من صفر')).min(2),
  effectiveAt: z.string().min(1, 'تاريخ ووقت العملية مطلوب'),
  destinationCohortReference: z.string().trim().min(1, 'مرجع الدفعة الناتجة مطلوب').max(100),
  destinationHerdId: uuid,
  destinationSiteId: uuid,
  destinationSexComposition: z.preprocess(
    (value) => value === '' ? null : value,
    z.enum(SEX_COMPOSITIONS).nullable().optional(),
  ),
  destinationBreedDescriptor: optionalText(120),
  reason: z.string().trim().min(3, 'سبب الدمج مطلوب').max(500),
  evidenceReference: optionalText(200),
  notes: optionalText(2000),
}).superRefine((data, ctx) => {
  if (data.sourceCohortIds.length !== data.quantities.length) {
    ctx.addIssue({
      code: 'custom',
      path: ['quantities'],
      message: 'عدد الكميات يجب أن يطابق عدد الدفعات المصدر.',
    });
  }
  if (new Set(data.sourceCohortIds).size !== data.sourceCohortIds.length) {
    ctx.addIssue({
      code: 'custom',
      path: ['sourceCohortIds'],
      message: 'لا يمكن دمج الدفعة مع نفسها؛ اختر دفعات مختلفة.',
    });
  }
});

export const livestockTransitionSchema = z.object({
  ...context,
  cohortId: uuid,
  expectedState: z.literal('PLANNED'),
  newState: z.literal('ACTIVE'),
  reason: z.string().trim().min(3, 'سبب التفعيل مطلوب').max(500),
  evidenceReference: optionalText(200),
});

export type LivestockProfileInput = z.infer<typeof livestockProfileSchema>;
export type LivestockSiteInput = z.infer<typeof livestockSiteSchema>;
export type LivestockHerdInput = z.infer<typeof livestockHerdSchema>;
export type LivestockCohortInput = z.infer<typeof livestockCohortSchema>;
export type LivestockTransitionInput = z.infer<typeof livestockTransitionSchema>;
export type LivestockMovementInput = z.infer<typeof livestockMovementSchema>;
export type LivestockWeightEventInput = z.infer<typeof livestockWeightEventSchema>;
export type LivestockBirthInput = z.infer<typeof livestockBirthSchema>;
export type LivestockMortalityInput = z.infer<typeof livestockMortalitySchema>;
export type LivestockSplitInput = z.infer<typeof livestockSplitSchema>;
export type LivestockMergeInput = z.infer<typeof livestockMergeSchema>;

// ---------------------------------------------------------------------------
// GF-024 — Livestock commercial, profitability & closeout.
//
// Physical quantity is exact integer headcount; money is parsed to minor
// units only at the RPC boundary. No schema accepts an editable profit,
// COGS, inventory value, or fair-value figure.
// ---------------------------------------------------------------------------

/** Finance-oriented cost categories on a Cohort attribution (labels only). */
export const LIVESTOCK_COST_CATEGORIES = [
  'ACQUISITION',
  'FEED',
  'HEALTH',
  'LABOR',
  'FACILITIES',
  'TRANSPORT',
  'OTHER',
] as const;

const purchaseLineInputSchema = z.object({
  cohortId: uuid,
  quantity: positiveCount('عدد الشراء يجب أن يكون عددًا صحيحًا أكبر من صفر'),
  /** Optional commercial agreement snapshot, never a posting. */
  agreedUnitPrice: z.preprocess(
    (value) => typeof value === 'string' && value.trim() === '' ? null : value,
    majorMoney('سعر الاتفاق يجب أن يكون موجبًا بدقة العملة').nullable().optional(),
  ),
});

const purchaseLinesJson = z.string().transform((value, ctx) => {
  try {
    return JSON.parse(value) as unknown;
  } catch {
    ctx.addIssue({ code: 'custom', message: 'سطور الشراء غير صالحة' });
    return z.NEVER;
  }
}).pipe(z.array(purchaseLineInputSchema).min(1, 'أضف سطر شراء واحدًا على الأقل').max(50));

export const livestockPurchaseSchema = z.object({
  ...context,
  supplierPartyId: uuid,
  purchaseReference: z.string().trim().min(1, 'مرجع الشراء مطلوب').max(120),
  agreementReference: optionalText(200),
  effectiveAt: z.string().min(1, 'تاريخ ووقت الاستلام مطلوب'),
  evidenceReference: optionalText(200),
  notes: optionalText(2000),
  linesJson: purchaseLinesJson,
});

const saleLineInputSchema = z.object({
  cohortId: uuid,
  quantity: positiveCount('عدد البيع يجب أن يكون عددًا صحيحًا أكبر من صفر'),
  unitPrice: majorMoney('سعر الوحدة يجب أن يكون موجبًا بدقة العملة'),
});

const saleLinesJson = z.string().transform((value, ctx) => {
  try {
    return JSON.parse(value) as unknown;
  } catch {
    ctx.addIssue({ code: 'custom', message: 'سطور البيع غير صالحة' });
    return z.NEVER;
  }
}).pipe(z.array(saleLineInputSchema).min(1, 'أضف سطر بيع واحدًا على الأقل').max(50));

export const livestockSaleSchema = z.object({
  ...context,
  buyerPartyId: uuid,
  saleReference: z.string().trim().min(1, 'مرجع البيع مطلوب').max(120),
  agreementReference: optionalText(200),
  saleDate: dateRequired,
  currency: z.string().regex(/^[A-Z]{3}$/),
  terms: optionalText(1000),
  evidenceReference: optionalText(200),
  linesJson: saleLinesJson,
});

export const livestockSaleApprovalSchema = z.object({
  ...context,
  saleId: uuid,
});

export const livestockSaleRecognitionSchema = livestockSaleApprovalSchema.extend({
  controlTransferDate: dateRequired,
  evidenceReference: z.string().trim().min(3, 'مرجع دليل التسليم مطلوب').max(200),
});

export const livestockSaleCollectionSchema = z.object({
  ...context,
  recognitionId: uuid,
  cashAccountId: uuid,
  amount: majorMoney('أدخل مبلغ تحصيل موجبًا بدقة العملة'),
  currency: z.string().regex(/^[A-Z]{3}$/),
  collectionDate: dateRequired,
  evidenceReference: z.string().trim().min(3, 'مرجع دليل التحصيل مطلوب').max(200),
});

export const livestockCostAttributionSchema = z.object({
  ...context,
  cohortId: uuid,
  sourceJournalLineId: uuid,
  amount: majorMoney('أدخل مبلغ التحمل موجبًا بدقة العملة'),
  currency: z.string().regex(/^[A-Z]{3}$/),
  costCategory: z.enum(LIVESTOCK_COST_CATEGORIES, { message: 'تصنيف التكلفة غير صالح' }),
  policyReference: z.string().trim().min(3, 'مرجع سياسة التحمل مطلوب').max(200),
  evidenceReference: z.string().trim().min(3, 'مرجع دليل التحمل مطلوب').max(200),
});

export const livestockCostAttributionReversalSchema = z.object({
  ...context,
  attributionId: uuid,
  reason: z.string().trim().min(3, 'سبب العكس مطلوب').max(500),
  evidenceReference: z.string().trim().min(3, 'مرجع دليل العكس مطلوب').max(200),
});

export const livestockCloseoutSchema = z.object({
  ...context,
  cohortId: uuid,
  closeReason: z.string().trim().min(3, 'سبب الإقفال مطلوب').max(500),
  evidenceReference: z.string().trim().min(3, 'مرجع دليل الإقفال مطلوب').max(200),
});

export type LivestockPurchaseInput = z.infer<typeof livestockPurchaseSchema>;
export type LivestockSaleInput = z.infer<typeof livestockSaleSchema>;
export type LivestockSaleApprovalInput = z.infer<typeof livestockSaleApprovalSchema>;
export type LivestockSaleRecognitionInput = z.infer<typeof livestockSaleRecognitionSchema>;
export type LivestockSaleCollectionInput = z.infer<typeof livestockSaleCollectionSchema>;
export type LivestockCostAttributionInput = z.infer<typeof livestockCostAttributionSchema>;
export type LivestockCostAttributionReversalInput = z.infer<typeof livestockCostAttributionReversalSchema>;
export type LivestockCloseoutInput = z.infer<typeof livestockCloseoutSchema>;
