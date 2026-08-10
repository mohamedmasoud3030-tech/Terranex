'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/shared/supabase/server';
import type { ActionState } from '@/features/auth/actions';
import {
  activateVersionSchema,
  agreementDraftSchema,
  capitalCallSchema,
  contributionSchema,
  partySchema,
} from './schema';

function fail(message: string): ActionState {
  return { error: message };
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
  revalidatePath('/');
  return {};
}

export async function addParticipant(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = z_safeParticipant(form);
  if (!parsed.ok) return fail(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc('add_project_participant', {
    p_organization_id: parsed.value.organizationId,
    p_project_id: parsed.value.projectId,
    p_party_id: parsed.value.partyId,
  });
  if (error) return fail('تعذر إضافة المشارك. قد يكون الطرف من منظمة أخرى.');
  revalidatePath('/');
  return {};
}

export async function createAgreementDraft(_: ActionState, form: FormData): Promise<ActionState> {
  const organizationId = String(form.get('organizationId') || '');
  const projectId = String(form.get('projectId') || '');
  const effectiveDate = String(form.get('effectiveDate') || '');
  const participantIds = form.getAll('participantId').map(String);
  const commitments = form.getAll('commitmentMinorUnits').map(Number);

  const parsed = agreementDraftSchema.safeParse({
    organizationId,
    projectId,
    effectiveDate,
    participants: participantIds.map((participantId, i) => ({
      participantId,
      commitmentMinorUnits: commitments[i],
    })),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات الاتفاقية غير صحيحة');

  const supabase = await createClient();
  const { error } = await supabase.rpc('create_agreement_draft', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_effective_date: parsed.data.effectiveDate,
    p_participant_ids: parsed.data.participants.map((p) => p.participantId),
    p_commitments: parsed.data.participants.map((p) => p.commitmentMinorUnits),
  });
  if (error) return fail('تعذر حفظ مسودة الاتفاقية. راجع الالتزامات والمشاركين.');
  revalidatePath('/');
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
  if (error) return fail('تعذر تفعيل الاتفاقية. لا يمكن تفعيل نسخة غير مسودة أو توجد نسخة مفعلة.');
  revalidatePath('/');
  return {};
}

export async function createCapitalCall(_: ActionState, form: FormData): Promise<ActionState> {
  const organizationId = String(form.get('organizationId') || '');
  const projectId = String(form.get('projectId') || '');
  const agreementVersionId = String(form.get('agreementVersionId') || '');
  const dueDate = String(form.get('dueDate') || '');
  const reference = String(form.get('reference') || '');
  const participantIds = form.getAll('participantId').map(String);
  const amounts = form.getAll('amountMinorUnits').map(Number);

  const parsed = capitalCallSchema.safeParse({
    organizationId,
    projectId,
    agreementVersionId,
    dueDate,
    reference,
    lines: participantIds.map((participantId, i) => ({ participantId, amountMinorUnits: amounts[i] })),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات طلب رأس المال غير صحيحة');

  const supabase = await createClient();
  const { error } = await supabase.rpc('create_capital_call', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_agreement_version_id: parsed.data.agreementVersionId,
    p_due_date: parsed.data.dueDate,
    p_reference: parsed.data.reference || null,
    p_participant_ids: parsed.data.lines.map((l) => l.participantId),
    p_amounts: parsed.data.lines.map((l) => l.amountMinorUnits),
  });
  if (error) return fail('تعذر إصدار طلب رأس المال. قد يتجاوز الالتزام.');
  revalidatePath('/');
  return {};
}

export async function recordContribution(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = contributionSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    participantId: form.get('participantId'),
    agreementVersionId: form.get('agreementVersionId'),
    capitalCallId: form.get('capitalCallId'),
    contributionMinorUnits: Number(form.get('contributionMinorUnits')),
    currency: form.get('currency'),
    occurredOn: form.get('occurredOn'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات المساهمة غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('record_contribution', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_participant_id: parsed.data.participantId,
    p_agreement_version_id: parsed.data.agreementVersionId,
    p_capital_call_id: parsed.data.capitalCallId,
    p_amount_minor_units: parsed.data.contributionMinorUnits,
    p_currency: parsed.data.currency,
    p_occurred_on: parsed.data.occurredOn,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return fail('تعذر تسجيل المساهمة. تحقق من المبلغ والطلب وعدم التكرار.');
  revalidatePath('/');
  return {};
}

// Small local validator reused by the participant action (avoids an extra export).
function z_safeParticipant(form: FormData) {
  const organizationId = String(form.get('organizationId') || '');
  const projectId = String(form.get('projectId') || '');
  const partyId = String(form.get('partyId') || '');
  const ok =
    /^[0-9a-f]{8}-[0-9a-f-]{27}[0-9a-f]$/i.test(organizationId) &&
    /^[0-9a-f]{8}-[0-9a-f-]{27}[0-9a-f]$/i.test(projectId) &&
    /^[0-9a-f]{8}-[0-9a-f-]{27}[0-9a-f]$/i.test(partyId);
  return ok
    ? { ok: true as const, value: { organizationId, projectId, partyId } }
    : { ok: false as const, error: 'معرّفات غير صحيحة' };
}
