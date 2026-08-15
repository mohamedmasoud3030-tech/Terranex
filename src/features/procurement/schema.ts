// R4 Procurement contracts. Quantity remains numeric operational truth; every
// monetary value is parsed to integer minor units before crossing the RPC
// boundary and every authoritative total is derived by PostgreSQL.

import { z } from 'zod';
import { isValidMajorMoney } from '@/shared/money';

const uuid = z.string().uuid('معرّف غير صالح');
const optionalText = (max: number) => z.preprocess(
  (value) => {
    if (value === undefined || value === null) return null;
    if (typeof value === 'string' && value.trim() === '') return null;
    return value;
  },
  z.string().trim().max(max).nullable().optional(),
);
const idempotencyKey = z.string().trim().min(8).max(120, 'مفتاح العملية يجب أن يكون بين 8 و 120 حرفًا');
const currency = z.string().regex(/^[A-Z]{3}$/, 'عملة غير صحيحة');
const date = z.string().trim().min(1, 'التاريخ مطلوب');
const moneyText = z.string().trim().min(1, 'سعر الوحدة مطلوب');

const optionalDate = z.preprocess(
  (value) => {
    if (value === undefined || value === null) return null;
    if (typeof value === 'string' && value.trim() === '') return null;
    return value;
  },
  z.string().trim().nullable().optional(),
);

const positiveDecimal = z.string().trim()
  .regex(/^(?:[1-9]\d{0,13}|0)(?:\.\d{1,6})?$/, 'أدخل قيمة رقمية موجبة حتى 6 خانات عشرية')
  .refine((v) => Number(v) > 0, 'أدخل قيمة رقمية موجبة حتى 6 خانات عشرية');

function jsonArray<T extends z.ZodType>(schema: T, emptyMessage: string) {
  return z.string().transform((value, ctx) => {
    try {
      return JSON.parse(value) as unknown;
    } catch {
      ctx.addIssue({ code: 'custom', message: 'سطور المستند غير صالحة' });
      return z.NEVER;
    }
  }).pipe(z.array(schema).min(1, emptyMessage).max(50));
}

// Supplier is an operational profile mapped to the existing authoritative Party.
export const supplierSchema = z.object({
  organizationId: uuid,
  partyId: uuid,
  name: z.string().trim().min(2, 'اسم المورد مطلوب').max(160),
  taxNumber: optionalText(40),
  paymentTerms: optionalText(200),
  notes: optionalText(2000),
  idempotencyKey,
});

export const linkSupplierPartySchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  supplierId: uuid,
  partyId: uuid,
  idempotencyKey,
});

const requestLineInputSchema = z.object({
  itemDescription: z.string().trim().min(2, 'وصف الصنف مطلوب').max(160),
  quantity: positiveDecimal,
  unit: z.string().trim().min(1, 'وحدة الكمية مطلوبة').max(20),
  notes: optionalText(1000),
});
const requestLinesJson = jsonArray(requestLineInputSchema, 'أضف سطرًا واحدًا على الأقل');

export const purchaseRequestSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  internalReference: z.string().trim().min(1, 'المرجع الداخلي مطلوب').max(80),
  description: optionalText(2000),
  linesJson: requestLinesJson,
  idempotencyKey,
});

export const submitPurchaseRequestSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  purchaseRequestId: uuid,
  idempotencyKey,
});
export const approvePurchaseRequestSchema = submitPurchaseRequestSchema;

const optionalUuid = z.preprocess(
  (value) => (typeof value === 'string' && value.trim() === '' ? null : value),
  z.string().uuid('معرّف غير صالح').nullable().optional(),
);
const orderLineInputSchema = requestLineInputSchema.extend({ unitPrice: moneyText });
const orderLinesJson = jsonArray(orderLineInputSchema, 'أضف سطر أمر واحدًا على الأقل');

export const purchaseOrderSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  internalReference: z.string().trim().min(1, 'المرجع الداخلي مطلوب').max(80),
  supplierId: uuid,
  sourcePurchaseRequestId: optionalUuid,
  description: optionalText(2000),
  expectedDeliveryDate: optionalDate,
  currency,
  commercialReference: z.string().trim().min(3, 'مرجع العرض/العقد مطلوب').max(200),
  linesJson: orderLinesJson,
  idempotencyKey,
}).superRefine((data, ctx) => {
  if (data.expectedDeliveryDate && data.expectedDeliveryDate < new Date().toISOString().slice(0, 10)) {
    ctx.addIssue({ code: 'custom', path: ['expectedDeliveryDate'], message: 'تاريخ التسليم المتوقع يجب ألا يكون في الماضي' });
  }
  data.linesJson.forEach((line, index) => {
    if (!isValidMajorMoney(line.unitPrice, data.currency)) {
      ctx.addIssue({ code: 'custom', path: ['linesJson', index, 'unitPrice'], message: 'سعر الوحدة غير صالح لهذه العملة' });
    }
  });
});

export const submitPurchaseOrderSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  purchaseOrderId: uuid,
  idempotencyKey,
});
export const approvePurchaseOrderSchema = submitPurchaseOrderSchema;

// Receiving remains quantity-only; unit is derived from the order line.
const receiptLineInputSchema = z.object({
  purchaseOrderLineId: uuid,
  quantityReceived: positiveDecimal,
});
export const purchaseReceiptSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  purchaseOrderId: uuid,
  evidenceReference: z.string().trim().min(3, 'مرجع دليل الاستلام مطلوب').max(200),
  notes: optionalText(2000),
  linesJson: jsonArray(receiptLineInputSchema, 'أضف سطر استلام واحدًا على الأقل'),
  idempotencyKey,
});

// A supplier invoice line explicitly identifies the receipt quantity it bills.
const invoiceLineInputSchema = z.object({
  purchaseReceiptLineId: uuid,
  quantityInvoiced: positiveDecimal,
  unitPrice: moneyText,
});
export const supplierInvoiceSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  purchaseOrderId: uuid,
  invoiceReference: z.string().trim().min(1, 'رقم فاتورة المورد مطلوب').max(120),
  invoiceDate: date,
  currency,
  costTreatment: z.enum(['EXPENSE', 'CAPITALIZABLE_WIP']),
  evidenceReference: z.string().trim().min(3, 'مرجع دليل الفاتورة مطلوب').max(200),
  notes: optionalText(2000),
  linesJson: jsonArray(invoiceLineInputSchema, 'أضف سطر فاتورة واحدًا على الأقل'),
  idempotencyKey,
}).superRefine((data, ctx) => {
  data.linesJson.forEach((line, index) => {
    if (!isValidMajorMoney(line.unitPrice, data.currency)) {
      ctx.addIssue({ code: 'custom', path: ['linesJson', index, 'unitPrice'], message: 'سعر الفاتورة غير صالح لهذه العملة' });
    }
  });
});

export const approveSupplierInvoiceSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  supplierInvoiceId: uuid,
  idempotencyKey,
});

export const supplierPaymentSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  obligationId: uuid,
  cashAccountId: uuid,
  amount: moneyText,
  currency,
  paymentDate: date,
  idempotencyKey,
}).superRefine((data, ctx) => {
  if (!isValidMajorMoney(data.amount, data.currency)) {
    ctx.addIssue({ code: 'custom', path: ['amount'], message: 'مبلغ الدفعة غير صالح لهذه العملة' });
  }
});

export type PurchaseReceiptInput = z.infer<typeof purchaseReceiptSchema>;
export type SupplierInput = z.infer<typeof supplierSchema>;
export type PurchaseRequestInput = z.infer<typeof purchaseRequestSchema>;
export type PurchaseOrderInput = z.infer<typeof purchaseOrderSchema>;
export type PurchaseDocumentActionInput = z.infer<typeof submitPurchaseRequestSchema>;
export type SupplierInvoiceInput = z.infer<typeof supplierInvoiceSchema>;
