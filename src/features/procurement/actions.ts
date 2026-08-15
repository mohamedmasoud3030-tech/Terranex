'use server';

import { createHash } from 'node:crypto';
import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import { parseMajorUnitsToMinor } from '@/shared/money';
import {
  approvePurchaseOrderSchema,
  approvePurchaseRequestSchema,
  approveSupplierInvoiceSchema,
  approveSupplierPaymentSchema,
  linkSupplierPartySchema,
  purchaseOrderSchema,
  purchaseReceiptSchema,
  purchaseRequestSchema,
  procurementEvidenceSchema,
  submitPurchaseOrderSchema,
  submitPurchaseRequestSchema,
  supplierInvoiceSchema,
  supplierPaymentSchema,
  supplierSchema,
} from './schema';

function fail(prev: ActionState, error: string): ActionState {
  return commandFailureState(prev, error);
}
function refresh(projectId: string) {
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/procurement`);
  revalidatePath(`/projects/${projectId}/costs`);
  revalidatePath(`/projects/${projectId}/cash`);
}

function parse<T>(prev: ActionState, result: { success: true; data: T } | { success: false; error: { issues: { message: string }[] } }): T | ActionState {
  return result.success ? result.data : fail(prev, result.error.issues[0]?.message ?? 'البيانات غير صحيحة');
}
function isActionState(value: unknown): value is ActionState {
  return typeof value === 'object' && value !== null && 'error' in value;
}

function domainError(prev: ActionState, message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('idempotency key payload mismatch')) return fail(prev, 'مفتاح العملية استُخدم لبيانات مختلفة. حدّث الصفحة وأعد المحاولة.');
  if (text.includes('forbidden')) return fail(prev, 'لا تملك صلاحية تنفيذ هذا الإجراء على هذه المنظمة.');
  if (text.includes('authentication required')) return fail(prev, 'انتهت جلسة الدخول. سجّل الدخول ثم أعد المحاولة.');
  if (text.includes('organization owner required') || text.includes('maker/checker')) return fail(prev, 'يتطلب الاعتماد مالك المنظمة وشخصًا مختلفًا عن مُعدّ المستند.');
  if (text.includes('financially linked supplier') || text.includes('supplier financial party')) return fail(prev, 'يجب ربط المورد بطرف مالي معتمد ونشط أولًا.');
  if (text.includes('supplier party not found')) return fail(prev, 'الطرف المالي للمورد غير موجود في هذه المنظمة.');
  if (text.includes('active supplier not found')) return fail(prev, 'المورد المحدد غير موجود أو غير نشط في هذه المنظمة.');
  if (text.includes('source purchase request must belong')) return fail(prev, 'طلب الشراء المصدر يجب أن ينتمي إلى نفس المشروع ويكون معتمدًا.');
  if (text.includes('expected delivery date')) return fail(prev, 'تاريخ التسليم المتوقع لا يمكن أن يكون في الماضي.');
  if (text.includes('currency must match project') || text.includes('currency must match purchase order')) return fail(prev, 'العملة يجب أن تطابق عملة المشروع وأمر الشراء.');
  if (text.includes('commercial evidence reference')) return fail(prev, 'مرجع العرض/العقد التجاري مطلوب.');
  if (text.includes('exact minor units')) return fail(prev, 'الكمية × سعر الوحدة يجب أن تنتج مبلغًا صحيحًا بوحدات العملة الصغرى دون تقريب.');
  if (text.includes('purchase request not found')) return fail(prev, 'طلب الشراء غير موجود في هذه المنظمة.');
  if (text.includes('purchase order not found')) return fail(prev, 'أمر الشراء غير موجود في هذا المشروع.');
  if (text.includes('purchase request is not in draft')) return fail(prev, 'طلب الشراء ليس في حالة مسودة ولا يمكن إرساله.');
  if (text.includes('purchase order is not in draft')) return fail(prev, 'أمر الشراء ليس في حالة مسودة ولا يمكن إرساله.');
  if (text.includes('purchase request is not submitted')) return fail(prev, 'طلب الشراء ليس قيد الاعتماد حاليًا.');
  if (text.includes('purchase order is not submitted')) return fail(prev, 'أمر الشراء ليس قيد الاعتماد حاليًا.');
  if (text.includes('supplier invoice is not submitted')) return fail(prev, 'فاتورة المورد ليست قيد الاعتماد.');
  if (text.includes('supplier invoice reference') || text.includes('supplier_invoices_supplier_reference_key')) return fail(prev, 'رقم فاتورة المورد مستخدم سابقًا لهذا المورد.');
  if (text.includes('supplier invoice unit price')) return fail(prev, 'سعر الفاتورة يجب أن يطابق سعر أمر الشراء تمامًا.');
  if (text.includes('supplier invoice quantity exceeds')) return fail(prev, 'كمية الفاتورة تتجاوز الكمية المستلمة المتاحة للفوترة.');
  if (text.includes('receipt line not found')) return fail(prev, 'سطر الاستلام لا ينتمي إلى أمر الشراء المحدد.');
  if (text.includes('supplier invoice requires an approved')) return fail(prev, 'لا تُسجَّل الفاتورة إلا على أمر شراء معتمد.');
  if (text.includes('payment exceeds remaining payable')) return fail(prev, 'الدفعة تتجاوز المتبقي المستحق للفاتورة.');
  if (text.includes('payment exceeds available cash')) return fail(prev, 'الرصيد المتاح في الحساب النقدي لا يكفي لهذه الدفعة.');
  if (text.includes('cash account must belong') || text.includes('payment currency')) return fail(prev, 'حساب النقدية يجب أن ينتمي إلى نفس المشروع والعملة.');
  if (text.includes('already exists') || text.includes('duplicate key')) return fail(prev, 'يوجد سجل بنفس المرجع في هذا النطاق.');
  if (text.includes('at least one') && text.includes('line')) return fail(prev, 'أضف سطرًا واحدًا على الأقل.');
  if (text.includes('project not found')) return fail(prev, 'المشروع غير موجود في هذه المنظمة.');
  if (text.includes('purchase order approval requires')) return fail(prev, 'لا يمكن اعتماد أمر الشراء قبل إرفاق ملف أمر الشراء أو العقد الثابت.');
  if (text.includes('supplier invoice approval requires an immutable invoice')) return fail(prev, 'لا يمكن اعتماد الفاتورة قبل إرفاق ملف فاتورة المورد الثابت.');
  if (text.includes('every matched receipt')) return fail(prev, 'لا يمكن اعتماد الفاتورة قبل إرفاق دليل فعلي لكل استلام مطابق.');
  if (text.includes('evidence document not found') || text.includes('document identity')) return fail(prev, 'نسخة المستند الجديدة يجب أن تتبع نفس المستند والعنوان والتصنيف داخل المشروع.');
  if (text.includes('evidence storage object not found')) return fail(prev, 'لم يثبت اكتمال رفع الملف الخاص. أعد رفع الملف ثم حاول مجددًا.');
  if (text.includes('does not match storage object') || text.includes('storage object has invalid')) return fail(prev, 'بيانات الملف لا تطابق النسخة المحفوظة في التخزين الخاص.');
  if (text.includes('purchase order must be approved before receiving')) return fail(prev, 'لا يمكن الاستلام إلا على أمر شراء معتمد.');
  if (text.includes('received quantity exceeds ordered quantity')) return fail(prev, 'الكمية المستلمة تتجاوز الكمية المطلوبة لهذا السطر.');
  if (text.includes('order line not found for this order')) return fail(prev, 'سطر أمر الشراء المحدد لا ينتمي إلى هذا الأمر.');
  return fail(prev, fallback);
}

async function rpc(name: string, args: Record<string, unknown>, fallback: string, projectId: string, prev: ActionState): Promise<ActionState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc(name, args);
  if (error) return domainError(prev, error.message, fallback);
  refresh(projectId);
  return commandSuccessState(prev);
}

export async function createSupplier(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, supplierSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('create_supplier', {
    p_organization_id: value.organizationId,
    p_party_id: value.partyId,
    p_name: value.name,
    p_tax_number: value.taxNumber,
    p_payment_terms: value.paymentTerms,
    p_notes: value.notes,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر تسجيل المورد.', String(form.get('projectId') ?? ''), prev);
}

export async function linkSupplierParty(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, linkSupplierPartySchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('link_supplier_party', {
    p_organization_id: value.organizationId,
    p_supplier_id: value.supplierId,
    p_party_id: value.partyId,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر ربط المورد بالطرف المالي.', value.projectId, prev);
}

export async function createPurchaseRequest(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, purchaseRequestSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('create_purchase_request', {
    p_organization_id: value.organizationId,
    p_project_id: value.projectId,
    p_internal_reference: value.internalReference,
    p_description: value.description,
    p_lines: value.linesJson.map((line) => ({
      item_description: line.itemDescription, quantity: line.quantity, unit: line.unit, notes: line.notes ?? undefined,
    })),
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر إنشاء طلب الشراء.', value.projectId, prev);
}

export async function submitPurchaseRequest(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, submitPurchaseRequestSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('submit_purchase_request', {
    p_organization_id: value.organizationId, p_purchase_request_id: value.purchaseRequestId, p_idempotency_key: value.idempotencyKey,
  }, 'تعذر إرسال طلب الشراء للاعتماد.', value.projectId, prev);
}

export async function approvePurchaseRequest(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, approvePurchaseRequestSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('approve_purchase_request', {
    p_organization_id: value.organizationId, p_purchase_request_id: value.purchaseRequestId, p_idempotency_key: value.idempotencyKey,
  }, 'تعذر اعتماد طلب الشراء.', value.projectId, prev);
}

export async function createPurchaseOrder(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, purchaseOrderSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('create_purchase_order', {
    p_organization_id: value.organizationId,
    p_project_id: value.projectId,
    p_internal_reference: value.internalReference,
    p_supplier_id: value.supplierId,
    p_source_purchase_request_id: value.sourcePurchaseRequestId,
    p_description: value.description,
    p_expected_delivery_date: value.expectedDeliveryDate,
    p_currency: value.currency,
    p_commercial_reference: value.commercialReference,
    p_lines: value.linesJson.map((line) => ({
      item_description: line.itemDescription,
      quantity: line.quantity,
      unit: line.unit,
      unit_price_minor_units: parseMajorUnitsToMinor(line.unitPrice, value.currency),
      notes: line.notes ?? undefined,
    })),
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر إنشاء أمر الشراء.', value.projectId, prev);
}

export async function submitPurchaseOrder(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, submitPurchaseOrderSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('submit_purchase_order', {
    p_organization_id: value.organizationId, p_purchase_order_id: value.purchaseOrderId, p_idempotency_key: value.idempotencyKey,
  }, 'تعذر إرسال أمر الشراء للاعتماد.', value.projectId, prev);
}

export async function approvePurchaseOrder(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, approvePurchaseOrderSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('approve_purchase_order', {
    p_organization_id: value.organizationId, p_purchase_order_id: value.purchaseOrderId, p_idempotency_key: value.idempotencyKey,
  }, 'تعذر اعتماد أمر الشراء.', value.projectId, prev);
}

export async function createPurchaseReceipt(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, purchaseReceiptSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('create_purchase_receipt', {
    p_organization_id: value.organizationId,
    p_project_id: value.projectId,
    p_purchase_order_id: value.purchaseOrderId,
    p_evidence_reference: value.evidenceReference,
    p_notes: value.notes,
    p_purchase_order_line_ids: value.linesJson.map((line) => line.purchaseOrderLineId),
    p_quantities: value.linesJson.map((line) => line.quantityReceived),
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر تسجيل الاستلام.', value.projectId, prev);
}

export async function recordSupplierInvoice(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, supplierInvoiceSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('record_supplier_invoice', {
    p_organization_id: value.organizationId,
    p_project_id: value.projectId,
    p_purchase_order_id: value.purchaseOrderId,
    p_invoice_reference: value.invoiceReference,
    p_invoice_date: value.invoiceDate,
    p_currency: value.currency,
    p_cost_treatment: value.costTreatment,
    p_evidence_reference: value.evidenceReference,
    p_notes: value.notes,
    p_lines: value.linesJson.map((line) => ({
      purchase_receipt_line_id: line.purchaseReceiptLineId,
      quantity_invoiced: line.quantityInvoiced,
      unit_price_minor_units: parseMajorUnitsToMinor(line.unitPrice, value.currency),
    })),
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر تسجيل فاتورة المورد.', value.projectId, prev);
}

export async function approveSupplierInvoice(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, approveSupplierInvoiceSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('approve_supplier_invoice', {
    p_organization_id: value.organizationId,
    p_supplier_invoice_id: value.supplierInvoiceId,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر اعتماد فاتورة المورد وإنشاء المستحق.', value.projectId, prev);
}

// Reuses the shared Finance Core proposal/approval workflow; no Procurement cash engine.
export async function prepareSupplierPayment(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, supplierPaymentSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('prepare_cost_payment', {
    p_organization_id: value.organizationId,
    p_obligation_id: value.obligationId,
    p_cash_account_id: value.cashAccountId,
    p_amount_minor_units: parseMajorUnitsToMinor(value.amount, value.currency),
    p_payment_date: value.paymentDate,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر إعداد مقترح دفع المورد.', value.projectId, prev);
}

export async function approveSupplierPayment(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, approveSupplierPaymentSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('approve_cost_payment', {
    p_organization_id: value.organizationId,
    p_payment_proposal_id: value.paymentProposalId,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر اعتماد مقترح الدفع. يلزم مالك مختلف ورصيد كافٍ.', value.projectId, prev);
}

export async function uploadProcurementEvidence(prev: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(prev, procurementEvidenceSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  const file = form.get('file');
  if (!(file instanceof File) || file.size === 0) return fail(prev, 'اختر ملف دليل فعلي.');
  if (file.size > 10 * 1024 * 1024) return fail(prev, 'حجم الملف يجب ألا يتجاوز 10 ميجابايت.');
  if (!['application/pdf', 'image/jpeg', 'image/png'].includes(file.type)) {
    return fail(prev, 'الملفات المدعومة: PDF أو JPEG أو PNG فقط.');
  }

  const bytes = Buffer.from(await file.arrayBuffer());
  const checksum = createHash('sha256').update(bytes).digest('hex');
  // Stable for response-loss retries of the same payload, but changes when a
  // caller incorrectly reuses the command key with a different file.
  const objectDigest = createHash('sha256')
    .update(`${value.organizationId}|${value.projectId}|${value.idempotencyKey}|${checksum}`)
    .digest('hex');
  const objectId = `${objectDigest.slice(0, 8)}-${objectDigest.slice(8, 12)}-4${objectDigest.slice(13, 16)}-a${objectDigest.slice(17, 20)}-${objectDigest.slice(20, 32)}`;
  const objectName = `${value.organizationId}/${value.projectId}/${objectId}`;
  const supabase = await createClient();
  const uploaded = await supabase.storage.from('procurement-evidence').upload(objectName, bytes, {
    contentType: file.type,
    upsert: false,
  });
  const alreadyUploaded = uploaded.error && /exist|duplicate/i.test(uploaded.error.message);
  if (uploaded.error && !alreadyUploaded) return domainError(prev, uploaded.error.message, 'تعذر رفع ملف الدليل الخاص.');

  const { error } = await supabase.rpc('register_procurement_evidence', {
    p_organization_id: value.organizationId,
    p_project_id: value.projectId,
    p_document_id: value.documentId,
    p_classification: value.classification,
    p_title: value.title,
    p_storage_object_name: objectName,
    p_original_filename: file.name,
    p_mime_type: file.type,
    p_size_bytes: file.size,
    p_sha256: checksum,
    p_purchase_order_id: value.purchaseOrderId,
    p_purchase_receipt_id: value.purchaseReceiptId,
    p_supplier_invoice_id: value.supplierInvoiceId,
    p_idempotency_key: value.idempotencyKey,
  });
  if (error) {
    // Registered objects are protected by Storage RLS; only an upload which
    // failed before metadata registration can be removed by this caller.
    if (!alreadyUploaded) await supabase.storage.from('procurement-evidence').remove([objectName]);
    return domainError(prev, error.message, 'تعذر تسجيل وربط ملف الدليل.');
  }
  refresh(value.projectId);
  return commandSuccessState(prev);
}
