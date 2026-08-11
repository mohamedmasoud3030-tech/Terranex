import { z } from 'zod';
import { isValidMajorMoney } from '@/shared/money';

const uuid = z.string().uuid('معرّف غير صالح');
const optionalUuid = z.preprocess((value) => (value === '' ? null : value), z.string().uuid().nullable());
const optionalText = (max: number) => z.preprocess(
  (value) => (typeof value === 'string' && value.trim() === '' ? null : value),
  z.string().trim().max(max).nullable(),
);
const dateOrNull = z.preprocess((value) => (value === '' ? null : value), z.string().nullable());
const idempotencyKey = z.string().trim().min(8).max(120);
const money = z.string().trim().refine((value) => isValidMajorMoney(value, 'EGP'), 'أدخل مبلغًا موجبًا بدقة قرشين');

export const profileSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  strategy: z.enum(['ACQUIRE_HOLD', 'DEVELOP_SELL', 'LAND_TRADE']),
  jurisdiction: optionalText(120),
  idempotencyKey,
});

export const assetSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  name: z.string().trim().min(2, 'اسم الأصل مطلوب').max(160),
  assetReference: optionalText(80),
  idempotencyKey,
});

export const parcelSchema = z.object({
  organizationId: uuid,
  propertyAssetId: uuid,
  identifier: z.string().trim().min(1, 'معرّف القطعة مطلوب').max(100),
  cadastralReference: optionalText(120),
  legalDescription: optionalText(1000),
  areaQuantity: z.string().trim().regex(/^\d{1,14}(?:[.,]\d{1,6})?$/, 'أدخل مساحة موجبة حتى 6 خانات عشرية'),
  areaUnit: z.enum(['M2', 'HECTARE', 'FEDDAN']),
  idempotencyKey,
});

export const acquisitionSchema = z.object({
  organizationId: uuid,
  propertyAssetId: uuid,
  sellerPartyId: uuid,
  contractReference: z.string().trim().min(2, 'مرجع العقد مطلوب').max(120),
  consideration: money,
  closingCosts: z.string().trim().refine((value) => value === '0' || value === '0.00' || isValidMajorMoney(value, 'EGP'), 'تكاليف الإقفال غير صحيحة'),
  currency: z.string().regex(/^[A-Z]{3}$/),
  contractDate: z.string().min(1, 'تاريخ العقد مطلوب'),
  considerationObligationId: optionalUuid,
  evidenceReference: z.string().trim().min(3, 'مرجع دليل العقد مطلوب').max(200),
  idempotencyKey,
});

export const controlSchema = z.object({
  organizationId: uuid,
  propertyAssetId: uuid,
  parcelId: optionalUuid,
  recordType: z.enum(['ACQUISITION_CHECK', 'TITLE', 'POSSESSION', 'PERMIT', 'INSPECTION']),
  controlType: z.string().trim().min(2, 'نوع الفحص مطلوب').max(120),
  status: z.enum(['PENDING', 'PASSED', 'FAILED', 'EXPIRED']),
  effectiveDate: dateOrNull,
  expiryDate: dateOrNull,
  result: optionalText(1000),
  responsibleActorId: uuid,
  evidenceReference: z.string().trim().min(3, 'مرجع الدليل مطلوب').max(200),
  notes: optionalText(1000),
  idempotencyKey,
});

export const transitionSchema = z.object({
  organizationId: uuid,
  subjectId: uuid,
  expectedState: z.string().min(1),
  newState: z.string().min(1),
  reason: z.string().trim().min(3, 'سبب الانتقال مطلوب').max(500),
  evidenceReference: optionalText(200),
  idempotencyKey,
});

export const phaseSchema = z.object({
  organizationId: uuid,
  propertyAssetId: uuid,
  parcelId: optionalUuid,
  name: z.string().trim().min(2, 'اسم المرحلة مطلوب').max(160),
  sequenceNo: z.coerce.number().int().positive(),
  plannedStartDate: dateOrNull,
  plannedEndDate: dateOrNull,
  idempotencyKey,
});

export const milestoneSchema = z.object({
  organizationId: uuid,
  phaseId: uuid,
  name: z.string().trim().min(2, 'اسم العلامة مطلوب').max(160),
  sequenceNo: z.coerce.number().int().positive(),
  plannedDate: dateOrNull,
  idempotencyKey,
});

export const budgetSchema = z.object({
  organizationId: uuid,
  propertyAssetId: uuid,
  currency: z.string().regex(/^[A-Z]{3}$/),
  basisNotes: z.string().trim().min(3, 'أساس الميزانية مطلوب').max(1000),
  parcelId: optionalUuid,
  phaseId: optionalUuid,
  costCategory: z.enum(['ACQUISITION', 'LEGAL_DUE_DILIGENCE', 'SITE_PREPARATION', 'CONSTRUCTION', 'PROFESSIONAL_FEES', 'HOLDING', 'OTHER']),
  amount: money,
  idempotencyKey,
});

export const approvalSchema = z.object({
  organizationId: uuid,
  subjectId: uuid,
  idempotencyKey,
});

export const costClassificationSchema = z.object({
  organizationId: uuid,
  obligationId: uuid,
  propertyAssetId: uuid,
  parcelId: optionalUuid,
  phaseId: optionalUuid,
  costCategory: z.enum(['ACQUISITION', 'LEGAL_DUE_DILIGENCE', 'SITE_PREPARATION', 'CONSTRUCTION', 'PROFESSIONAL_FEES', 'HOLDING', 'OTHER']),
  policyReference: z.string().trim().min(3, 'مرجع قرار المعالجة مطلوب').max(200),
  idempotencyKey,
});

export const valuationSchema = z.object({
  organizationId: uuid,
  propertyAssetId: uuid,
  effectiveDate: z.string().min(1, 'تاريخ التقييم مطلوب'),
  valuerSource: z.string().trim().min(2, 'المقيّم أو المصدر مطلوب').max(160),
  method: z.string().trim().min(2, 'طريقة التقييم مطلوبة').max(120),
  amount: money,
  currency: z.string().regex(/^[A-Z]{3}$/),
  assumptionsNotes: z.string().trim().min(3, 'الافتراضات مطلوبة').max(2000),
  confidence: z.preprocess((value) => (value === '' ? null : value), z.enum(['LOW', 'MEDIUM', 'HIGH']).nullable()),
  evidenceReference: z.string().trim().min(3, 'مرجع دليل التقييم مطلوب').max(200),
  idempotencyKey,
});

export const sectorEventSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  propertyAssetId: optionalUuid,
  parcelId: optionalUuid,
  phaseId: optionalUuid,
  milestoneId: optionalUuid,
  eventType: z.enum(['SITE_VISIT', 'DEVELOPMENT_PROGRESS', 'CONTROL_OBSERVATION', 'MILESTONE_NOTE', 'OTHER']),
  occurredAt: z.string().min(1, 'وقت الحدث مطلوب'),
  quantity: z.preprocess((value) => (typeof value === 'string' && value.trim() === '' ? null : value), z.string().regex(/^\d{1,14}(?:[.,]\d{1,6})?$/).nullable()),
  unit: optionalText(40),
  responsibleActorId: uuid,
  location: optionalText(300),
  notes: z.string().trim().min(3, 'ملاحظات الحدث مطلوبة').max(1000),
  evidenceReference: optionalText(200),
  idempotencyKey,
}).superRefine((data, ctx) => {
  if ((data.quantity === null) !== (data.unit === null)) {
    ctx.addIssue({ code: 'custom', path: ['quantity'], message: 'الكمية والوحدة يجب إدخالهما معًا' });
  }
  if (data.milestoneId && !data.phaseId) {
    ctx.addIssue({ code: 'custom', path: ['milestoneId'], message: 'العلامة تتطلب مرحلتها' });
  }
});
