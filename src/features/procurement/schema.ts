// GF-025 / R4 — Procurement Foundation: client input contracts.
//
// Mirrors the server commands exactly (migration 20260815031000_gf025_procurement_foundation.sql). These
// schemas cover Suppliers, Purchase Requests and Purchase Orders only —
// quantity/compatible-unit operational truth, no financial amounts in this
// slice. Pricing/commitment, supplier invoicing/payment, and receiving are
// later bounded procurement slices.

import { z } from 'zod';

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

// ---------------------------------------------------------------------------
// Supplier (organization-scoped, shared across projects)
// ---------------------------------------------------------------------------
export const supplierSchema = z.object({
  organizationId: uuid,
  name: z.string().trim().min(2, 'اسم المورد مطلوب').max(160),
  taxNumber: optionalText(40),
  paymentTerms: optionalText(200),
  notes: optionalText(2000),
  idempotencyKey,
});

// ---------------------------------------------------------------------------
// Purchase Request / Order lines
// ---------------------------------------------------------------------------
const lineInputSchema = z.object({
  itemDescription: z.string().trim().min(2, 'وصف الصنف مطلوب').max(160),
  quantity: positiveDecimal,
  unit: z.string().trim().min(1, 'وحدة الكمية مطلوبة').max(20),
  notes: optionalText(1000),
});

const linesJson = z.string().transform((value, ctx) => {
  try {
    return JSON.parse(value) as unknown;
  } catch {
    ctx.addIssue({ code: 'custom', message: 'سطور المستند غير صالحة' });
    return z.NEVER;
  }
}).pipe(z.array(lineInputSchema).min(1, 'أضف سطرًا واحدًا على الأقل').max(50));

// ---------------------------------------------------------------------------
// Purchase Request
// ---------------------------------------------------------------------------
export const purchaseRequestSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  internalReference: z.string().trim().min(1, 'المرجع الداخلي مطلوب').max(80),
  description: optionalText(2000),
  linesJson,
  idempotencyKey,
});

export const submitPurchaseRequestSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  purchaseRequestId: uuid,
  idempotencyKey,
});

export const approvePurchaseRequestSchema = submitPurchaseRequestSchema;

// ---------------------------------------------------------------------------
// Purchase Order
// ---------------------------------------------------------------------------
const optionalUuid = z.preprocess(
  (value) => (typeof value === 'string' && value.trim() === '' ? null : value),
  z.string().uuid('معرّف غير صالح').nullable().optional(),
);

export const purchaseOrderSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  internalReference: z.string().trim().min(1, 'المرجع الداخلي مطلوب').max(80),
  supplierId: optionalUuid,
  sourcePurchaseRequestId: optionalUuid,
  description: optionalText(2000),
  expectedDeliveryDate: optionalDate,
  linesJson,
  idempotencyKey,
}).superRefine((data, ctx) => {
  if (data.expectedDeliveryDate && data.expectedDeliveryDate < new Date().toISOString().slice(0, 10)) {
    ctx.addIssue({
      code: 'custom', path: ['expectedDeliveryDate'],
      message: 'تاريخ التسليم المتوقع يجب ألا يكون في الماضي',
    });
  }
});

export const submitPurchaseOrderSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  purchaseOrderId: uuid,
  idempotencyKey,
});

export const approvePurchaseOrderSchema = submitPurchaseOrderSchema;

// ---------------------------------------------------------------------------
// GF-026 — Purchase Receiving (receipt of goods against an APPROVED PO).
// Quantity-only; unit is derived server-side from the order line.
// ---------------------------------------------------------------------------
const receiptLineInputSchema = z.object({
  purchaseOrderLineId: uuid,
  quantityReceived: positiveDecimal,
});

const receiptLinesJson = z.string().transform((value, ctx) => {
  try {
    return JSON.parse(value) as unknown;
  } catch {
    ctx.addIssue({ code: 'custom', message: 'سطور الاستلام غير صالحة' });
    return z.NEVER;
  }
}).pipe(z.array(receiptLineInputSchema).min(1, 'أضف سطر استلام واحدًا على الأقل').max(50));

export const purchaseReceiptSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  purchaseOrderId: uuid,
  evidenceReference: z.string().trim().min(3, 'مرجع دليل الاستلام مطلوب').max(200),
  notes: optionalText(2000),
  linesJson: receiptLinesJson,
  idempotencyKey,
});

export type PurchaseReceiptInput = z.infer<typeof purchaseReceiptSchema>;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
export type SupplierInput = z.infer<typeof supplierSchema>;
export type PurchaseRequestInput = z.infer<typeof purchaseRequestSchema>;
export type PurchaseOrderInput = z.infer<typeof purchaseOrderSchema>;
export type PurchaseDocumentActionInput = z.infer<typeof submitPurchaseRequestSchema>;
