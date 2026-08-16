'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/shared/supabase/server';
import type { ActionState } from '@/features/auth/actions';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import { parseMajorUnitsToMinor } from '@/shared/money';
import {
  achieveMilestoneSchema,
  attachPaymentEvidenceSchema,
  budgetApproveSchema,
  budgetCreateSchema,
  budgetDeleteDraftSchema,
  budgetLine,
  budgetSupersedeSchema,
  decideExceptionSchema,
  fxConversionSchema,
  fxSnapshotSchema,
  milestoneSchema,
  obligationScheduleSchema,
  obligationTermsSchema,
  openDisputeSchema,
  openExceptionSchema,
  approvalPolicySchema,
  orgReportingCurrencySchema,
  resolveDisputeSchema,
  resubmitExceptionSchema,
  retentionReleaseSchema,
  taxTreatmentSchema,
} from './schema';

function refreshProject(projectId: string) {
  revalidatePath('/');
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/costs`);
  revalidatePath(`/projects/${projectId}/budget`);
  revalidatePath(`/projects/${projectId}/integrity`);
}

function domainError(prev: ActionState, message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('idempotency key payload mismatch')) {
    return commandFailureState(prev, 'تعذرت إعادة المحاولة لأن مفتاح العملية استُخدم سابقًا لبيانات مختلفة. حدّث الصفحة وحاول من جديد.');
  }
  if (text.includes('retention must be strictly less')) {
    return commandFailureState(prev, 'قيمة الحجز يجب أن تكون أقل من إجمالي الالتزام.');
  }
  if (text.includes('scheduled total exceeds')) {
    return commandFailureState(prev, 'إجمالي بنود الجدولة يتجاوز مبلغ الالتزام.');
  }
  if (text.includes('scheduled retention exceeds')) {
    return commandFailureState(prev, 'بنود حجز الضمان تتجاوز الحجز المعلن في الشروط.');
  }
  if (text.includes('only be set while the obligation is a draft') || text.includes('only be set while')) {
    return commandFailureState(prev, 'لا يمكن تعديل الشروط أو الجدولة بعد اعتماد الالتزام.');
  }
  if (text.includes('an achieved milestone is immutable')) {
    return commandFailureState(prev, 'الإنجاز المعتمد حقيقة مقفلة ولا يمكن تعديله.');
  }
  if (text.includes('a dispute requires an authorized obligation')) {
    return commandFailureState(prev, 'لا يمكن فتح نزاع إلا على التزام معتمد.');
  }
  if (text.includes('tiered approval requires')) {
    return commandFailureState(prev, 'سياسة الاعتماد المتدرج تتطلب عددًا أكبر من المعتمدين المستقلين لهذا المبلغ.');
  }
  if (text.includes('approver already signed')) {
    return commandFailureState(prev, 'وقّعت هذا الموضوع مسبقًا؛ يلزم معتمد مختلف.');
  }
  if (text.includes('maker/checker')) {
    return commandFailureState(prev, 'فصل الصلاحيات: لا يجوز لنفس الشخص إعداد القرار واعتماده.');
  }
  if (text.includes('budget ceiling')) {
    return commandFailureState(prev, 'تجاوز سقف الموازنة. يلزم استثناء موازنة معتمد قبل الاعتماد.');
  }
  if (text.includes('approved budget periods must not overlap')) {
    return commandFailureState(prev, 'فترات الموازنات المعتمدة لا يجوز أن تتداخل لنفس المشروع.');
  }
  if (text.includes('an approved budget is immutable')) {
    return commandFailureState(prev, 'الموازنة المعتمدة لا تُعدَّل؛ أنشئ مراجعة جديدة بدلًا من ذلك.');
  }
  if (text.includes('budget lines can only change while the budget is a draft')) {
    return commandFailureState(prev, 'لا يمكن تعديل بنود موازنة معتمدة أو مستبدلة.');
  }
  if (text.includes('budget exception currency must match')) {
    return commandFailureState(prev, 'عملة استثناء الموازنة يجب أن تطابق عملة الموازنة نفسها.');
  }
  if (text.includes('payment blocked: obligation is under an open dispute')) {
    return commandFailureState(prev, 'الدفع محظور لوجود نزاع مفتوح على هذا الالتزام.');
  }
  if (text.includes('retention withheld')) {
    return commandFailureState(prev, 'المبلغ يتجاوز المستحق القابل للدفع؛ جزء منه محجوز كضمان لم يُفرج عنه بعد.');
  }
  if (text.includes('retention release exceeds')) {
    return commandFailureState(prev, 'الإفراج يتجاوز قيمة الحجز المعلنة.');
  }
  if (text.includes('retention release milestone')) {
    return commandFailureState(prev, 'إنجاز الإفراج يجب أن يكون محققًا وينتمي لنفس مشروع الالتزام.');
  }
  if (text.includes('approval policy requires evidence')) {
    return commandFailureState(prev, 'سياسة الاعتماد تتطلب مستندًا مرجعيًا لهذا الإجراء.');
  }
  if (text.includes('conversion rate must be a positive rational')) {
    return commandFailureState(prev, 'سعر التحويل يجب أن يكون كسرًا موجبًا.');
  }
  if (text.includes('rate snapshot date cannot be after')) {
    return commandFailureState(prev, 'تاريخ لقطة السعر لا يجوز أن يلي تاريخ التحويل.');
  }
  if (text.includes('forbidden: organization owner required')) {
    return commandFailureState(prev, 'هذا الإجراء يتطلب صلاحية مالك المنظمة.');
  }
  return commandFailureState(prev, fallback);
}

const bigintTextOrNull = (value: string | undefined): string | null => {
  if (!value || !/^[1-9][0-9]*$/.test(value)) return null;
  return value;
};

/** Exact minor-unit parse that permits zero (retention may be zero). */
function parseNonNegativeMajorUnitsToMinor(value: string, currency: string): string {
  const trimmed = value.trim();
  if (/^0(\.0+)?$/.test(trimmed)) {
    return '0';
  }
  return parseMajorUnitsToMinor(trimmed, currency);
}

// ---------------------------------------------------------------- F3
export async function createMilestone(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = milestoneSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات الإنجاز غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f3_create_project_milestone', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_code: parsed.data.code,
    p_label_ar: parsed.data.labelAr,
    p_planned_date: parsed.data.plannedDate,
    p_evidence_reference: parsed.data.evidenceReference || null,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر إنشاء الإنجاز. تحقق من الرمز والصلاحيات.');
  refreshProject(parsed.data.projectId);
  return commandSuccessState(prev);
}

export async function achieveMilestone(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = achieveMilestoneSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات الاعتماد غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f3_achieve_project_milestone', {
    p_organization_id: parsed.data.organizationId,
    p_milestone_id: parsed.data.milestoneId,
    p_achieved_date: parsed.data.achievedDate,
    p_evidence_reference: parsed.data.evidenceReference || null,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر اعتماد الإنجاز.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function setObligationTerms(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = obligationTermsSchema.safeParse({
    organizationId: form.get('organizationId'),
    obligationId: form.get('obligationId'),
    currency: form.get('currency'),
    termsType: form.get('termsType'),
    dueDate: form.get('dueDate'),
    netDays: form.get('netDays'),
    retention: form.get('retention'),
    evidenceReference: form.get('evidenceReference'),
    notes: form.get('notes'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات الشروط غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f3_set_obligation_terms', {
    p_organization_id: parsed.data.organizationId,
    p_obligation_id: parsed.data.obligationId,
    p_terms_type: parsed.data.termsType,
    p_due_date: parsed.data.dueDate || null,
    p_net_days: parsed.data.netDays ? Number(parsed.data.netDays) : null,
    p_retention_minor_units: parseNonNegativeMajorUnitsToMinor(parsed.data.retention, parsed.data.currency),
    p_evidence_reference: parsed.data.evidenceReference || null,
    p_notes: parsed.data.notes || null,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر حفظ شروط الدفع. لا يمكن تعديل التزام معتمد.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function setObligationSchedule(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = obligationScheduleSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات الجدولة غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f3_set_obligation_schedule', {
    p_organization_id: parsed.data.organizationId,
    p_obligation_id: parsed.data.obligationId,
    p_lines: parsed.data.linesJson,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر حفظ جدولة الدفع. لا يمكن تعديل التزام معتمد.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function openDispute(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = openDisputeSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات النزاع غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f3_open_obligation_dispute', {
    p_organization_id: parsed.data.organizationId,
    p_obligation_id: parsed.data.obligationId,
    p_reason: parsed.data.reason,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر فتح النزاع.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function resolveDispute(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = resolveDisputeSchema.safeParse({
    organizationId: form.get('organizationId'),
    disputeId: form.get('disputeId'),
    resolutionNote: form.get('resolutionNote'),
    evidenceReference: form.get('evidenceReference'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات التسوية غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f3_resolve_obligation_dispute', {
    p_organization_id: parsed.data.organizationId,
    p_dispute_id: parsed.data.disputeId,
    p_resolution_note: parsed.data.resolutionNote,
    p_evidence_reference: parsed.data.evidenceReference || null,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر تسوية النزاع. يلزم مالك لم يفتح النزاع.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function releaseRetention(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = retentionReleaseSchema.safeParse({
    organizationId: form.get('organizationId'),
    obligationId: form.get('obligationId'),
    currency: form.get('currency'),
    amount: form.get('amount'),
    releaseDate: form.get('releaseDate'),
    reason: form.get('reason'),
    evidenceReference: form.get('evidenceReference'),
    milestoneId: form.get('milestoneId'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات الإفراج غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f3_release_obligation_retention', {
    p_organization_id: parsed.data.organizationId,
    p_obligation_id: parsed.data.obligationId,
    p_amount_minor_units: parseMajorUnitsToMinor(parsed.data.amount, parsed.data.currency),
    p_release_date: parsed.data.releaseDate,
    p_reason: parsed.data.reason,
    p_milestone_id: parsed.data.milestoneId || null,
    p_evidence_reference: parsed.data.evidenceReference || null,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر الإفراج عن الحجز. يلزم التزام معتمد وصلاحية مالك.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

// ---------------------------------------------------------------- F4
export async function createBudget(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = budgetCreateSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات الموازنة غير صحيحة');
  let rawLines: unknown;
  try {
    rawLines = JSON.parse(parsed.data.linesJson);
  } catch {
    return commandFailureState(prev, 'بنود الموازنة ليست JSON صالحًا.');
  }
  if (!Array.isArray(rawLines) || rawLines.length === 0) {
    return commandFailureState(prev, 'أدخل بند موازنة واحدًا على الأقل.');
  }
  const lines = [];
  for (let i = 0; i < rawLines.length; i += 1) {
    const parsedLine = budgetLine.safeParse(rawLines[i]);
    if (!parsedLine.success) {
      return commandFailureState(prev, `بند الموازنة رقم ${i + 1} غير صالح: معالجة التكلفة والمبلغ بالوحدات الصغرى مطلوبان.`);
    }
    lines.push(parsedLine.data);
  }
  const supabase = await createClient();
  const { error } = await supabase.rpc('f4_create_project_budget', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_period_start: parsed.data.periodStart,
    p_period_end: parsed.data.periodEnd,
    p_budget_type: parsed.data.budgetType,
    p_currency: parsed.data.currency,
    p_description: parsed.data.description,
    p_evidence_reference: parsed.data.evidenceReference || null,
    p_lines: lines.map((line) => ({
      cost_treatment: line.cost_treatment,
      amount_minor_units: line.amount_minor_units,
      notes: line.notes || null,
    })),
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر إنشاء الموازنة. تأكد من الفترة والعملة والبنود.');
  refreshProject(parsed.data.projectId);
  return commandSuccessState(prev);
}

export async function approveBudget(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = budgetApproveSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات الاعتماد غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f4_approve_project_budget', {
    p_organization_id: parsed.data.organizationId,
    p_budget_id: parsed.data.budgetId,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر اعتماد الموازنة. يلزم مالك لم يعدّ الموازنة.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function supersedeBudget(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = budgetSupersedeSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات المراجعة غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f4_supersede_project_budget', {
    p_organization_id: parsed.data.organizationId,
    p_budget_id: parsed.data.budgetId,
    p_description: parsed.data.description,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر فتح مراجعة الموازنة.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function deleteDraftBudget(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = budgetDeleteDraftSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات الحذف غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f4_delete_draft_budget', {
    p_organization_id: parsed.data.organizationId,
    p_budget_id: parsed.data.budgetId,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر حذف مسودة الموازنة.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

// ---------------------------------------------------------------- F5
export async function setApprovalPolicy(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = approvalPolicySchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات السياسة غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f5_set_approval_policy', {
    p_organization_id: parsed.data.organizationId,
    p_policy_domain: parsed.data.policyDomain,
    p_threshold_minor_units: bigintTextOrNull(parsed.data.thresholdMinorUnits),
    p_currency: parsed.data.currency || null,
    p_evidence_required: parsed.data.evidenceRequired === 'true',
    p_active: parsed.data.active === 'true',
    p_min_approvers: Number(parsed.data.minApprovers),
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر حفظ سياسة الاعتماد. يلزم صلاحية مالك.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function openApprovalException(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = openExceptionSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    exceptionDomain: form.get('exceptionDomain'),
    subjectType: form.get('subjectType'),
    subjectId: form.get('subjectId'),
    amountMinorUnits: form.get('amountMinorUnits'),
    currency: form.get('currency'),
    reason: form.get('reason'),
    evidenceReference: form.get('evidenceReference'),
    severity: form.get('severity'),
    ownerId: form.get('ownerId'),
    dueDate: form.get('dueDate'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات الاستثناء غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f5_open_approval_exception', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_exception_domain: parsed.data.exceptionDomain,
    p_subject_type: parsed.data.subjectType,
    p_subject_id: parsed.data.subjectId || null,
    p_amount_minor_units: bigintTextOrNull(parsed.data.amountMinorUnits),
    p_currency: parsed.data.currency || null,
    p_reason: parsed.data.reason,
    p_evidence_reference: parsed.data.evidenceReference || null,
    p_severity: parsed.data.severity,
    p_owner_id: parsed.data.ownerId || null,
    p_due_date: parsed.data.dueDate || null,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر فتح الاستثناء.');
  refreshProject(parsed.data.projectId);
  return commandSuccessState(prev);
}

export async function decideApprovalException(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = decideExceptionSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات القرار غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f5_decide_approval_exception', {
    p_organization_id: parsed.data.organizationId,
    p_exception_id: parsed.data.exceptionId,
    p_decision: parsed.data.decision,
    p_decision_note: parsed.data.decisionNote,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر تسجيل القرار. يلزم مالك لم يفتح الاستثناء.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function resubmitApprovalException(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = resubmitExceptionSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات إعادة التقديم غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f5_resubmit_exception', {
    p_organization_id: parsed.data.organizationId,
    p_exception_id: parsed.data.exceptionId,
    p_reason: parsed.data.reason,
    p_evidence_reference: parsed.data.evidenceReference || null,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر إعادة تقديم الاستثناء. يلزم استثناء مرفوض.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function attachPaymentEvidence(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = attachPaymentEvidenceSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات المستند غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f5_attach_payment_evidence', {
    p_organization_id: parsed.data.organizationId,
    p_payment_proposal_id: parsed.data.paymentProposalId,
    p_evidence_reference: parsed.data.evidenceReference,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر إرفاق المستند بمقترح الدفع.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

// ---------------------------------------------------------------- F6
export async function recordFxSnapshot(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = fxSnapshotSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات سعر الصرف غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f6_record_fx_rate_snapshot', {
    p_organization_id: parsed.data.organizationId,
    p_base_currency: parsed.data.baseCurrency,
    p_quote_currency: parsed.data.quoteCurrency,
    p_rate_numerator: parsed.data.rateNumerator,
    p_rate_denominator: parsed.data.rateDenominator,
    p_rate_date: parsed.data.rateDate,
    p_rate_source: parsed.data.rateSource,
    p_provider_reference: parsed.data.providerReference || null,
    p_notes: parsed.data.notes || null,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر تسجيل لقطة سعر الصرف.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function recordFxConversion(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = fxConversionSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    sourceAmountMinorUnits: form.get('sourceAmountMinorUnits'),
    rateSnapshotId: form.get('rateSnapshotId'),
    conversionDate: form.get('conversionDate'),
    purpose: form.get('purpose'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات التحويل غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f6_record_fx_conversion_by_snapshot', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId || null,
    p_source_amount_minor_units: parsed.data.sourceAmountMinorUnits,
    p_rate_snapshot_id: parsed.data.rateSnapshotId,
    p_conversion_date: parsed.data.conversionDate,
    p_purpose: parsed.data.purpose,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر تسجيل التحويل. تحقق من اللقطة والتاريخ.');
  refreshProject(String(form.get('projectId') || ''));
  return commandSuccessState(prev);
}

export async function setOrgReportingCurrency(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = orgReportingCurrencySchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات عملة التقارير غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f6_set_org_reporting_currency', {
    p_organization_id: parsed.data.organizationId,
    p_reporting_currency: parsed.data.reportingCurrency,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر تحديث عملة التقارير. يلزم صلاحية مالك.');
  revalidatePath('/');
  return commandSuccessState(prev);
}

export async function registerTaxTreatment(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = taxTreatmentSchema.safeParse({
    organizationId: form.get('organizationId'),
    taxDomain: form.get('taxDomain'),
    taxName: form.get('taxName'),
    appliesTo: form.get('appliesTo'),
    treatmentStatus: form.get('treatmentStatus'),
    authority: form.get('authority'),
    effectiveFrom: form.get('effectiveFrom'),
    effectiveTo: form.get('effectiveTo'),
    notes: form.get('notes'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات المعالجة الضريبية غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('f6_register_tax_treatment', {
    p_organization_id: parsed.data.organizationId,
    p_tax_domain: parsed.data.taxDomain,
    p_tax_name: parsed.data.taxName,
    p_applies_to: parsed.data.appliesTo,
    p_treatment_status: parsed.data.treatmentStatus,
    p_authority: parsed.data.authority || null,
    p_effective_from: parsed.data.effectiveFrom,
    p_effective_to: parsed.data.effectiveTo || null,
    p_notes: parsed.data.notes,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(prev, error.message, 'تعذر تسجيل المعالجة الضريبية. يلزم صلاحية مالك.');
  revalidatePath('/');
  return commandSuccessState(prev);
}
