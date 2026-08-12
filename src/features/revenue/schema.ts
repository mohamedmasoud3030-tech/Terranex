import { z } from 'zod';
import { isValidMajorMoney } from '@/shared/money';

const uuid = z.string().uuid('معرّف غير صالح');
const idempotencyKey = z.string().trim().min(8).max(120);
const currency = z.string().regex(/^[A-Z]{3}$/, 'رمز العملة غير صالح');
const date = z.string().min(1, 'التاريخ مطلوب');
const money = z.string().trim().refine(
  (value) => isValidMajorMoney(value, 'EGP'),
  'أدخل مبلغًا موجبًا بدقة الوحدة الفرعية للعملة',
);
const optionalDate = z.preprocess(
  (value) => (value === '' ? null : value),
  z.string().nullable(),
);
const optionalUuid = z.preprocess(
  (value) => (value === '' ? null : value),
  z.string().uuid().nullable(),
);

export const dispositionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  propertyAssetId: uuid,
  buyerPartyId: uuid,
  agreementReference: z.string().trim().min(2, 'مرجع الاتفاق مطلوب').max(120),
  agreementEvidenceReference: z.string().trim().min(3, 'مرجع دليل الاتفاق مطلوب').max(200),
  agreedProceeds: money,
  currency,
  agreementDate: date,
  expectedControlTransferDate: optionalDate,
  idempotencyKey,
});

export const dispositionApprovalSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  dispositionId: uuid,
  idempotencyKey,
});

export const controlTransferSchema = dispositionApprovalSchema.extend({
  controlTransferDate: date,
  evidenceReference: z.string().trim().min(3, 'مرجع دليل انتقال السيطرة مطلوب').max(200),
});

export const saleRecognitionSchema = dispositionApprovalSchema.extend({
  recognitionDate: date,
});

export const saleCollectionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  recognitionId: uuid,
  cashAccountId: uuid,
  amount: money,
  currency,
  collectionDate: date,
  evidenceReference: z.string().trim().min(3, 'مرجع دليل التحصيل مطلوب').max(200),
  idempotencyKey,
});

export const collectionReconciliationSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  collectionId: uuid,
  statementLineId: uuid,
  idempotencyKey,
});

export const sellingCostClassificationSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  obligationId: uuid,
  propertyAssetId: uuid,
  parcelId: optionalUuid,
  phaseId: optionalUuid,
  policyReference: z.string().trim().min(3, 'مرجع معالجة تكلفة البيع مطلوب').max(200),
  idempotencyKey,
});
