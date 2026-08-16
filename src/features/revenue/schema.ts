import { z } from 'zod';
import { isValidMajorMoney } from '@/shared/money';

const uuid = z.string().uuid('معرّف غير صالح');
const idempotencyKey = z.string().trim().min(8).max(120);
const currency = z.string().regex(/^[A-Z]{3}$/, 'رمز العملة غير صالح');
const date = z.string().min(1, 'التاريخ مطلوب');
const moneyText = z.string().trim().min(1, 'المبلغ مطلوب');
const optionalDate = z.preprocess(
  (value) => (value === '' ? null : value),
  z.string().nullable(),
);
const optionalUuid = z.preprocess(
  (value) => (value === '' ? null : value),
  z.string().uuid().nullable(),
);

function validateMoneyForCurrency(
  value: string,
  valueCurrency: string,
  ctx: z.RefinementCtx,
  path: string,
) {
  if (!isValidMajorMoney(value, valueCurrency)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: [path],
      message: 'أدخل مبلغًا موجبًا بدقة الوحدة الفرعية للعملة',
    });
  }
}

export const dispositionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  propertyAssetId: uuid,
  buyerPartyId: uuid,
  agreementReference: z.string().trim().min(2, 'مرجع الاتفاق مطلوب').max(120),
  agreementEvidenceReference: z.string().trim().min(3, 'مرجع دليل الاتفاق مطلوب').max(200),
  agreedProceeds: moneyText,
  currency,
  agreementDate: date,
  expectedControlTransferDate: optionalDate,
  idempotencyKey,
}).superRefine((value, ctx) => {
  validateMoneyForCurrency(value.agreedProceeds, value.currency, ctx, 'agreedProceeds');
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
  amount: moneyText,
  currency,
  collectionDate: date,
  evidenceReference: z.string().trim().min(3, 'مرجع دليل التحصيل مطلوب').max(200),
  idempotencyKey,
}).superRefine((value, ctx) => {
  validateMoneyForCurrency(value.amount, value.currency, ctx, 'amount');
});

export const collectionReconciliationSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  collectionId: uuid,
  statementLineId: uuid,
  idempotencyKey,
});

export const rentalRecognitionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  propertyAssetId: uuid,
  tenantPartyId: uuid,
  contractReference: z.string().trim().min(2, 'مرجع عقد/اتفاق الإيجار مطلوب').max(160),
  rentalPeriodStart: date,
  rentalPeriodEnd: date,
  amount: moneyText,
  currency,
  recognitionDate: date,
  evidenceReference: z.string().trim().min(3, 'مرجع دليل الإيجار مطلوب').max(200),
  idempotencyKey,
}).superRefine((value, ctx) => {
  validateMoneyForCurrency(value.amount, value.currency, ctx, 'amount');
  if (value.rentalPeriodEnd < value.rentalPeriodStart) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['rentalPeriodEnd'], message: 'نهاية فترة الإيجار لا تسبق بدايتها' });
  }
  if (value.recognitionDate < value.rentalPeriodStart) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['recognitionDate'], message: 'تاريخ الاعتراف لا يسبق فترة الإيجار' });
  }
});

export const rentalCollectionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  recognitionId: uuid,
  cashAccountId: uuid,
  amount: moneyText,
  currency,
  collectionDate: date,
  evidenceReference: z.string().trim().min(3, 'مرجع دليل التحصيل مطلوب').max(200),
  idempotencyKey,
}).superRefine((value, ctx) => {
  validateMoneyForCurrency(value.amount, value.currency, ctx, 'amount');
});

export const rentalReconciliationSchema = z.object({
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
