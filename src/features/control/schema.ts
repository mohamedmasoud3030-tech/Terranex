import { z } from 'zod';
import { isValidMajorMoney, parseSignedMajorUnitsToMinor } from '@/shared/money';

// F3–F10 control layer input contracts. Money travels as major-unit text
// (parsed exactly to minor units in the actions layer); every command
// carries an idempotency key.

const moneyAmount = z
  .string({ error: 'أدخل مبلغًا صحيحًا' })
  .trim()
  .refine((value) => isValidMajorMoney(value, 'EGP'), 'أدخل مبلغًا موجبًا بحد أقصى خانتين عشريتين');

// Retention may legitimately be zero; negative values are rejected.
const nonNegativeMoney = z
  .string({ error: 'أدخل مبلغًا صحيحًا' })
  .trim()
  .refine((value) => {
    try {
      return BigInt(parseSignedMajorUnitsToMinor(value, 'EGP')) >= 0n;
    } catch {
      return false;
    }
  }, 'أدخل مبلغًا غير سالب بحد أقصى خانتين عشريتين');

const idempotencyKey = z.string().trim().min(8, 'مفتاح إعادة المحاولة قصير جدًا').max(120);
const orgId = z.string().uuid();
const projectId = z.string().uuid();
const uuid = z.string().uuid();

// ---- F3 — Contract finance ----

export const milestoneSchema = z.object({
  organizationId: orgId,
  projectId,
  code: z.string().trim().min(2, 'رمز الإنجاز مطلوب').max(40),
  labelAr: z.string().trim().min(2, 'وصف الإنجاز مطلوب').max(200),
  plannedDate: z.string().trim().min(1, 'التاريخ المخطط مطلوب'),
  evidenceReference: z.string().trim().max(500).optional().or(z.literal('')),
  idempotencyKey,
});

export const achieveMilestoneSchema = z.object({
  organizationId: orgId,
  milestoneId: uuid,
  achievedDate: z.string().trim().min(1, 'تاريخ الإنجاز مطلوب'),
  evidenceReference: z.string().trim().max(500).optional().or(z.literal('')),
  idempotencyKey,
});

export const obligationTermsSchema = z.object({
  organizationId: orgId,
  obligationId: uuid,
  termsType: z.enum(['FIXED_DATE', 'NET_DAYS', 'MILESTONE_SCHEDULE']),
  dueDate: z.string().trim().optional().or(z.literal('')),
  netDays: z.string().trim().optional().or(z.literal('')),
  retention: nonNegativeMoney,
  evidenceReference: z.string().trim().max(500).optional().or(z.literal('')),
  notes: z.string().trim().max(1000).optional().or(z.literal('')),
  idempotencyKey,
}).superRefine((data, ctx) => {
  if (data.termsType === 'FIXED_DATE' && !data.dueDate) {
    ctx.addIssue({
      code: 'custom',
      path: ['dueDate'],
      message: 'تاريخ الاستحقاق مطلوب عند اختيار تاريخ ثابت',
    });
  }
  if (data.termsType === 'NET_DAYS') {
    const days = Number(data.netDays);
    if (!data.netDays || !Number.isInteger(days) || days < 1 || days > 730) {
      ctx.addIssue({
        code: 'custom',
        path: ['netDays'],
        message: 'عدد الأيام الصافية يجب أن يكون بين 1 و 730',
      });
    }
  }
});

export const openDisputeSchema = z.object({
  organizationId: orgId,
  obligationId: uuid,
  reason: z.string().trim().min(3, 'سبب النزاع مطلوب (3 أحرف على الأقل)').max(1000),
  idempotencyKey,
});

export const resolveDisputeSchema = z.object({
  organizationId: orgId,
  disputeId: uuid,
  resolutionNote: z.string().trim().min(3, 'ملاحظة التسوية مطلوبة').max(1000),
  idempotencyKey,
});

export const retentionReleaseSchema = z.object({
  organizationId: orgId,
  obligationId: uuid,
  amount: moneyAmount,
  releaseDate: z.string().trim().min(1, 'تاريخ الإفراج مطلوب'),
  reason: z.string().trim().min(3, 'سبب الإفراج مطلوب').max(1000),
  milestoneId: uuid.optional().or(z.literal('')),
  idempotencyKey,
});

// ---- F4 — Budget control ----

const budgetLine = z.object({
  cost_treatment: z.enum(['EXPENSE', 'CAPITALIZABLE_WIP']),
  amount_minor_units: z.string().trim().min(1).regex(/^[1-9][0-9]*$/, 'المبلغ بالوحدات الصغرى'),
  notes: z.string().trim().max(1000).optional().or(z.literal('')),
});

export const budgetCreateSchema = z.object({
  organizationId: orgId,
  projectId,
  periodStart: z.string().trim().min(1, 'بداية الفترة مطلوبة'),
  periodEnd: z.string().trim().min(1, 'نهاية الفترة مطلوبة'),
  budgetType: z.enum(['ORIGINAL', 'REVISED']),
  currency: z.string().regex(/^[A-Z]{3}$/, 'عملة غير صحيحة'),
  description: z.string().trim().min(3, 'وصف الموازنة مطلوب').max(1000),
  evidenceReference: z.string().trim().max(500).optional().or(z.literal('')),
  linesJson: z.string().trim().min(1, 'أدخل بندًا واحدًا على الأقل'),
  idempotencyKey,
});

export function budgetLinesFromInput(raw: string): z.infer<typeof budgetLine>[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return [];
  }
  if (!Array.isArray(parsed)) return [];
  return parsed.filter((line): line is z.infer<typeof budgetLine> =>
    typeof line === 'object' && line !== null && budgetLine.safeParse(line).success);
}

export const budgetApproveSchema = z.object({
  organizationId: orgId,
  budgetId: uuid,
  idempotencyKey,
});

export const budgetSupersedeSchema = z.object({
  organizationId: orgId,
  budgetId: uuid,
  description: z.string().trim().min(3, 'وصف المراجعة مطلوب').max(1000),
  idempotencyKey,
});

export const budgetDeleteDraftSchema = z.object({
  organizationId: orgId,
  budgetId: uuid,
  idempotencyKey,
});

// ---- F5 — Approval & exception engine ----

export const approvalPolicySchema = z.object({
  organizationId: orgId,
  policyDomain: z.enum([
    'OBLIGATION_AUTHORIZATION',
    'PAYMENT_APPROVAL',
    'BUDGET_APPROVAL',
    'BUDGET_EXCEPTION',
    'RETAINAGE_RELEASE',
    'DISPUTE_RESOLUTION',
  ]),
  thresholdMinorUnits: z.string().trim().optional().or(z.literal('')),
  currency: z.string().regex(/^[A-Z]{3}$/, 'عملة غير صحيحة').optional().or(z.literal('')),
  evidenceRequired: z.enum(['true', 'false']),
  active: z.enum(['true', 'false']),
  idempotencyKey,
});

export const openExceptionSchema = z.object({
  organizationId: orgId,
  projectId,
  exceptionDomain: z.enum([
    'BUDGET_CEILING',
    'PAYMENT_BLOCKED',
    'INVOICE_TOLERANCE',
    'CLOSE_GATE',
    'DISPUTE_HOLD',
    'OTHER_DISCLOSED',
  ]),
  subjectType: z.enum([
    'project_budget_line',
    'cost_obligation',
    'cost_payment_proposal',
    'supplier_invoice',
    'close_run',
    'project_milestone',
    'none',
  ]),
  subjectId: uuid.optional().or(z.literal('')),
  amountMinorUnits: z.string().trim().optional().or(z.literal('')),
  currency: z.string().regex(/^[A-Z]{3}$/, 'عملة غير صحيحة').optional().or(z.literal('')),
  reason: z.string().trim().min(3, 'سبب الاستثناء مطلوب').max(1000),
  evidenceReference: z.string().trim().max(500).optional().or(z.literal('')),
  idempotencyKey,
}).superRefine((data, ctx) => {
  if (data.subjectType !== 'none' && !data.subjectId) {
    ctx.addIssue({
      code: 'custom',
      path: ['subjectId'],
      message: 'معرّف الموضوع مطلوب عند اختيار موضوع محدد',
    });
  }
});

export const decideExceptionSchema = z.object({
  organizationId: orgId,
  exceptionId: uuid,
  decision: z.enum(['APPROVED', 'REJECTED', 'VOID']),
  decisionNote: z.string().trim().min(3, 'ملاحظة القرار مطلوبة').max(1000),
  idempotencyKey,
});

export const attachPaymentEvidenceSchema = z.object({
  organizationId: orgId,
  paymentProposalId: uuid,
  evidenceReference: z.string().trim().min(3, 'مرجع المستند مطلوب').max(500),
  idempotencyKey,
});

// ---- F6 — Currency & tax contract ----

export const fxSnapshotSchema = z.object({
  organizationId: orgId,
  baseCurrency: z.string().regex(/^[A-Z]{3}$/, 'عملة الأساس غير صحيحة'),
  quoteCurrency: z.string().regex(/^[A-Z]{3}$/, 'عملة التسعير غير صحيحة'),
  rateNumerator: z.string().trim().regex(/^[1-9][0-9]*$/, 'البسط يجب أن يكون عددًا موجبًا'),
  rateDenominator: z.string().trim().regex(/^[1-9][0-9]*$/, 'المقام يجب أن يكون عددًا موجبًا'),
  rateDate: z.string().trim().min(1, 'تاريخ السعر مطلوب'),
  rateSource: z.enum(['EXTERNAL_PROVIDER_STATEMENT', 'MANUAL_ENTRY']),
  providerReference: z.string().trim().max(200).optional().or(z.literal('')),
  notes: z.string().trim().max(1000).optional().or(z.literal('')),
  idempotencyKey,
}).superRefine((data, ctx) => {
  if (data.baseCurrency === data.quoteCurrency) {
    ctx.addIssue({
      code: 'custom',
      path: ['quoteCurrency'],
      message: 'لقطة السعر تتطلب عملتين مختلفتين',
    });
  }
});

export const fxConversionSchema = z.object({
  organizationId: orgId,
  projectId: uuid.optional().or(z.literal('')),
  sourceAmountMinorUnits: z.string().trim().regex(/^[1-9][0-9]*$/, 'المبلغ بالوحدات الصغرى'),
  sourceCurrency: z.string().regex(/^[A-Z]{3}$/, 'عملة المصدر غير صحيحة'),
  targetCurrency: z.string().regex(/^[A-Z]{3}$/, 'عملة الهدف غير صحيحة'),
  rateSnapshotId: uuid,
  conversionDate: z.string().trim().min(1, 'تاريخ التحويل مطلوب'),
  purpose: z.enum(['REPORTING_ROLLUP', 'DISCLOSURE', 'RECONCILIATION']),
  idempotencyKey,
});

export const orgReportingCurrencySchema = z.object({
  organizationId: orgId,
  reportingCurrency: z.string().regex(/^[A-Z]{3}$/, 'عملة التقارير غير صحيحة').or(z.literal('')),
  idempotencyKey,
});

export const taxTreatmentSchema = z.object({
  organizationId: orgId,
  taxDomain: z.enum(['VALUE_ADDED', 'INCOME', 'WITHHOLDING', 'PROPERTY', 'PAYROLL', 'OTHER_DECLARED']),
  taxName: z.string().trim().min(2, 'اسم الضريبة مطلوب').max(160),
  appliesTo: z.enum([
    'SALES_REVENUE',
    'PROCUREMENT_SPEND',
    'INVESTOR_DISTRIBUTIONS',
    'PROJECT_INCOME',
    'ASSET_TRANSFERS',
  ]),
  treatmentStatus: z.enum([
    'ASSESSED_EXTERNALLY_AND_RECORDED',
    'ASSESSED_EXTERNALLY_NOT_RECORDED',
    'DEFERRED_PENDING_TAX_ADVISORY',
  ]),
  authority: z.string().trim().max(200).optional().or(z.literal('')),
  effectiveFrom: z.string().trim().min(1, 'تاريخ السريان مطلوب'),
  effectiveTo: z.string().trim().optional().or(z.literal('')),
  notes: z.string().trim().min(3, 'ملاحظات المعالجة مطلوبة').max(1000),
  idempotencyKey,
});

export type MilestoneInput = z.infer<typeof milestoneSchema>;
export type ObligationTermsInput = z.infer<typeof obligationTermsSchema>;
export type BudgetCreateInput = z.infer<typeof budgetCreateSchema>;
export type ApprovalPolicyInput = z.infer<typeof approvalPolicySchema>;
export type OpenExceptionInput = z.infer<typeof openExceptionSchema>;
export type FxSnapshotInput = z.infer<typeof fxSnapshotSchema>;
export type TaxTreatmentInput = z.infer<typeof taxTreatmentSchema>;
