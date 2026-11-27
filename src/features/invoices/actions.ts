'use server';

import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { parseMajorUnitsToMinor } from '@/shared/money';
import { createClient } from '@/shared/supabase/server';
import {
  customerInvoiceCollectionSchema,
  customerInvoiceIssueSchema,
  customerPartySchema,
} from './schema';

function fail(error: string): ActionState { return { error }; }
function parse<T>(result: { success: true; data: T } | { success: false; error: { issues: { message: string }[] } }): T | ActionState {
  return result.success ? result.data : fail(result.error.issues[0]?.message ?? 'البيانات غير صحيحة');
}
function isActionState(value: unknown): value is ActionState {
  return typeof value === 'object' && value !== null && 'error' in value;
}
function refresh() {
  revalidatePath('/');
  revalidatePath('/invoices');
}
function domainError(message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('idempotency key payload mismatch')) return fail('مفتاح العملية استُخدم لبيانات مختلفة. حدّث الصفحة وأعد المحاولة.');
  if (text.includes('organization owner required')) return fail('إصدار فواتير العملاء وتحصيلها يتطلب صلاحية مالك المنظمة.');
  if (text.includes('reference already exists')) return fail('رقم الفاتورة مستخدم بالفعل في هذا المشروع.');
  if (text.includes('collection exceeds outstanding receivable')) return fail('مبلغ التحصيل يتجاوز الرصيد المستحق المتبقي على الفاتورة.');
  if (text.includes('cannot collect a reversed customer invoice')) return fail('تم عكس قيد هذه الفاتورة؛ لا يمكن تحصيلها.');
  if (text.includes('cash account must belong')) return fail('حساب التحصيل يجب أن ينتمي إلى نفس المشروع ونفس العملة.');
  if (text.includes('customer party not found')) return fail('العميل المحدد غير موجود في هذه المنظمة.');
  if (text.includes('collection cannot precede')) return fail('تاريخ التحصيل لا يمكن أن يسبق تاريخ الفاتورة.');
  if (text.includes('invoice date must be effective')) return fail('تاريخ الفاتورة لا يمكن أن يكون في المستقبل.');
  if (text.includes('forbidden')) return fail('لا تملك صلاحية تنفيذ هذا الإجراء.');
  return fail(fallback);
}
async function rpc(name: string, args: Record<string, unknown>, fallback: string): Promise<ActionState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc(name, args);
  if (error) return domainError(error.message, fallback);
  refresh();
  return {};
}

export async function issueCustomerInvoice(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(customerInvoiceIssueSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('issue_customer_invoice', {
    p_organization_id: value.organizationId,
    p_project_id: value.projectId,
    p_customer_party_id: value.customerPartyId,
    p_invoice_reference: value.invoiceReference,
    p_description: value.description,
    p_amount_minor_units: parseMajorUnitsToMinor(value.amount, value.currency),
    p_invoice_date: value.invoiceDate,
    p_evidence_reference: value.evidenceReference,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر إصدار الفاتورة.');
}

export async function collectCustomerInvoice(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(customerInvoiceCollectionSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('collect_customer_invoice', {
    p_organization_id: value.organizationId,
    p_invoice_id: value.invoiceId,
    p_cash_account_id: value.cashAccountId,
    p_amount_minor_units: parseMajorUnitsToMinor(value.amount, value.currency),
    p_collection_date: value.collectionDate,
    p_evidence_reference: value.evidenceReference,
    p_idempotency_key: value.idempotencyKey,
  }, 'تعذر ترحيل التحصيل.');
}

export async function createCustomerParty(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(customerPartySchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc('create_party', {
    p_organization_id: value.organizationId,
    p_legal_name: value.legalName,
    p_party_type: value.partyType,
  }, 'تعذر حفظ العميل.');
}
