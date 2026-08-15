import { z } from 'zod';
import { isValidMajorMoney, isValidSignedMoney, parseSignedMajorUnitsToMinor } from '@/shared/money';

const moneyAmount = z
  .string({ error: 'أدخل مبلغًا صحيحًا' })
  .trim()
  .refine((value) => isValidMajorMoney(value, 'EGP'), 'أدخل مبلغًا موجبًا بحد أقصى خانتين عشريتين');

const idempotencyKey = z.string().trim().min(8, 'مفتاح إعادة المحاولة قصير جدًا').max(120);

export const cashAccountSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  name: z.string().trim().min(2, 'اسم الحساب مطلوب').max(120),
  currency: z.string().regex(/^[A-Z]{3}$/, 'عملة غير صحيحة'),
});

export const contributionAttributionSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  contributionId: z.string().uuid(),
  cashAccountId: z.string().uuid(),
  idempotencyKey,
});

export const obligationSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  partyId: z.string().uuid(),
  description: z.string().trim().min(3, 'الوصف مطلوب (3 أحرف على الأقل)').max(500),
  amount: moneyAmount,
  currency: z.string().regex(/^[A-Z]{3}$/, 'عملة غير صحيحة'),
  transactionDate: z.string().min(1, 'تاريخ المعاملة مطلوب'),
  costTreatment: z.enum(['EXPENSE', 'CAPITALIZABLE_WIP']),
  idempotencyKey,
});

export const authorizeObligationSchema = z.object({
  organizationId: z.string().uuid(),
  obligationId: z.string().uuid(),
  idempotencyKey,
});

export const paymentSchema = z.object({
  organizationId: z.string().uuid(),
  obligationId: z.string().uuid(),
  cashAccountId: z.string().uuid(),
  amount: moneyAmount,
  currency: z.string().regex(/^[A-Z]{3}$/, 'عملة غير صحيحة'),
  paymentDate: z.string().min(1, 'تاريخ الدفعة مطلوب'),
  idempotencyKey,
});

export const approvePaymentSchema = z.object({
  organizationId: z.string().uuid(),
  paymentProposalId: z.string().uuid(),
  idempotencyKey,
});

const bankCsvLine = z.object({
  transactionDate: z.string().min(1, 'التاريخ مطلوب في كل سطر'),
  amount: z.string().trim().min(1, 'المبلغ مطلوب في كل سطر'),
  currency: z.string().regex(/^[A-Z]{3}$/, 'عملة غير صحيحة في السطر'),
  description: z.string().trim().min(1, 'الوصف مطلوب في كل سطر').max(500),
  providerReference: z.string().trim().max(80).optional().or(z.literal('')),
});

export const bankImportSchema = z.object({
  organizationId: z.string().uuid(),
  cashAccountId: z.string().uuid(),
  idempotencyKey,
  lines: z.array(bankCsvLine).min(1, 'أدخل سطر كشف حساب واحدًا على الأقل'),
}).superRefine((data, ctx) => {
  const firstCurrency = data.lines[0]?.currency;
  data.lines.forEach((line, index) => {
    if (firstCurrency && line.currency !== firstCurrency) {
      ctx.addIssue({
        code: 'custom',
        path: ['lines', index, 'currency'],
        message: 'كل سطور كشف الحساب يجب أن تكون بنفس العملة؛ لا يتم تحويل العملات ضمن الاستيراد.',
      });
    }

    try {
      if (!isValidSignedMoney(line.amount, line.currency)
          || parseSignedMajorUnitsToMinor(line.amount, line.currency) === '0') {
        ctx.addIssue({
          code: 'custom',
          path: ['lines', index, 'amount'],
          message: 'أدخل مبلغًا صحيحًا غير صفري بعلامة (+/-) في كل سطر',
        });
      }
    } catch {
      ctx.addIssue({
        code: 'custom',
        path: ['lines', index, 'amount'],
        message: 'أدخل مبلغًا صحيحًا غير صفري بعلامة (+/-) في كل سطر',
      });
    }
  });
});

export const reconcileSchema = z.object({
  organizationId: z.string().uuid(),
  paymentId: z.string().uuid(),
  statementLineId: z.string().uuid(),
  idempotencyKey,
});

export const voidReconciliationSchema = z.object({
  organizationId: z.string().uuid(),
  matchId: z.string().uuid(),
  reason: z.string().trim().min(3, 'سبب الإلغاء مطلوب (3 أحرف على الأقل)').max(500),
  idempotencyKey,
});

export const reversalSchema = z.object({
  organizationId: z.string().uuid(),
  batchId: z.string().uuid(),
  reason: z.string().trim().min(3, 'سبب العكس مطلوب (3 أحرف على الأقل)').max(500),
  idempotencyKey,
});

export type CashAccountInput = z.infer<typeof cashAccountSchema>;
export type ContributionAttributionInput = z.infer<typeof contributionAttributionSchema>;
export type ObligationInput = z.infer<typeof obligationSchema>;
export type AuthorizeObligationInput = z.infer<typeof authorizeObligationSchema>;
export type PaymentInput = z.infer<typeof paymentSchema>;
export type ApprovePaymentInput = z.infer<typeof approvePaymentSchema>;
export type BankImportInput = z.infer<typeof bankImportSchema>;
export type ReconcileInput = z.infer<typeof reconcileSchema>;
export type VoidReconciliationInput = z.infer<typeof voidReconciliationSchema>;
export type ReversalInput = z.infer<typeof reversalSchema>;
