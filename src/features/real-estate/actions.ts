'use server';

import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { parseMajorUnitsToMinor, parseSignedMajorUnitsToMinor } from '@/shared/money';
import { createClient } from '@/shared/supabase/server';
import {
  acquisitionSchema,
  approvalSchema,
  assetSchema,
  budgetSchema,
  controlSchema,
  costClassificationSchema,
  milestoneSchema,
  parcelSchema,
  phaseSchema,
  profileSchema,
  sectorEventSchema,
  transitionSchema,
  valuationSchema,
} from './schema';

function fail(error: string): ActionState {
  return { error };
}
function refresh(projectId: string) {
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/operations`);
  revalidatePath(`/projects/${projectId}/costs`);
  revalidatePath(`/projects/${projectId}/intake`);
}
function projectId(form: FormData): string {
  return String(form.get('projectId') ?? '');
}
function domainError(message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('idempotency key payload mismatch'))
    return fail('مفتاح العملية استُخدم لبيانات مختلفة. حدّث الصفحة وأعد المحاولة.');
  if (text.includes('organization owner required'))
    return fail('هذا التأكيد المادي يتطلب صلاحية مالك المنظمة.');
  if (text.includes('expected state mismatch'))
    return fail('تغيّرت الحالة منذ فتح الصفحة. حدّث الصفحة قبل إعادة المحاولة.');
  if (text.includes('requires effective passed title'))
    return fail('لا يمكن إثبات الحيازة دون سند ملكية ناجح وساري.');
  if (text.includes('requires effective passed possession'))
    return fail('لا يمكن إثبات الحيازة دون محضر استلام ناجح وساري.');
  if (text.includes('requires a passed acquisition'))
    return fail('يلزم فحص استحواذ ناجح قبل بدء الاستحواذ.');
  if (text.includes('requires a recorded acquisition'))
    return fail('يلزم تسجيل عقد الاستحواذ أولًا.');
  if (text.includes('same project') || text.includes('must belong'))
    return fail('المرجع المحدد لا ينتمي إلى نفس المشروع أو الأصل.');
  if (text.includes('only a proposed'))
    return fail('تم اعتماد هذا المقترح أو لم يعد قابلًا للاعتماد. حدّث الصفحة.');
  if (text.includes('forbidden')) return fail('لا تملك صلاحية تنفيذ هذا الإجراء.');
  return fail(fallback);
}
async function rpc(
  name: string,
  args: Record<string, unknown>,
  fallback: string,
  pathProjectId: string,
): Promise<ActionState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc(name, args);
  if (error) return domainError(error.message, fallback);
  refresh(pathProjectId);
  return {};
}
function parse<T>(
  result: { success: true; data: T } | { success: false; error: { issues: { message: string }[] } },
): T | ActionState {
  return result.success
    ? result.data
    : fail(result.error.issues[0]?.message ?? 'البيانات غير صحيحة');
}
function isActionState(value: unknown): value is ActionState {
  return typeof value === 'object' && value !== null && 'error' in value;
}

export async function createProfile(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(profileSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_real_estate_profile',
    {
      p_organization_id: value.organizationId,
      p_project_id: value.projectId,
      p_strategy: value.strategy,
      p_jurisdiction: value.jurisdiction,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر إنشاء ملف المشروع العقاري.',
    value.projectId,
  );
}
export async function createAsset(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(assetSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_property_asset',
    {
      p_organization_id: value.organizationId,
      p_project_id: value.projectId,
      p_name: value.name,
      p_asset_reference: value.assetReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر إنشاء الأصل العقاري.',
    value.projectId,
  );
}
export async function createParcel(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(parcelSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_parcel',
    {
      p_organization_id: value.organizationId,
      p_property_asset_id: value.propertyAssetId,
      p_identifier: value.identifier,
      p_cadastral_reference: value.cadastralReference,
      p_legal_description: value.legalDescription,
      p_area_quantity: value.areaQuantity.replace(',', '.'),
      p_area_unit: value.areaUnit,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر إضافة القطعة.',
    projectId(form),
  );
}
export async function recordAcquisition(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(acquisitionSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'record_property_acquisition',
    {
      p_organization_id: value.organizationId,
      p_property_asset_id: value.propertyAssetId,
      p_seller_party_id: value.sellerPartyId,
      p_contract_reference: value.contractReference,
      p_consideration_minor_units: parseMajorUnitsToMinor(value.consideration, value.currency),
      p_closing_costs_minor_units: parseSignedMajorUnitsToMinor(value.closingCosts, value.currency),
      p_currency: value.currency,
      p_contract_date: value.contractDate,
      p_consideration_obligation_id: value.considerationObligationId,
      p_evidence_reference: value.evidenceReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تسجيل الاستحواذ.',
    projectId(form),
  );
}
export async function recordControl(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(controlSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'record_property_control',
    {
      p_organization_id: value.organizationId,
      p_property_asset_id: value.propertyAssetId,
      p_parcel_id: value.parcelId,
      p_record_type: value.recordType,
      p_control_type: value.controlType,
      p_status: value.status,
      p_effective_date: value.effectiveDate,
      p_expiry_date: value.expiryDate,
      p_result: value.result,
      p_responsible_actor_id: value.responsibleActorId,
      p_evidence_reference: value.evidenceReference,
      p_notes: value.notes,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تسجيل الفحص أو الدليل.',
    projectId(form),
  );
}
export async function transitionProperty(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(
    transitionSchema.safeParse({
      ...Object.fromEntries(form),
      subjectId: form.get('propertyAssetId'),
    }),
  );
  if (isActionState(value)) return value;
  return rpc(
    'transition_property_asset',
    {
      p_organization_id: value.organizationId,
      p_property_asset_id: value.subjectId,
      p_expected_state: value.expectedState,
      p_new_state: value.newState,
      p_reason: value.reason,
      p_evidence_reference: value.evidenceReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تغيير حالة الأصل. تحقق من الأدلة وتسلسل الحالة.',
    projectId(form),
  );
}
export async function createPhase(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(phaseSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_development_phase',
    {
      p_organization_id: value.organizationId,
      p_property_asset_id: value.propertyAssetId,
      p_parcel_id: value.parcelId,
      p_name: value.name,
      p_sequence_no: value.sequenceNo,
      p_planned_start_date: value.plannedStartDate,
      p_planned_end_date: value.plannedEndDate,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر إنشاء مرحلة التطوير.',
    projectId(form),
  );
}
export async function transitionPhase(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(
    transitionSchema.safeParse({ ...Object.fromEntries(form), subjectId: form.get('phaseId') }),
  );
  if (isActionState(value)) return value;
  return rpc(
    'transition_development_phase',
    {
      p_organization_id: value.organizationId,
      p_phase_id: value.subjectId,
      p_expected_state: value.expectedState,
      p_new_state: value.newState,
      p_reason: value.reason,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تغيير حالة المرحلة.',
    projectId(form),
  );
}
export async function createMilestone(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(milestoneSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_development_milestone',
    {
      p_organization_id: value.organizationId,
      p_phase_id: value.phaseId,
      p_name: value.name,
      p_sequence_no: value.sequenceNo,
      p_planned_date: value.plannedDate,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر إنشاء العلامة.',
    projectId(form),
  );
}
export async function transitionMilestone(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(
    transitionSchema.safeParse({ ...Object.fromEntries(form), subjectId: form.get('milestoneId') }),
  );
  if (isActionState(value)) return value;
  return rpc(
    'transition_development_milestone',
    {
      p_organization_id: value.organizationId,
      p_milestone_id: value.subjectId,
      p_expected_state: value.expectedState,
      p_new_state: value.newState,
      p_reason: value.reason,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تغيير حالة العلامة.',
    projectId(form),
  );
}
export async function proposeBudget(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(budgetSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'propose_property_budget',
    {
      p_organization_id: value.organizationId,
      p_property_asset_id: value.propertyAssetId,
      p_currency: value.currency,
      p_basis_notes: value.basisNotes,
      p_parcel_ids: [value.parcelId],
      p_phase_ids: [value.phaseId],
      p_cost_categories: [value.costCategory],
      p_amount_minor_units: [parseMajorUnitsToMinor(value.amount, value.currency)],
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر حفظ مقترح الميزانية.',
    projectId(form),
  );
}
export async function approveBudget(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(
    approvalSchema.safeParse({
      ...Object.fromEntries(form),
      subjectId: form.get('budgetVersionId'),
    }),
  );
  if (isActionState(value)) return value;
  return rpc(
    'approve_property_budget',
    {
      p_organization_id: value.organizationId,
      p_budget_version_id: value.subjectId,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر اعتماد نسخة الميزانية.',
    projectId(form),
  );
}
export async function classifyCost(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(costClassificationSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'classify_property_cost',
    {
      p_organization_id: value.organizationId,
      p_cost_obligation_id: value.obligationId,
      p_property_asset_id: value.propertyAssetId,
      p_parcel_id: value.parcelId,
      p_phase_id: value.phaseId,
      p_cost_category: value.costCategory,
      p_policy_reference: value.policyReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر إسناد بُعد التكلفة العقاري.',
    projectId(form),
  );
}
export async function proposeValuation(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(valuationSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'propose_property_valuation',
    {
      p_organization_id: value.organizationId,
      p_property_asset_id: value.propertyAssetId,
      p_effective_date: value.effectiveDate,
      p_valuer_source: value.valuerSource,
      p_method: value.method,
      p_amount_minor_units: parseMajorUnitsToMinor(value.amount, value.currency),
      p_currency: value.currency,
      p_assumptions_notes: value.assumptionsNotes,
      p_confidence: value.confidence,
      p_evidence_reference: value.evidenceReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر حفظ التقييم الإداري المقترح.',
    projectId(form),
  );
}
export async function approveValuation(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(
    approvalSchema.safeParse({ ...Object.fromEntries(form), subjectId: form.get('valuationId') }),
  );
  if (isActionState(value)) return value;
  return rpc(
    'approve_property_valuation',
    {
      p_organization_id: value.organizationId,
      p_valuation_id: value.subjectId,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر اعتماد التقييم الإداري.',
    projectId(form),
  );
}
export async function confirmSectorEvent(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(sectorEventSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'confirm_real_estate_event',
    {
      p_organization_id: value.organizationId,
      p_project_id: value.projectId,
      p_property_asset_id: value.propertyAssetId,
      p_parcel_id: value.parcelId,
      p_phase_id: value.phaseId,
      p_milestone_id: value.milestoneId,
      p_event_type: value.eventType,
      p_occurred_at: new Date(value.occurredAt).toISOString(),
      p_quantity: value.quantity?.replace(',', '.') ?? null,
      p_unit: value.unit,
      p_responsible_actor_id: value.responsibleActorId,
      p_location: value.location,
      p_notes: value.notes,
      p_evidence_reference: value.evidenceReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تأكيد الحدث العقاري.',
    value.projectId,
  );
}
