import { z } from 'zod';

const uuid = z.string().uuid('معرّف غير صالح');
const key = z.string().trim().min(8).max(120);
const optional = (max: number) => z.preprocess(v => typeof v === 'string' && v.trim() === '' ? null : v, z.string().trim().max(max).nullable().optional());
const context = { organizationId: uuid, projectId: uuid, idempotencyKey: key };
export const SITE_TYPES = ['FARM','BARN','PASTURE','OTHER'] as const;
export const SPECIES = ['CATTLE','BUFFALO','SHEEP','GOAT'] as const;
export const HERD_PURPOSES = ['MEAT','BREEDING','MIXED'] as const;
export const COHORT_ORIGINS = ['PURCHASED','BORN','CONTRIBUTED_IN_KIND','TRANSFERRED_IN','OPENING_BALANCE'] as const;
export const SEX_COMPOSITIONS = ['MALE','FEMALE','MIXED'] as const;
export const WEIGHT_BASES = ['INDIVIDUAL_MEASURED','COHORT_TOTAL','SAMPLED_AVERAGE','ESTIMATED'] as const;

export const livestockProfileSchema = z.object({ ...context, notes: optional(2000) });
export const livestockSiteSchema = z.object({ ...context, name: z.string().trim().min(2,'اسم موقع التشغيل مطلوب').max(160), internalReference: z.string().trim().min(1,'مرجع الموقع مطلوب').max(80), siteType: z.enum(SITE_TYPES,{message:'نوع موقع التشغيل غير صالح'}), locationDescription: optional(500), notes: optional(2000) });
export const livestockHerdSchema = z.object({ ...context, siteId: uuid, name: z.string().trim().min(2,'اسم القطيع مطلوب').max(160), internalReference: z.string().trim().min(1,'مرجع القطيع مطلوب').max(80), species: z.enum(SPECIES,{message:'نوع الحيوان غير صالح'}), purpose: z.enum(HERD_PURPOSES,{message:'غرض القطيع غير صالح'}), breedDescriptor: optional(120) });
const positiveWeight = z.preprocess(v => typeof v === 'string' && v.trim() === '' ? null : v, z.string().trim().regex(/^(?:[1-9]\d{0,14})(?:\.\d{1,3})?$/,'أدخل وزنًا موجبًا حتى 3 خانات عشرية').nullable().optional());
export const livestockCohortSchema = z.object({ ...context, herdId: uuid, cohortReference: z.string().trim().min(1,'مرجع الدفعة مطلوب').max(100), originType: z.enum(COHORT_ORIGINS,{message:'مصدر الدفعة غير صالح'}), originDate: z.string().min(1,'تاريخ دخول الدفعة مطلوب'), openingHeadcount: z.string().regex(/^[1-9]\d*$/,'العدد عند بداية الدفعة يجب أن يكون عددًا صحيحًا أكبر من صفر'), sexComposition: z.preprocess(v => v === '' ? null : v,z.enum(SEX_COMPOSITIONS).nullable().optional()), breedDescriptor: optional(120), openingWeightValue: positiveWeight, openingWeightUnit: z.preprocess(v=>v===''?null:v,z.literal('KG').nullable().optional()), openingWeightBasis: z.preprocess(v=>v===''?null:v,z.enum(WEIGHT_BASES).nullable().optional()), originEvidenceReference: optional(200), notes: optional(2000) }).superRefine((d,ctx)=>{ const supplied=[d.openingWeightValue,d.openingWeightUnit,d.openingWeightBasis].filter(v=>v!=null).length; if(supplied!==0&&supplied!==3) ctx.addIssue({code:'custom',path:['openingWeightValue'],message:'قيمة الوزن ووحدته وأساسه يجب إدخالها معًا'}); });
export const livestockTransitionSchema = z.object({ ...context, cohortId: uuid, expectedState: z.literal('PLANNED'), newState: z.literal('ACTIVE'), reason: z.string().trim().min(3,'سبب التفعيل مطلوب').max(500), evidenceReference: optional(200) });
