'use server';

import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';
import {
  approvePurchaseOrderSchema,
  approvePurchaseRequestSchema,
  purchaseOrderSchema,
  purchaseReceiptSchema,
  purchaseRequestSchema,
  submitPurchaseOrderSchema,
  submitPurchaseRequestSchema,
  supplierSchema,
} from './schema';

function fail(error: string): ActionState { return { error }; }
function refresh(projectId: string) {
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/procurement`);
}

function parse<T>(result: { success: true; data: T } | { success: false; error: { issues: { message: string }[] } }): T | ActionState {
  return result.success ? result.data : fail(result.error.issues[0]?.message ?? 'البيانات غير صحيحة');
}
function isActionState(value: unknown): value is ActionState {
  return typeof value === 'object' && value !== null && 'error' in value;
}

function domainError(message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('idempotency key payload mismatch')) return fail('مفتاح العملية استُخدم لبيانات مختلفة. حدّث الصفحة وأعد المحاولة.');
  if (text.includes('forbidden')) return fail('لا تملك صلاحية تنفيذ هذا الإجراء على هذه المنظمة.');
  if (text.includes('authentication required')) return fail('انتهت جلسة الدخول. سجّل الدخول ثم أعد المحاولة.');
  if (text.includes('organization owner required') || text.includes('maker/checker')) return fail('اعتماد هذا المستند يتطلب مالك المنظمة، ويجب ألا يكون هو نفس طالب المستند.');
  if (text.includes('active supplier not found')) return fail('المورد المحدد غير موجود أو غير نشط في هذه المنظمة.');
  if (text.includes('source purchase request not found')) return fail('طلب الشراء المصدر غير موجود في هذه المنظمة.');
  if (text.includes('purchase request not found')) return fail('طلب الشراء غير موجود في هذه المنظمة.');
  if (text.includes('purchase order not found')) return fail('أمر الشراء غير موجود في هذه المنظمة.');
  if (text.includes('purchase request is not in draft')) return fail('طلب الشراء ليس في حالة مسودة ولا يمكن إرساله.');
  if (text.includes('purchase order is not in draft')) return fail('أمر الشراء ليس في حالة مسودة ولا يمكن إرساله.');
  if (text.includes('purchase request is not submitted')) return fail('طلب الشراء ليس قيد الاعتماد حاليًا.');
  if (text.includes('purchase order is not submitted')) return fail('أمر الشراء ليس قيد الاعتماد حاليًا.');
  if (text.includes('already exists')) return fail('يوجد سجل بنفس المرجع/الاسم في هذا النطاق.');
  if (text.includes('invalid idempotency key')) return fail('مفتاح العملية غير صالح.');
  if (text.includes('invalid supplier name')) return fail('اسم المورد مطلوب (حرفان على الأقل).');
  if (text.includes('at least one') && text.includes('line')) return fail('أضف سطرًا واحدًا على الأقل.');
  if (text.includes('project not found')) return fail('المشروع غير موجود في هذه المنظمة.');
  if (text.includes('purchase order must be approved before receiving')) return fail('لا يمكن الاستلام إلا على أمر شراء معتمد.');
  if (text.includes('received quantity exceeds ordered quantity')) return fail('الكمية المستلمة تتجاوز الكمية المطلوبة لهذا السطر.');
  if (text.includes('receipt line unit must match order line unit')) return fail('وحدة الاستلام يجب أن تطابق وحدة سطر الأمر.');
  if (text.includes('invalid evidence reference')) return fail('مرجع دليل الاستلام مطلوب (3 أحرف على الأقل).');
  if (text.includes('order line not found for this order')) return fail('سطر أمر الشراء المحدد لا ينتمي إلى هذا الأمر.');
  if (text.includes('invalid receipt line quantity')) return fail('كمية الاستلام يجب أن تكون موجبة.');
  return fail(fallback);
}

async function rpc(name: string, args: Record<string, unknown>, fallback: string, projectId: string): Promise<ActionState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc(name, args);
  if (error) return domainError(error.message, fallback);
  refresh(projectId);
  return {};
}

export async function createSupplier(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(supplierSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  // Suppliers are organization-scoped and shared across projects; a projectId is
  // carried only so the opened project's procurement page can be refreshed.
  const projectId = String(form.get('projectId') ?? '');
  return rpc('create_supplier', {
    p_organization_id: value.organizationId,
    p_name: value.name,
    p_tax_number: value.taxNumber,
    p_payment_terms: value.paymentTerms,
    p_notes: value.notes,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر تسجيل المورد.', projectId);
}

export async function createPurchaseRequest(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(purchaseRequestSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('create_purchase_request', {
    p_organization_id: value.organizationId,
    p_project_id: value.projectId,
    p_internal_reference: value.internalReference,
    p_description: value.description,
    p_lines: value.linesJson.map((line) => ({
      item_description: line.itemDescription,
      quantity: line.quantity.replace(',', '.'),
      unit: line.unit,
      notes: line.notes ?? undefined,
    })),
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر إنشاء طلب الشراء.', value.projectId);
}

export async function submitPurchaseRequest(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(submitPurchaseRequestSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('submit_purchase_request', {
    p_organization_id: value.organizationId,
    p_purchase_request_id: value.purchaseRequestId,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر إرسال طلب الشراء للاعتماد.', value.projectId);
}

export async function approvePurchaseRequest(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(approvePurchaseRequestSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('approve_purchase_request', {
    p_organization_id: value.organizationId,
    p_purchase_request_id: value.purchaseRequestId,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر اعتماد طلب الشراء.', value.projectId);
}

export async function createPurchaseOrder(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(purchaseOrderSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('create_purchase_order', {
    p_organization_id: value.organizationId,
    p_project_id: value.projectId,
    p_internal_reference: value.internalReference,
    p_supplier_id: value.supplierId,
    p_source_purchase_request_id: value.sourcePurchaseRequestId,
    p_description: value.description,
    p_expected_delivery_date: value.expectedDeliveryDate,
    p_lines: value.linesJson.map((line) => ({
      item_description: line.itemDescription,
      quantity: line.quantity.replace(',', '.'),
      unit: line.unit,
      notes: line.notes ?? undefined,
    })),
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر إنشاء أمر الشراء.', value.projectId);
}

export async function submitPurchaseOrder(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(submitPurchaseOrderSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('submit_purchase_order', {
    p_organization_id: value.organizationId,
    p_purchase_order_id: value.purchaseOrderId,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر إرسال أمر الشراء للاعتماد.', value.projectId);
}

export async function approvePurchaseOrder(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(approvePurchaseOrderSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('approve_purchase_order', {
    p_organization_id: value.organizationId,
    p_purchase_order_id: value.purchaseOrderId,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر اعتماد أمر الشراء.', value.projectId);
}

export async function createPurchaseReceipt(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(purchaseReceiptSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('create_purchase_receipt', {
    p_organization_id: value.organizationId,
    p_project_id: value.projectId,
    p_purchase_order_id: value.purchaseOrderId,
    p_evidence_reference: value.evidenceReference,
    p_notes: value.notes,
    p_lines: value.linesJson.map((line) => ({
      purchase_order_line_id: line.purchaseOrderLineId,
      quantity_received: line.quantityReceived.replace(',', '.'),
    })),
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر تسجيل الاستلام.', value.projectId);
}
