'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/shared/supabase/server';
import type { ActionState } from '@/features/auth/actions';
import { parseMajorUnitsToMinor } from '@/features/funding/money';
import {
  propertyAssetSchema,
  propertyCostItemSchema,
  propertyValuationSchema,
  dispositionSchema,
  recognizeSaleSchema,
  collectionSchema,
  obligationSchema,
} from './schema';

function fail(message: string): ActionState {
  return { error: message };
}

function refreshProject(projectId?: string) {
  revalidatePath('/');
  if (!projectId) return;
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/property`);
  revalidatePath(`/projects/${projectId}/disposition`);
  revalidatePath(`/projects/${projectId}/result`);
}

function domainError(message: string | undefined, fallback: string): ActionState {
  if (message?.includes('property asset already sold')) {
    return fail('العقار مباع بالفعل. لا يمكن بيعه مرة أخرى بدون عملية إلغاء صريحة.');
  }
  if (message?.includes('collection exceeds outstanding receivable')) {
    return fail('مبلغ التحصيل يتجاوز المتبقي المستحق.');
  }
  if (message?.includes('cannot compute carrying amount')) {
    return fail('لا يمكن حساب التكلفة الدفترية. تأكد من وجود بيانات تكلفة موثوقة.');
  }
  if (message?.includes('disposition must be approved')) {
    return fail('يجب اعتماد التصرف قبل الاعتراف بالبيع.');
  }
  return fail(fallback);
}

export async function createPropertyAsset(_: ActionState, form: FormData): Promise<ActionState> {
  const acquisitionCost = String(form.get('acquisitionCost') || '');
  const parsed = propertyAssetSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    displayName: form.get('displayName'),
    strategy: form.get('strategy'),
    jurisdiction: form.get('jurisdiction') || '',
    titleStatus: form.get('titleStatus') || undefined,
    acquiredOn: form.get('acquiredOn') || undefined,
    acquisitionCost: acquisitionCost || '',
    currency: form.get('currency'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات العقار غير صحيحة');

  const acquisitionCostMinor = parsed.data.acquisitionCost
    ? parseMajorUnitsToMinor(parsed.data.acquisitionCost, parsed.data.currency)
    : null;

  const supabase = await createClient();
  const { error } = await supabase.rpc('create_property_asset', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_display_name: parsed.data.displayName,
    p_strategy: parsed.data.strategy,
    p_jurisdiction: parsed.data.jurisdiction || null,
    p_title_status: parsed.data.titleStatus || null,
    p_acquired_on: parsed.data.acquiredOn || null,
    p_acquisition_cost_minor_units: acquisitionCostMinor ? BigInt(acquisitionCostMinor) : null,
    p_currency: parsed.data.currency,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر إنشاء العقار. تحقق من الصلاحيات وحاول مجددًا.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function recordPropertyCostItem(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = propertyCostItemSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    propertyAssetId: form.get('propertyAssetId'),
    parcelId: form.get('parcelId') || undefined,
    costCategory: form.get('costCategory'),
    isCapitalizable: form.get('isCapitalizable') === 'true',
    costAmount: form.get('costAmount'),
    currency: form.get('currency'),
    description: form.get('description') || '',
    occurredOn: form.get('occurredOn'),
    obligationId: form.get('obligationId') || undefined,
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات التكلفة غير صحيحة');

  const costMinor = parseMajorUnitsToMinor(parsed.data.costAmount, parsed.data.currency);
  const supabase = await createClient();
  const { error } = await supabase.rpc('record_property_cost_item', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_property_asset_id: parsed.data.propertyAssetId,
    p_parcel_id: parsed.data.parcelId || null,
    p_cost_category: parsed.data.costCategory,
    p_is_capitalizable: parsed.data.isCapitalizable,
    p_cost_minor_units: BigInt(costMinor),
    p_currency: parsed.data.currency,
    p_description: parsed.data.description || null,
    p_occurred_on: parsed.data.occurredOn,
    p_obligation_id: parsed.data.obligationId || null,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل التكلفة. تحقق من البيانات وحاول مجددًا.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function recordPropertyValuation(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = propertyValuationSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    propertyAssetId: form.get('propertyAssetId'),
    effectiveDate: form.get('effectiveDate'),
    valuerSource: form.get('valuerSource'),
    method: form.get('method'),
    valuationAmount: form.get('valuationAmount'),
    currency: form.get('currency'),
    assumptions: form.get('assumptions') || '',
    confidence: form.get('confidence') || undefined,
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات التقييم غير صحيحة');

  const valuationMinor = parseMajorUnitsToMinor(parsed.data.valuationAmount, parsed.data.currency);
  const supabase = await createClient();
  const { error } = await supabase.rpc('record_property_valuation', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_property_asset_id: parsed.data.propertyAssetId,
    p_effective_date: parsed.data.effectiveDate,
    p_valuer_source: parsed.data.valuerSource,
    p_method: parsed.data.method,
    p_valuation_minor_units: BigInt(valuationMinor),
    p_currency: parsed.data.currency,
    p_assumptions: parsed.data.assumptions || null,
    p_confidence: parsed.data.confidence || null,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل التقييم. تحقق من البيانات وحاول مجددًا.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function createDisposition(_: ActionState, form: FormData): Promise<ActionState> {
  const sellingCosts = String(form.get('sellingCosts') || '');
  const parsed = dispositionSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    propertyAssetId: form.get('propertyAssetId'),
    buyerPartyId: form.get('buyerPartyId'),
    agreedProceeds: form.get('agreedProceeds'),
    currency: form.get('currency'),
    agreementDate: form.get('agreementDate'),
    sellingCosts: sellingCosts || '',
    contractReference: form.get('contractReference') || '',
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات التصرف غير صحيحة');

  const proceedsMinor = parseMajorUnitsToMinor(parsed.data.agreedProceeds, parsed.data.currency);
  const sellingCostsMinor = parsed.data.sellingCosts
    ? parseMajorUnitsToMinor(parsed.data.sellingCosts, parsed.data.currency)
    : '0';

  const supabase = await createClient();
  const { error } = await supabase.rpc('create_disposition', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_property_asset_id: parsed.data.propertyAssetId,
    p_buyer_party_id: parsed.data.buyerPartyId,
    p_agreed_proceeds_minor_units: BigInt(proceedsMinor),
    p_currency: parsed.data.currency,
    p_agreement_date: parsed.data.agreementDate,
    p_selling_costs_minor_units: BigInt(sellingCostsMinor),
    p_contract_reference: parsed.data.contractReference || null,
    p_evidence_document_ids: null,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر إنشاء التصرف. تحقق من البيانات وحاول مجددًا.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function approveDisposition(_: ActionState, form: FormData): Promise<ActionState> {
  const organizationId = String(form.get('organizationId') || '');
  const dispositionId = String(form.get('dispositionId') || '');
  const projectId = String(form.get('projectId') || '');

  if (!organizationId || !dispositionId) {
    return fail('بيانات غير مكتملة');
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc('approve_disposition', {
    p_organization_id: organizationId,
    p_disposition_id: dispositionId,
  });
  if (error) return domainError(error.message, 'تعذر اعتماد التصرف.');
  refreshProject(projectId);
  return {};
}

export async function recognizeSale(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = recognizeSaleSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    dispositionId: form.get('dispositionId'),
    controlTransferDate: form.get('controlTransferDate'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات الاعتراف غير صحيحة');

  const supabase = await createClient();
  const { error } = await supabase.rpc('recognize_sale', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_disposition_id: parsed.data.dispositionId,
    p_control_transfer_date: parsed.data.controlTransferDate,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر الاعتراف بالبيع. تحقق من حالة التصرف والتكاليف.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function recordCollection(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = collectionSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    saleReceivableId: form.get('saleReceivableId'),
    collectionAmount: form.get('collectionAmount'),
    currency: form.get('currency'),
    collectedOn: form.get('collectedOn'),
    cashAccountId: form.get('cashAccountId'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات التحصيل غير صحيحة');

  const collectionMinor = parseMajorUnitsToMinor(parsed.data.collectionAmount, parsed.data.currency);
  const supabase = await createClient();
  const { error } = await supabase.rpc('record_collection', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_sale_receivable_id: parsed.data.saleReceivableId,
    p_collection_minor_units: BigInt(collectionMinor),
    p_currency: parsed.data.currency,
    p_collected_on: parsed.data.collectedOn,
    p_cash_account_id: parsed.data.cashAccountId,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل التحصيل. تحقق من المبلغ والمتبقي.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function recordObligation(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = obligationSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    supplierPartyId: form.get('supplierPartyId'),
    amount: form.get('amount'),
    currency: form.get('currency'),
    costCategory: form.get('costCategory'),
    description: form.get('description') || '',
    occurredOn: form.get('occurredOn'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات الالتزام غير صحيحة');

  const amountMinor = parseMajorUnitsToMinor(parsed.data.amount, parsed.data.currency);
  const supabase = await createClient();
  const { error } = await supabase.rpc('record_obligation', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_supplier_party_id: parsed.data.supplierPartyId,
    p_amount_minor_units: BigInt(amountMinor),
    p_currency: parsed.data.currency,
    p_cost_category: parsed.data.costCategory,
    p_description: parsed.data.description || null,
    p_occurred_on: parsed.data.occurredOn,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل الالتزام. تحقق من البيانات وحاول مجددًا.');
  refreshProject(parsed.data.projectId);
  return {};
}
