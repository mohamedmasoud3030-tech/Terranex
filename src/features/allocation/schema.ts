import { z } from 'zod';

const uuid = z.string().uuid();
const idempotencyKey = z.string().trim().min(8, 'مفتاح إعادة المحاولة قصير جدًا').max(120);
const positiveIntegerText = z.string().trim().regex(/^[1-9]\d*$/, 'القيمة يجب أن تكون عددًا صحيحًا موجبًا');

export const configureRulesSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  governingVersionId: uuid,
  policy: z.enum(['PRO_RATA', 'FIXED_SHARES']),
  commonDenominator: positiveIntegerText,
  basisEvidenceReference: z.string().trim().min(3, 'مرجع مستند أساس التخصيص مطلوب').max(200),
  idempotencyKey,
});

export const prepareAllocationSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  closeSnapshotId: uuid,
  governingVersionId: uuid,
  idempotencyKey,
});

export const approveAllocationSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  allocationRunId: uuid,
  postingDate: z.string().date(),
  idempotencyKey,
});

export const prepareDistributionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  allocationRunId: uuid,
  participantPartyId: uuid,
  amount: z.string().trim().min(1, 'مبلغ التوزيع مطلوب'),
  currency: z.string().regex(/^[A-Z]{3}$/),
  evidenceReference: z.string().trim().min(3, 'مرجع الدليل مطلوب').max(200),
  idempotencyKey,
});

export const approveDistributionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  distributionId: uuid,
  postingDate: z.string().date(),
  idempotencyKey,
});

export const payDistributionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  distributionId: uuid,
  cashAccountId: uuid,
  amount: z.string().trim().min(1, 'مبلغ الدفع مطلوب'),
  currency: z.string().regex(/^[A-Z]{3}$/),
  paymentDate: z.string().date(),
  evidenceReference: z.string().trim().min(3, 'مرجع دليل الدفع مطلوب').max(200),
  idempotencyKey,
});

export const participantRuleSchema = z.object({
  partyId: uuid,
  weightNumerator: positiveIntegerText,
});

export type ConfigureRulesInput = z.infer<typeof configureRulesSchema>;
