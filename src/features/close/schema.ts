import { z } from 'zod';
import { isValidMajorMoney } from '@/shared/money';

const idempotencyKey = z.string().trim().min(8, 'مفتاح إعادة المحاولة قصير جدًا').max(120);

const uuid = z.string().uuid();

export const createAccountingPeriodSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  startDate: z.string().date(),
  endDate: z.string().date(),
  idempotencyKey,
}).superRefine((value, ctx) => {
  if (value.startDate > value.endDate) {
    ctx.addIssue({
      code: 'custom',
      path: ['endDate'],
      message: 'تاريخ نهاية الفترة يجب أن يكون في أو بعد تاريخ البداية.',
    });
  }
});

export const prepareCloseSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  periodId: uuid,
  notes: z.string().trim().max(2000, 'الملاحظات طويلة جدًا').optional().or(z.literal('')),
  idempotencyKey,
});

export const approveCloseSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  closeRunId: uuid,
  idempotencyKey,
});

export const requestExceptionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  closeRunId: uuid,
  gateCode: z.string().trim().min(1, 'رمز البوابة مطلوب'),
  reason: z.string().trim().min(5, 'السبب مطلوب (5 أحرف على الأقل)').max(2000),
  evidenceReference: z.string().trim().min(3, 'الدليل مطلوب (3 أحرف على الأقل)').max(200),
  materialityComment: z.string().trim().max(2000).optional().or(z.literal('')),
  idempotencyKey,
});

export const approveExceptionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  exceptionId: uuid,
  idempotencyKey,
});

export const reopenSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  periodId: uuid,
  reason: z.string().trim().min(5, 'سبب إعادة الفتح مطلوب (5 أحرف على الأقل)').max(2000),
  evidenceReference: z.string().trim().min(3, 'مرجع الدليل مطلوب (3 أحرف على الأقل)').max(200),
  idempotencyKey,
});

export const requestCorrectionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  targetBatchId: uuid,
  sourcePeriodId: uuid,
  correctionPeriodId: uuid,
  reason: z.string().trim().min(5, 'سبب التصحيح مطلوب (5 أحرف على الأقل)').max(2000),
  evidenceReference: z.string().trim().min(3, 'مرجع الدليل مطلوب (3 أحرف على الأقل)').max(200),
  idempotencyKey,
});

export const approveCorrectionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  correctionRequestId: uuid,
  idempotencyKey,
});

export const executeCorrectionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  correctionRequestId: uuid,
  correctionDate: z.string().min(1, 'تاريخ التصحيح مطلوب'),
  idempotencyKey,
});

// Reuse the shared money import so the build keeps the canonical module
// reachable from this slice; close itself does not currently accept money
// fields, but the import is here to keep one shared-money surface.
const _moneyGuard: (v: string) => boolean = (v) => isValidMajorMoney(v, 'EGP');
void _moneyGuard;

export type CreateAccountingPeriodInput = z.infer<typeof createAccountingPeriodSchema>;
export type PrepareCloseInput = z.infer<typeof prepareCloseSchema>;
export type ApproveCloseInput = z.infer<typeof approveCloseSchema>;
export type RequestExceptionInput = z.infer<typeof requestExceptionSchema>;
export type ApproveExceptionInput = z.infer<typeof approveExceptionSchema>;
export type ReopenInput = z.infer<typeof reopenSchema>;
export type RequestCorrectionInput = z.infer<typeof requestCorrectionSchema>;
export type ApproveCorrectionInput = z.infer<typeof approveCorrectionSchema>;
export type ExecuteCorrectionInput = z.infer<typeof executeCorrectionSchema>;
