'use server';

import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';
import {
  agricultureProfileSchema,
  cropAssignmentSchema,
  cropCycleSchema,
  cycleTransitionSchema,
  farmSchema,
  fieldActivitySchema,
  fieldSchema,
} from './schema';

function fail(error: string): ActionState { return { error }; }
function refresh(projectId: string) {
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/agriculture`);
  revalidatePath(`/projects/${projectId}/operations`);
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
  if (text.includes('forbidden')) return fail('لا تملك صلاحية تنفيذ هذا الإجراء على هذا المشروع.');
  if (text.includes('agriculture project not found')) return fail('هذا المشروع ليس مشروعًا زراعيًا.');
  if (text.includes('expected state mismatch')) return fail('تغيّرت حالة الدورة منذ فتح الصفحة. حدّث الصفحة قبل إعادة المحاولة.');
  if (text.includes('field area capacity exceeded')) return fail('مجموع المساحات المخصصة للحقل يتجاوز سعته. راجع المواعيد والمساحات.');
  if (text.includes('assigned area must be positive')) return fail('المساحة المخصصة يجب أن تكون موجبة.');
  if (text.includes('field area must be positive')) return fail('مساحة الحقل يجب أن تكون موجبة.');
  if (text.includes('field not found')) return fail('الحقل المحدد غير موجود في هذا المشروع.');
  if (text.includes('farm not found')) return fail('المزرعة المحددة غير موجودة في هذا المشروع.');
  if (text.includes('crop cycle not found')) return fail('دورة المحصول المحددة غير موجودة في هذا المشروع.');
  if (text.includes('invalid crop cycle transition')) return fail('انتقال دورة الحياة المطلوب غير مسموح.');
  if (text.includes('cancelled crop cycle cannot receive field assignments')) return fail('لا يمكن تخصيص حقول لدورة محصول ملغاة.');
  if (text.includes('assigned area unit') && text.includes('must match')) return fail('وحدة المساحة المخصصة يجب أن تطابق وحدة الحقل.');
  if (text.includes('authentication required')) return fail('انتهت جلسة الدخول. سجّل الدخول ثم أعد المحاولة.');
  if (text.includes('invalid activity type')) return fail('نوع النشاط غير ضمن القائمة المعتمدة.');
  if (text.includes('invalid activity date')) return fail('تاريخ النشاط غير صالح.');
  if (text.includes('quantity and unit must be provided together')) return fail('الكمية ووحدتها يجب إدخالهما معًا أو تركهما معًا.');
  if (text.includes('quantity must be positive')) return fail('الكمية يجب أن تكون موجبة.');
  if (text.includes('crop cycle field assignment not found')) return fail('الحقل غير مخصص لهذه الدورة. اختر تخصيصًا قائمًا.');
  return fail(fallback);
}

async function rpc(name: string, args: Record<string, unknown>, fallback: string, projectId: string): Promise<ActionState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc(name, args);
  if (error) return domainError(error.message, fallback);
  refresh(projectId);
  return {};
}

export async function createAgricultureProfile(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(agricultureProfileSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_agriculture_profile',
    {
      p_organization_id: value.organizationId,
      p_project_id: value.projectId,
      p_notes: value.notes,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر إنشاء ملف الزراعة.',
    value.projectId,
  );
}

export async function createFarm(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(farmSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_farm',
    {
      p_organization_id: value.organizationId,
      p_project_id: value.projectId,
      p_name: value.name,
      p_internal_reference: value.internalReference,
      p_operating_location: value.operatingLocation,
      p_tenure_description: value.tenureDescription,
      p_timezone: value.timezone,
      p_map_reference: value.mapReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تسجيل المزرعة.',
    value.projectId,
  );
}

export async function createField(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(fieldSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_field',
    {
      p_organization_id: value.organizationId,
      p_project_id: value.projectId,
      p_farm_id: value.farmId,
      p_identifier: value.identifier,
      p_area_quantity: value.areaQuantity.replace(',', '.'),
      p_area_unit: value.areaUnit,
      p_soil_notes: value.soilNotes,
      p_irrigation_notes: value.irrigationNotes,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تسجيل الحقل.',
    value.projectId,
  );
}

export async function createCropCycle(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(cropCycleSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_crop_cycle',
    {
      p_organization_id: value.organizationId,
      p_project_id: value.projectId,
      p_crop: value.crop,
      p_variety: value.variety,
      p_season_reference: value.seasonReference,
      p_planned_start_date: value.plannedStartDate,
      p_planned_end_date: value.plannedEndDate,
      p_target_yield_quantity: value.targetYieldQuantity?.replace(',', '.') ?? null,
      p_target_yield_unit: value.targetYieldUnit,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر إنشاء دورة المحصول.',
    value.projectId,
  );
}

export async function assignCropCycleToField(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(cropAssignmentSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'assign_crop_cycle_to_field',
    {
      p_organization_id: value.organizationId,
      p_project_id: value.projectId,
      p_crop_cycle_id: value.cropCycleId,
      p_field_id: value.fieldId,
      p_assigned_area_quantity: value.assignedAreaQuantity.replace(',', '.'),
      p_assigned_area_unit: value.assignedAreaUnit,
      p_planned_start_date: value.plannedStartDate,
      p_planned_end_date: value.plannedEndDate,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تخصيص الحقل لدورة المحصول.',
    value.projectId,
  );
}

export async function transitionCropCycle(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(cycleTransitionSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'transition_crop_cycle',
    {
      p_organization_id: value.organizationId,
      p_crop_cycle_id: value.cropCycleId,
      p_expected_state: value.expectedState,
      p_new_state: value.newState,
      p_reason: value.reason,
      p_evidence_reference: value.evidenceReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تأكيد انتقال دورة المحصول.',
    value.projectId,
  );
}

export async function createFieldActivity(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(fieldActivitySchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_field_activity',
    {
      p_organization_id: value.organizationId,
      p_project_id: value.projectId,
      p_crop_cycle_id: value.cropCycleId,
      p_field_id: value.fieldId,
      p_assignment_id: value.assignmentId,
      p_activity_date: value.activityDate,
      p_activity_type: value.activityType,
      p_quantity: value.quantity?.replace(',', '.') ?? null,
      p_unit: value.unit,
      p_notes: value.notes,
      p_evidence_reference: value.evidenceReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تسجيل نشاط الحقل.',
    value.projectId,
  );
}
