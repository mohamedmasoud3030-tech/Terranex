'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/shared/supabase/server';
import type { ActionState } from '@/features/auth/actions';
import { parseMajorUnitsToMinor } from '@/shared/money';
import {
  activateVersionSchema,
  agreementDraftSchema,
  capitalCallSchema,
  contributionSchema,
  participantSchema,
  partySchema,
} from './schema';

function fail(message: string): ActionState {
  return { error: message };
}

function refreshProject(projectId?: string) {
  revalidatePath('/');
  if (!projectId) return;
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/terms`);
  revalidatePath(`/projects/${projectId}/funding`);
  revalidatePath(`/projects/${projectId}/intake`);
}

function domainError(message: string | undefined, fallback: string): ActionState {
  if (message?.includes('idempotency key payload mismatch')) {
    return fail('تعذر إعادة المحاولة لأن مفتاح العملية استُخدم سابقًا لبيانات مختلفة. حدّث الصفحة وحاول من جديد.');
  }
  if (message?.includes('capital call exceeds participant commitment')) {
    return fail('المبلغ المطلوب يتجاوز الالتزام المتاح لهذا المستثمر.');
  }
  if (message?.includes('agreement amendment activation is deferred')) {
    return fail('تعديل اتفاقية مفعّلة غير متاح في هذه المرحلة. النسخة الحالية تظل هي الحاكمة.');
  }
  return fail(fallback);
}

export async function createParty(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = partySchema.safeParse({
    organizationId: form.get('organizationId'),
    legalName: form.get('legalName'),
    partyType: form.get('partyType') || 'PERSON',
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('create_party', {
    p_organization_id: parsed.data.organizationId,
    p_legal_name: parsed.data.legalName,
    p_party_type: parsed.data.partyType,
  });
  if (error) return fail('تعذر إنشاء الطرف. تحقق من الصلاحيات وحاول مجددًا.');
  refreshProject(String(form.get('projectId') || ''));
  return {};
}

export async function addParticipant(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = participantSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    partyId: form.get('partyId'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'معرّفات غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('add_project_participant', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_party_id: parsed.data.partyId,
  });
  if (error) return fail('تعذر إضافة المشارك. قد يكون الطرف من منظمة أخرى أو مضافًا بالفعل.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function createAgreementDraft(_: ActionState, form: FormData): Promise<ActionState> {
  const organizationId = String(form.get('organizationId') || '');
  const projectId = String(form.get('projectId') || '');
  const effectiveDate = String(form.get('effectiveDate') || '');
  const idempotencyKey = String(form.get('idempotencyKey') || '');
  const participantIds = form.getAll('participantId').map(String);
  const commitmentAmounts = form.getAll('commitmentAmount').map(String);

  const parsed = agreementDraftSchema.safeParse({
    organizationId,
    projectId,
    effectiveDate,
    idempotencyKey,
    participants: participantIds.map((participantId, i) => ({
      participantId,
      commitmentAmount: commitmentAmounts[i] ?? '',
    })),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات الاتفاقية غير صحيحة');

  const commitments = parsed.data.participants.map((participant) =>
    parseMajorUnitsToMinor(participant.commitmentAmount, 'EGP'),
  );
  const supabase = await createClient();
  const { error } = await supabase.rpc('create_agreement_draft', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_effective_date: parsed.data.effectiveDate,
    p_participant_ids: parsed.data.participants.map((participant) => participant.participantId),
    p_commitments: commitments,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر حفظ مسودة الاتفاقية. راجع الالتزامات والمشاركين.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function activateAgreementVersion(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = activateVersionSchema.safeParse({
    organizationId: form.get('organizationId'),
    versionId: form.get('versionId'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'نسخة غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('activate_agreement_version', {
    p_organization_id: parsed.data.organizationId,
    p_version_id: parsed.data.versionId,
  });
  if (error) return domainError(error.message, 'تعذر تفعيل الاتفاقية. لا يمكن تفعيل نسخة غير مسودة أو توجد نسخة حاكمة بالفعل.');
  refreshProject(String(form.get('projectId') || ''));
  return {};
}

export async function createCapitalCall(_: ActionState, form: FormData): Promise<ActionState> {
  const organizationId = String(form.get('organizationId') || '');
  const projectId = String(form.get('projectId') || '');
  const agreementVersionId = String(form.get('agreementVersionId') || '');
  const dueDate = String(form.get('dueDate') || '');
  const reference = String(form.get('reference') || '');
  const idempotencyKey = String(form.get('idempotencyKey') || '');
  const participantIds = form.getAll('participantId').map(String);
  const amounts = form.getAll('amount').map(String);

  const parsed = capitalCallSchema.safeParse({
    organizationId,
    projectId,
    agreementVersionId,
    dueDate,
    reference,
    idempotencyKey,
    lines: participantIds.map((participantId, i) => ({ participantId, amount: amounts[i] ?? '' })),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات طلب رأس المال غير صحيحة');

  const minorAmounts = parsed.data.lines.map((line) => parseMajorUnitsToMinor(line.amount, 'EGP'));
  const supabase = await createClient();
  const { error } = await supabase.rpc('create_capital_call', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_agreement_version_id: parsed.data.agreementVersionId,
    p_due_date: parsed.data.dueDate,
    p_reference: parsed.data.reference || null,
    p_participant_ids: parsed.data.lines.map((line) => line.participantId),
    p_amounts: minorAmounts,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر إصدار طلب رأس المال. تحقق من الالتزامات وحاول مجددًا.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function recordContribution(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = contributionSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    participantId: form.get('participantId'),
    agreementVersionId: form.get('agreementVersionId'),
    capitalCallId: form.get('capitalCallId'),
    amount: form.get('amount'),
    currency: form.get('currency'),
    occurredOn: form.get('occurredOn'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات المساهمة غير صحيحة');

  const minorAmount = parseMajorUnitsToMinor(parsed.data.amount, parsed.data.currency);
  const supabase = await createClient();
  const { error } = await supabase.rpc('record_contribution', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_participant_id: parsed.data.participantId,
    p_agreement_version_id: parsed.data.agreementVersionId,
    p_capital_call_id: parsed.data.capitalCallId,
    p_amount_minor_units: minorAmount,
    p_currency: parsed.data.currency,
    p_occurred_on: parsed.data.occurredOn,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل المساهمة. تحقق من المبلغ والطلب وحاول مجددًا.');
  refreshProject(parsed.data.projectId);
  return {};
}
