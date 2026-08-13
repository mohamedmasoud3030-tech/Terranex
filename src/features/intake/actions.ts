'use server';

import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';
import {
  acceptModellingGapSchema,
  declareControlTotalsSchema,
  declareSectionApplicabilitySchema,
  recordEvidenceItemSchema,
  recordFreezeDateSchema,
  recordSetupReferencesSchema,
  reportModellingGapSchema,
} from './schema';

function fail(message: string): ActionState {
  return { error: message };
}

function refresh(projectId: string) {
  revalidatePath('/');
  revalidatePath('/intake');
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/intake`);
  revalidatePath(`/projects/${projectId}/pilot`);
}

function domainError(message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('authentication required')) return fail('انتهت الجلسة. سجّل الدخول ثم أعد المحاولة.');
  if (text.includes('organization owner required')) return fail('هذا الإجراء يتطلب صلاحية مالك المنظمة.');
  if (text.includes('forbidden')) return fail('لا تملك صلاحية على هذه المنظمة. قد تكون عضويتك أُلغيت.');
  if (text.includes('project not found')) return fail('المشروع غير موجود في هذه المنظمة.');
  if (text.includes('freeze date is set-once')) return fail('تاريخ التجميد يُسجَّل مرة واحدة. أي استخراج لاحق يكون بتاريخ جديد، لا بإعادة كتابة.');
  if (text.includes('freeze date cannot change after a posted opening')) return fail('لا يمكن تغيير تاريخ التجميد بعد ترحيل استيراد افتتاحي.');
  if (text.includes('does not accept a plug')) return fail('إجمالي المدين المعلن يجب أن يساوي إجمالي الدائن. تيرانكس لا تقبل قيد تسوية.');
  if (text.includes('cannot change after a posted opening import')) return fail('لا يمكن تعديل هذا التصريح بعد ترحيل استيراد افتتاحي.');
  if (text.includes('unknown intake section code')) return fail('قسم غير معروف.');
  if (text.includes('at least one setup reference')) return fail('أدخل مرجع الاتفاقية أو دليل المنظمة أو دليل نطاق المشروع.');
  if (text.includes('commercially accept')) return fail('فجوة النمذجة لا تُعاد كتابتها. اقبلها تجاريًا أو اتركها مفتوحة.');
  return fail(fallback);
}

async function rpc(name: string, args: Record<string, unknown>) {
  const s = await createClient();
  return s.rpc(name, args) as unknown as Promise<{ data: unknown; error: { message: string } | null }>;
}

function orNull(value: string | undefined): string | null {
  return value && value.length > 0 ? value : null;
}

export async function recordFreezeDateAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = recordFreezeDateSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات تاريخ التجميد غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('intake_record_freeze_date', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_freeze_date: input.freezeDate,
    p_evidence_reference: input.evidenceReference,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل تاريخ التجميد.');
  refresh(input.projectId);
  return {};
}

export async function declareControlTotalsAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = declareControlTotalsSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات المجاميع الرقابية غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('intake_declare_control_totals', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_declared_debit_total: input.declaredDebitTotal,
    p_declared_credit_total: input.declaredCreditTotal,
    p_evidence_reference: input.evidenceReference,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل المجاميع الرقابية.');
  refresh(input.projectId);
  return {};
}

export async function recordSetupReferencesAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = recordSetupReferencesSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات المراجع غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('intake_record_setup_references', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_agreement_title_or_reference: orNull(input.agreementTitleOrReference),
    p_organization_evidence_reference: orNull(input.organizationEvidenceReference),
    p_project_evidence_reference: orNull(input.projectEvidenceReference),
  });
  if (error) return domainError(error.message, 'تعذر تسجيل مراجع الإعداد.');
  refresh(input.projectId);
  return {};
}

export async function declareSectionApplicabilityAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = declareSectionApplicabilitySchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات تصنيف القسم غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('intake_declare_section_applicability', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_section_code: input.sectionCode,
    p_applicable: input.applicable === 'true',
    p_reason: input.reason,
    p_evidence_reference: orNull(input.evidenceReference),
  });
  if (error) return domainError(error.message, 'تعذر تسجيل تصنيف القسم.');
  refresh(input.projectId);
  return {};
}

export async function reportModellingGapAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = reportModellingGapSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات فجوة النمذجة غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('intake_report_modelling_gap', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_source_reference: input.sourceReference,
    p_description: input.description,
    p_amount_minor_units: orNull(input.amountMinorUnits),
    p_why_unmappable: input.whyUnmappable,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل فجوة النمذجة.');
  refresh(input.projectId);
  return {};
}

export async function acceptModellingGapAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = acceptModellingGapSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات قبول الفجوة غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('intake_accept_modelling_gap', {
    p_organization_id: input.organizationId,
    p_gap_id: input.gapId,
    p_resolution_evidence_reference: input.resolutionEvidenceReference,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل القبول التجاري للفجوة.');
  refresh(input.projectId);
  return {};
}

export async function recordEvidenceItemAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = recordEvidenceItemSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات سجل الأدلة غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('intake_record_evidence_item', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_evidence_identifier: input.evidenceIdentifier,
    p_linked_fact: input.linkedFact,
    p_customer_storage_location: input.customerStorageLocation,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل مرجع الدليل.');
  refresh(input.projectId);
  return {};
}
