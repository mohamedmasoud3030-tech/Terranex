import { z } from 'zod';
import { isValidMajorMoney } from '@/shared/money';

/** Roles an owner may reclassify between by hand. Cash, payables, revenue and capital are not on this list. */
export const ADJUSTMENT_ROLES = ['PROJECT_EXPENSE', 'DEVELOPMENT_WIP', 'PREPAID_ASSET'] as const;
export type AdjustmentRole = (typeof ADJUSTMENT_ROLES)[number];

export const ADJUSTMENT_ROLE_LABEL: Record<AdjustmentRole, string> = {
  PROJECT_EXPENSE: 'مصروفات المشروع',
  DEVELOPMENT_WIP: 'أعمال تحت التطوير',
  PREPAID_ASSET: 'مدفوعات مقدمة',
};

export const adjustmentSchema = z
  .object({
    organizationId: z.string().uuid('معرّف غير صالح'),
    projectId: z.string().uuid('معرّف غير صالح'),
    currency: z.string().regex(/^[A-Z]{3}$/, 'رمز العملة غير صالح'),
    fromRole: z.enum(ADJUSTMENT_ROLES, { message: 'اختر الحساب الدائن' }),
    toRole: z.enum(ADJUSTMENT_ROLES, { message: 'اختر الحساب المدين' }),
    amount: z.string().trim().min(1, 'المبلغ مطلوب'),
    entryDate: z.string().min(1, 'التاريخ مطلوب'),
    memo: z.string().trim().min(5, 'اكتب بيانًا لا يقل عن 5 أحرف').max(500),
    evidenceReference: z.string().trim().min(3, 'مرجع الدليل مطلوب').max(200),
    idempotencyKey: z.string().trim().min(8).max(120),
  })
  .superRefine((v, ctx) => {
    if (v.fromRole === v.toRole) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['toRole'], message: 'اختر حسابين مختلفين' });
    }
    if (!isValidMajorMoney(v.amount, v.currency)) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['amount'], message: 'أدخل مبلغًا موجبًا بدقة الوحدة الفرعية للعملة' });
    }
  });
