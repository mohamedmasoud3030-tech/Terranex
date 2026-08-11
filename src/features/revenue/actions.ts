'use server';

import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { parseMajorUnitsToMinor } from '@/shared/money';
import { createClient } from '@/shared/supabase/server';
import {
  collectionReconciliationSchema,
  controlTransferSchema,
  dispositionApprovalSchema,
  dispositionSchema,
  saleCollectionSchema,
  saleRecognitionSchema,
  sellingCostClassificationSchema,
} from './schema';

function fail(error: string): ActionState { return { error }; }
function parse<T>(result: { success: true; data: T } | { success: false; error: { issues: { message: string }[] } }): T | ActionState {
  return result.success ? result.data : fail(result.error.issues[0]?.message ?? 'البيانات غير صحيحة');
}
function isActionState(value: unknown): value is ActionState {
  return typeof value === 'object' && value !== null && 'error' in value;
}
function refresh(projectId: string) {
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/operations`);
  revalidatePath(`/projects/${projectId}/cash`);
  revalidatePath(`/projects/${projectId}/costs`);
}
function domainError(message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('idempotency key payload mismatch')) return fail('مفتاح العملية استُخدم لبيانات مختلفة. حدّث الصفحة وأعد المحاولة.');
  if (text.includes('organization owner required')) return fail('هذا الإجراء المالي المادي يتطلب صلاحية مالك المنظمة.');
  if (text.includes('already exists') || text.includes('already recognized')) return fail('يوجد تصرف أو اعتراف بيع قائم لهذا الأصل؛ لا يمكن بيع الأصل مرتين.');
  if (text.includes('authoritative posted carrying cost')) return fail('لا يمكن اشتقاق تكلفة دفترية موثوقة من تكاليف WIP المرحلة والمسنَدة للأصل. لن يستخدم النظام تقديرًا بديلًا.');
  if (text.includes('exceeds outstanding receivable')) return fail('مبلغ التحصيل يتجاوز الرصيد المستحق المتبقي.');
  if (text.includes('requires the property to be explicitly EXITING')) return fail('غيّر حالة الأصل إلى «قيد التخارج» بشكل مستقل أولًا.');
  if (text.includes('remain EXITING')) return fail('يجب أن يبقى الأصل «قيد التخارج» حتى اكتمال الاعتراف.');
  if (text.includes('title and possession')) return fail('يلزم سند وحيازة ناجحان وساريان لإثبات انتقال السيطرة.');
  if (text.includes('same project') || text.includes('must belong') || text.includes('does not belong')) return fail('المرجع المحدد لا ينتمي إلى نفس المنظمة والمشروع والأصل.');
  if (text.includes('positive statement amount')) return fail('يجب أن يكون سطر البنك إيداعًا موجبًا مطابقًا للتحصيل تمامًا.');
  if (text.includes('duplicate key') || text.includes('bank_statement_reconciliation_allocations')) return fail('سطر البنك مطابق بالفعل لدفعة أو تحصيل آخر.');
  if (text.includes('forbidden')) return fail('لا تملك صلاحية تنفيذ هذا الإجراء.');
  return fail(fallback);
}
async function rpc(name: string, args: Record<string, unknown>, fallback: string, projectId: string): Promise<ActionState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc(name, args);
  if (error) return domainError(error.message, fallback);
  refresh(projectId);
  return {};
}

export async function createDisposition(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(dispositionSchema.safeParse(Object.fromEntries(form))); if (isActionState(value)) return value;
  return rpc('create_property_disposition', {
    p_organization_id:value.organizationId,p_project_id:value.projectId,
    p_property_asset_id:value.propertyAssetId,p_buyer_party_id:value.buyerPartyId,
    p_agreement_reference:value.agreementReference,
    p_agreement_evidence_reference:value.agreementEvidenceReference,
    p_agreed_proceeds_minor_units:parseMajorUnitsToMinor(value.agreedProceeds,value.currency),
    p_currency:value.currency,p_agreement_date:value.agreementDate,
    p_expected_control_transfer_date:value.expectedControlTransferDate,
    p_idempotency_key:value.idempotencyKey,
  }, 'تعذر حفظ مسودة التصرف.', value.projectId);
}

export async function approveDisposition(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(dispositionApprovalSchema.safeParse(Object.fromEntries(form))); if (isActionState(value)) return value;
  return rpc('approve_property_disposition', {
    p_organization_id:value.organizationId,p_disposition_id:value.dispositionId,
    p_idempotency_key:value.idempotencyKey,
  }, 'تعذر اعتماد التصرف.', value.projectId);
}

export async function confirmControlTransfer(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(controlTransferSchema.safeParse(Object.fromEntries(form))); if (isActionState(value)) return value;
  return rpc('confirm_property_control_transfer', {
    p_organization_id:value.organizationId,p_disposition_id:value.dispositionId,
    p_control_transfer_date:value.controlTransferDate,p_evidence_reference:value.evidenceReference,
    p_idempotency_key:value.idempotencyKey,
  }, 'تعذر إثبات انتقال السيطرة.', value.projectId);
}

export async function recognizeSale(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(saleRecognitionSchema.safeParse(Object.fromEntries(form))); if (isActionState(value)) return value;
  return rpc('recognize_property_sale', {
    p_organization_id:value.organizationId,p_disposition_id:value.dispositionId,
    p_recognition_date:value.recognitionDate,p_idempotency_key:value.idempotencyKey,
  }, 'تعذر الاعتراف بالبيع.', value.projectId);
}

export async function collectReceivable(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(saleCollectionSchema.safeParse(Object.fromEntries(form))); if (isActionState(value)) return value;
  return rpc('collect_property_sale_receivable', {
    p_organization_id:value.organizationId,p_recognition_id:value.recognitionId,
    p_cash_account_id:value.cashAccountId,
    p_amount_minor_units:parseMajorUnitsToMinor(value.amount,value.currency),
    p_collection_date:value.collectionDate,p_evidence_reference:value.evidenceReference,
    p_idempotency_key:value.idempotencyKey,
  }, 'تعذر ترحيل التحصيل.', value.projectId);
}

export async function reconcileCollection(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(collectionReconciliationSchema.safeParse(Object.fromEntries(form))); if (isActionState(value)) return value;
  return rpc('reconcile_property_sale_collection', {
    p_organization_id:value.organizationId,p_collection_id:value.collectionId,
    p_statement_line_id:value.statementLineId,p_idempotency_key:value.idempotencyKey,
  }, 'تعذر مطابقة التحصيل بسطر البنك.', value.projectId);
}

export async function classifySellingCost(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(sellingCostClassificationSchema.safeParse(Object.fromEntries(form))); if (isActionState(value)) return value;
  return rpc('classify_property_selling_cost', {
    p_organization_id:value.organizationId,p_cost_obligation_id:value.obligationId,
    p_property_asset_id:value.propertyAssetId,p_parcel_id:value.parcelId,
    p_phase_id:value.phaseId,p_policy_reference:value.policyReference,
    p_idempotency_key:value.idempotencyKey,
  }, 'تعذر إسناد تكلفة البيع.', value.projectId);
}
