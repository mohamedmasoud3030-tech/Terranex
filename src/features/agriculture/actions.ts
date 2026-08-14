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
  harvestEventSchema,
  harvestInventoryAdjustmentSchema,
  inputApplicationSchema,
  inputItemSchema,
  inputLotSchema,
  storageLocationSchema,
  transferHarvestInventorySchema,
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
  // GF-015 — input item, input lot, and input application.
  if (text.includes('invalid input category')) return fail('فئة المدخل يجب أن تكون تقاوي أو سماد أو مبيد/كيماوي.');
  if (text.includes('invalid input name')) return fail('اسم المدخل مطلوب (حرفان على الأقل).');
  if (text.includes('invalid application unit')) return fail('وحدة تطبيق المدخل مطلوبة.');
  if (text.includes('invalid lot reference')) return fail('مرجع التشغيلة مطلوب.');
  if (text.includes('input item already exists')) return fail('يوجد مدخل بنفس الاسم والفئة في هذا المشروع.');
  if (text.includes('input lot reference already exists')) return fail('مرجع التشغيلة مستخدم بالفعل لهذا المدخل.');
  if (text.includes('manufacture date must not be after the expiry date')) return fail('تاريخ التصنيع يجب ألا يكون بعد تاريخ الانتهاء.');
  if (text.includes('input item not found')) return fail('المدخل المحدد غير موجود في هذا المشروع.');
  if (text.includes('input lot not found')) return fail('التشغيلة المحددة غير موجودة لهذا المدخل.');
  if (text.includes('field activity not found')) return fail('نشاط الحقل المحدد غير موجود في هذه المنظمة.');
  if (text.includes('does not accept an input application')) return fail('نوع نشاط الحقل المحدد لا يستقبل تطبيق مدخلات. اختر زراعة أو تسميد أو رش.');
  if (text.includes('requires a PLANT activity')) return fail('التقاوي تُسجَّل على نشاط زراعة فقط.');
  if (text.includes('requires a FERTILIZE activity')) return fail('السماد يُسجَّل على نشاط تسميد فقط.');
  if (text.includes('requires a SPRAY activity')) return fail('المبيد/الكيماوي يُسجَّل على نشاط رش فقط.');
  if (text.includes('expired on')) return fail('التشغيلة منتهية الصلاحية في تاريخ التطبيق ولا يمكن تسجيلها.');
  if (text.includes('application quantity must be positive')) return fail('كمية التطبيق يجب أن تكون موجبة.');
  if (text.includes('application unit must be the input item unit')) return fail('وحدة الكمية يجب أن تطابق وحدة تطبيق المدخل.');
  if (text.includes('applied area must be positive')) return fail('المساحة المعالجة يجب أن تكون موجبة.');
  if (text.includes('applied area unit must be the assignment area unit')) return fail('وحدة المساحة المعالجة يجب أن تطابق وحدة مساحة التخصيص.');
  if (text.includes('applied area exceeds the assigned area')) return fail('المساحة المعالجة تتجاوز المساحة المخصصة لهذا التخصيص.');
  if (text.includes('invalid application date')) return fail('تاريخ التطبيق غير صالح.');
  if (text.includes('invalid safety note')) return fail('ملاحظة السلامة غير صالحة.');
  // GF-016 — harvest event, harvest lot, storage location, and harvest inventory movement.
  if (text.includes('invalid storage location name')) return fail('اسم موقع التخزين مطلوب (حرفان على الأقل).');
  if (text.includes('storage location already exists')) return fail('يوجد موقع تخزين بنفس الاسم في هذا المشروع.');
  if (text.includes('storage location not found')) return fail('موقع التخزين المحدد غير موجود في هذا المشروع.');
  if (text.includes('crop cycle is not harvest-ready')) return fail('دورة المحصول ليست جاهزة للحصاد. انقلها إلى حالة "قيد الحصاد" أولًا.');
  if (text.includes('harvest gross quantity must be positive')) return fail('الكمية الإجمالية للحصاد يجب أن تكون موجبة.');
  if (text.includes('harvest net quantity must be positive')) return fail('الكمية الصافية للحصاد يجب أن تكون موجبة.');
  if (text.includes('harvest net quantity must not exceed gross quantity')) return fail('الكمية الصافية يجب ألا تتجاوز الكمية الإجمالية.');
  if (text.includes('invalid harvest quantity unit')) return fail('وحدة كمية الحصاد مطلوبة.');
  if (text.includes('invalid harvest grade')) return fail('درجة/جودة الحصاد غير صالحة.');
  if (text.includes('harvest lot reference already exists')) return fail('مرجع تشغيلة الحصاد مستخدم بالفعل في هذا المشروع.');
  if (text.includes('harvest lot not found')) return fail('تشغيلة الحصاد المحددة غير موجودة في هذه المنظمة.');
  if (text.includes('insufficient inventory')) return fail('الرصيد المتاح غير كافٍ لهذه الحركة.');
  if (text.includes('transfer source and destination storage must differ')) return fail('لا يمكن النقل إلى نفس موقع التخزين.');
  if (text.includes('cannot precede the harvest date')) return fail('تاريخ الحركة لا يمكن أن يسبق تاريخ الحصاد.');
  if (text.includes('transfer quantity must be positive')) return fail('كمية النقل يجب أن تكون موجبة.');
  if (text.includes('adjustment quantity must be positive')) return fail('كمية التعديل يجب أن تكون موجبة.');
  if (text.includes('adjustment reason is required')) return fail('سبب التعديل مطلوب.');
  if (text.includes('invalid harvest inventory movement type')) return fail('نوع حركة المخزون غير صالح.');
  if (text.includes('invalid movement reason')) return fail('سبب الحركة غير صالح.');
  if (text.includes('invalid movement date')) return fail('تاريخ الحركة غير صالح.');
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

// ---------------------------------------------------------------------------
// GF-015 — Field Input Application Foundation.
//
// Three commands, all server-authoritative. The browser never supplies
// the actor, and for an application it never supplies the project,
// crop cycle, field, or assignment: the server derives all four from
// the referenced FieldActivity. `projectId` is carried in the form only
// so the affected workspace paths can be revalidated.
//
// GF-015 records the operational fact only. No obligation, payment,
// journal, investor balance, inventory balance, valuation, or
// biological-asset accounting fact is created, and CropCycle lifecycle
// state is never advanced. Available-stock validation begins only when
// the canonical InventoryMovement slice exists.
// ---------------------------------------------------------------------------

export async function createInputItem(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(inputItemSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_input_item',
    {
      p_organization_id: value.organizationId,
      p_project_id: value.projectId,
      p_category: value.category,
      p_name: value.name,
      p_internal_reference: value.internalReference,
      p_application_unit: value.applicationUnit,
      p_manufacturer: value.manufacturer,
      p_notes: value.notes,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تسجيل المدخل الزراعي.',
    value.projectId,
  );
}

export async function createInputLot(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(inputLotSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  // The project and the unit are derived server-side from the input
  // item; they are deliberately not sent from the browser.
  return rpc(
    'create_input_lot',
    {
      p_organization_id: value.organizationId,
      p_input_item_id: value.inputItemId,
      p_lot_reference: value.lotReference,
      p_supplier_reference: value.supplierReference,
      p_manufactured_on: value.manufacturedOn ?? null,
      p_expires_on: value.expiresOn ?? null,
      p_evidence_reference: value.evidenceReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تسجيل تشغيلة المدخل.',
    value.projectId,
  );
}

export async function recordInputApplication(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(inputApplicationSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'record_input_application',
    {
      p_organization_id: value.organizationId,
      p_field_activity_id: value.fieldActivityId,
      p_input_item_id: value.inputItemId,
      p_input_lot_id: value.inputLotId,
      p_application_date: value.applicationDate,
      p_quantity: value.quantity.replace(',', '.'),
      p_unit: value.unit,
      p_applied_area_quantity: value.appliedAreaQuantity.replace(',', '.'),
      p_applied_area_unit: value.appliedAreaUnit,
      p_notes: value.notes,
      p_safety_note: value.safetyNote,
      p_evidence_reference: value.evidenceReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تسجيل تطبيق المدخل.',
    value.projectId,
  );
}

// ---------------------------------------------------------------------------
// GF-016 — Harvest & Inventory Flow Foundation.
//
// Four commands, all server-authoritative. The browser never supplies the
// actor. For a harvest, project, crop cycle, field and assignment are all
// derived server-side from the referenced assignment; the movement unit is
// derived server-side from the referenced Harvest Lot. `projectId` is
// carried in the form only so the affected workspace paths are revalidated.
//
// GF-016 tracks physical harvest-output quantity only: no sale, valuation,
// accounting, biological-asset, or input-stock fact is created, and
// CropCycle lifecycle state is never advanced.
// ---------------------------------------------------------------------------

export async function createStorageLocation(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(storageLocationSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'create_storage_location',
    {
      p_organization_id: value.organizationId,
      p_project_id: value.projectId,
      p_name: value.name,
      p_internal_reference: value.internalReference,
      p_notes: value.notes,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تسجيل موقع التخزين.',
    value.projectId,
  );
}

export async function recordHarvestEvent(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(harvestEventSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  // Project, crop cycle, field and assignment are derived server-side from
  // the referenced assignment; they are not re-asserted by the browser.
  return rpc(
    'record_harvest_event',
    {
      p_organization_id: value.organizationId,
      p_assignment_id: value.assignmentId,
      p_harvest_date: value.harvestDate,
      p_gross_quantity: value.grossQuantity.replace(',', '.'),
      p_net_quantity: value.netQuantity.replace(',', '.'),
      p_quantity_unit: value.quantityUnit,
      p_grade: value.grade,
      p_lot_reference: value.lotReference,
      p_destination_storage_id: value.destinationStorageId,
      p_notes: value.notes,
      p_evidence_reference: value.evidenceReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تسجيل حدث الحصاد.',
    value.projectId,
  );
}

export async function transferHarvestInventory(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(transferHarvestInventorySchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  // The movement unit is derived server-side from the Harvest Lot's own
  // unit; it is never supplied by the browser.
  return rpc(
    'transfer_harvest_inventory',
    {
      p_organization_id: value.organizationId,
      p_harvest_lot_id: value.harvestLotId,
      p_from_storage_id: value.fromStorageId,
      p_to_storage_id: value.toStorageId,
      p_quantity: value.quantity.replace(',', '.'),
      p_movement_date: value.movementDate,
      p_reason: value.reason,
      p_evidence_reference: value.evidenceReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تنفيذ نقل المخزون.',
    value.projectId,
  );
}

export async function recordHarvestInventoryAdjustment(_: ActionState, form: FormData): Promise<ActionState> {
  const value = parse(harvestInventoryAdjustmentSchema.safeParse(Object.fromEntries(form)));
  if (isActionState(value)) return value;
  return rpc(
    'record_harvest_inventory_adjustment',
    {
      p_organization_id: value.organizationId,
      p_harvest_lot_id: value.harvestLotId,
      p_storage_id: value.storageId,
      p_movement_type: value.movementType,
      p_quantity: value.quantity.replace(',', '.'),
      p_movement_date: value.movementDate,
      p_reason: value.reason,
      p_evidence_reference: value.evidenceReference,
      p_idempotency_key: value.idempotencyKey,
    },
    'تعذر تسجيل تعديل المخزون.',
    value.projectId,
  );
}
