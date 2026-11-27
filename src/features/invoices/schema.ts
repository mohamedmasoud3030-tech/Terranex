import { z } from 'zod';
import { isValidMajorMoney } from '@/shared/money';

const uuid = z.string().uuid('معرّف غير صالح');
const idempotencyKey = z.string().trim().min(8).max(120);
const currency = z.string().regex(/^[A-Z]{3}$/, 'رمز العملة غير صالح');
const date = z.string().min(1, 'التاريخ مطلوب');
const moneyText = z.string().trim().min(1, 'المبلغ مطلوب');

export const customerInvoiceIssueSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  customerPartyId: uuid,
  invoiceReference: z.string().trim().min(1, 'رقم الفاتورة مطلوب').max(120, 'رقم الفاتورة طويل جدًا'),
  description: z.preprocess(
    (value) => (typeof value === 'string' && value.trim() === '' ? null : value),
    z.string().trim().min(2, 'الوصف قصير جدًا').max(1000, 'الوصف طويل جدًا').nullable(),
  ),
  amount: moneyText,
  currency,
  invoiceDate: date,
  evidenceReference: z.string().trim().min(3, 'مرجع الدليل مطلوب').max(200, 'مرجع الدليل طويل جدًا'),
  idempotencyKey,
}).superRefine((value, ctx) => {
  if (!isValidMajorMoney(value.amount, value.currency)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['amount'],
      message: 'أدخل مبلغًا موجبًا بدقة الوحدة الفرعية للعملة',
    });
  }
});

export const customerInvoiceCollectionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  invoiceId: uuid,
  cashAccountId: uuid,
  amount: moneyText,
  currency,
  collectionDate: date,
  evidenceReference: z.string().trim().min(3, 'مرجع الدليل مطلوب').max(200, 'مرجع الدليل طويل جدًا'),
  idempotencyKey,
}).superRefine((value, ctx) => {
  if (!isValidMajorMoney(value.amount, value.currency)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['amount'],
      message: 'أدخل مبلغًا موجبًا بدقة الوحدة الفرعية للعملة',
    });
  }
});

export const customerPartySchema = z.object({
  organizationId: uuid,
  legalName: z.string().trim().min(2, 'اسم العميل مطلوب').max(160, 'اسم العميل طويل جدًا'),
  partyType: z.enum(['PERSON', 'ORGANIZATION']),
});
