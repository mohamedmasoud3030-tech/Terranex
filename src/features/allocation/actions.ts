'use server';

import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';
import { parseMajorUnitsToMinor } from '@/shared/money';
import {
  approveAllocationSchema,
  approveDistributionSchema,
  configureRulesSchema,
  participantRuleSchema,
  payDistributionSchema,
  prepareAllocationSchema,
  prepareDistributionSchema,
} from './schema';

function fail(message: string): ActionState {
  return { error: message };
}

function refresh(projectId: string) {
  revalidatePath('/');
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/investors`);
}

function domainError(message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('idempotency key payload mismatch')) return fail('مفتاح إعادة المحاولة استُخدم لبيانات مختلفة. حدّث الصفحة وحاول مجددًا.');
  if (text.includes('organization owner required') || text.includes('owner approval required')) return fail('هذا الإجراء يتطلب صلاحية مالك المنظمة.');
  if (text.includes('approved S6 close snapshot')) return fail('يجب اختيار لقطة إغلاق S6 معتمدة.');
  if (text.includes('allocation rules are not configured')) return fail('ثبّت قواعد التخصيص للنسخة الحاكمة أولًا.');
  if (text.includes('already frozen')) return fail('قواعد هذه النسخة الحاكمة مثبتة بالفعل ولا يمكن تعديلها.');
  if (text.includes('allocation basis evidence')) return fail('مرجع مستند أساس التخصيص مطلوب.');
  if (text.includes('outside the frozen allocation-basis effective range')) return fail('الفترة المغلقة خارج النطاق الفعّال لأساس التخصيص المثبت.');
  if (text.includes('active approved allocation')) return fail('لا يمكن استخدام تخصيص تم عكسه لإنشاء أو اعتماد توزيعات جديدة.');
  if (text.includes('active distribution payable')) return fail('تم عكس مستحق التوزيع؛ لا يمكن تنفيذ دفعة جديدة عليه.');
  if (text.includes('OPEN accounting period')) return fail('الترحيل يتطلب فترة محاسبية OPEN تغطي التاريخ المختار.');
  if (text.includes('already approved')) return fail('تم اعتماد هذه العملية بالفعل.');
  if (text.includes('already has an approved allocation')) return fail('هذه اللقطة المغلقة لها تخصيص معتمد بالفعل.');
  if (text.includes('exceeds participant capital')) return fail('التوزيع المطلوب يتجاوز رأس المال المتاح لهذا المستثمر.');
  if (text.includes('exceeds project distributable cash')) return fail('التوزيع المطلوب يتجاوز النقدية القابلة للتوزيع للمشروع.');
  if (text.includes('exceeds approved outstanding payable')) return fail('الدفع يتجاوز الرصيد المتبقي من التوزيع المستحق.');
  if (text.includes('exceeds cash account balance')) return fail('رصيد الحساب النقدي لا يكفي لتنفيذ الدفعة.');
  if (text.includes('payment requires an approved distribution')) return fail('لا يمكن الدفع قبل اعتماد التوزيع كمستحق.');
  return fail(fallback);
}

async function rpc(name: string, args: Record<string, unknown>) {
  const s = await createClient();
  return s.rpc(name, args) as unknown as Promise<{ data: unknown; error: { message: string } | null }>;
}

export async function configureAllocationRulesAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = configureRulesSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات قواعد التخصيص غير صحيحة');

  const partyIds = form.getAll('partyId').map(String);
  const numerators = form.getAll('weightNumerator').map(String);
  if (partyIds.length === 0 || partyIds.length !== numerators.length) return fail('يجب إدخال وزن مستقل لكل مستثمر.');
  const rows = partyIds.map((partyId, index) => ({ partyId, weightNumerator: numerators[index] }));
  const rowParsed = participantRuleSchema.array().safeParse(rows);
  if (!rowParsed.success) return fail(rowParsed.error.issues[0]?.message ?? 'أوزان المستثمرين غير صحيحة');

  const input = parsed.data;
  const { error } = await rpc('s5_configure_allocation_rules', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_governing_version_id: input.governingVersionId,
    p_policy: input.policy,
    p_participant_party_ids: rowParsed.data.map((row) => row.partyId),
    p_weight_numerators: rowParsed.data.map((row) => row.weightNumerator),
    p_common_denominator: input.commonDenominator,
    p_basis_evidence_reference: input.basisEvidenceReference,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تثبيت قواعد التخصيص.');
  refresh(input.projectId);
  return {};
}

export async function prepareAllocationAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = prepareAllocationSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات التخصيص غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s5_prepare_allocation', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_close_snapshot_id: input.closeSnapshotId,
    p_governing_version_id: input.governingVersionId,
    p_source_category: 'REALIZED_RESULT',
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تحضير تخصيص النتيجة.');
  refresh(input.projectId);
  return {};
}

export async function approveAllocationAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = approveAllocationSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات الاعتماد غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s5_approve_allocation', {
    p_organization_id: input.organizationId,
    p_run_id: input.allocationRunId,
    p_posting_date: input.postingDate,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر اعتماد تخصيص النتيجة.');
  refresh(input.projectId);
  return {};
}

export async function prepareDistributionAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = prepareDistributionSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات التوزيع غير صحيحة');
  const input = parsed.data;
  let amount: string;
  try {
    amount = parseMajorUnitsToMinor(input.amount, input.currency);
  } catch {
    return fail('مبلغ التوزيع غير صحيح أو خارج النطاق.');
  }
  const { error } = await rpc('s5_prepare_distribution', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_allocation_run_id: input.allocationRunId,
    p_participant_party_id: input.participantPartyId,
    p_requested_amount_minor_units: amount,
    p_evidence_reference: input.evidenceReference,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تحضير التوزيع المستحق.');
  refresh(input.projectId);
  return {};
}

export async function approveDistributionAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = approveDistributionSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات اعتماد التوزيع غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s5_approve_distribution', {
    p_organization_id: input.organizationId,
    p_distribution_id: input.distributionId,
    p_posting_date: input.postingDate,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر اعتماد التوزيع كمستحق.');
  refresh(input.projectId);
  return {};
}

export async function payDistributionAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = payDistributionSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات دفع التوزيع غير صحيحة');
  const input = parsed.data;
  let amount: string;
  try {
    amount = parseMajorUnitsToMinor(input.amount, input.currency);
  } catch {
    return fail('مبلغ الدفع غير صحيح أو خارج النطاق.');
  }
  const { error } = await rpc('s5_pay_distribution', {
    p_organization_id: input.organizationId,
    p_distribution_id: input.distributionId,
    p_cash_account_id: input.cashAccountId,
    p_amount_minor_units: amount,
    p_payment_date: input.paymentDate,
    p_evidence_reference: input.evidenceReference,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر دفع التوزيع المستحق.');
  refresh(input.projectId);
  return {};
}
