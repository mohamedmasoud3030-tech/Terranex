'use server';

import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';
import {
  acceptUatTaskSchema,
  compactOpeningRowSlots,
  approveOpeningImportSchema,
  openingImportRowSchema,
  recordCheckpointSchema,
  recordUatExecutionSchema,
  registerUatTaskSchema,
  rejectOpeningImportSchema,
  rejectUatTaskSchema,
  resolveExceptionSchema,
  reviewOpeningImportSchema,
  setMembershipStatusSchema,
  signOffCheckpointSchema,
  stageOpeningImportSchema,
  validateOpeningImportSchema,
} from './schema';

function fail(message: string): ActionState {
  return { error: message };
}

function refresh(projectId: string) {
  revalidatePath('/');
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/pilot`);
}

function domainError(message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('idempotency key payload mismatch')) return fail('مفتاح إعادة المحاولة استُخدم لبيانات مختلفة. حدّث الصفحة وحاول مجددًا.');
  if (text.includes('forbidden: organization owner required')) return fail('هذا الإجراء يتطلب صلاحية مالك المنظمة.');
  if (text.includes('forbidden')) return fail('لا تملك صلاحية على هذه المنظمة. قد تكون عضويتك أُلغيت.');
  if (text.includes('unsupported opening import schema version')) return fail('إصدار قالب الاستيراد غير مدعوم.');
  if (text.includes('sha-256 source file checksum')) return fail('بصمة SHA-256 لملف المصدر مطلوبة.');
  if (text.includes('columns length mismatch')) return fail('عدد القيم في الأعمدة غير متطابق. راجع الملف المصدر.');
  if (text.includes('exceeds the 5000 row limit')) return fail('عدد سطور الملف يتجاوز الحد المسموح (٥٠٠٠ سطر).');
  if (text.includes('only a DRAFT opening import')) return fail('لا يمكن التحقق إلا من استيراد في حالة مسودة.');
  if (text.includes('only a VALIDATED opening import')) return fail('لا يمكن ترشيح الاستيراد للاعتماد قبل نجاح التحقق.');
  if (text.includes('ready for approval can be approved')) return fail('يجب مراجعة الاستيراد وترشيحه للاعتماد أولًا.');
  if (text.includes('s7_opening_import_maker_checker_check')) return fail('من أعدّ الاستيراد لا يمكنه اعتماده. يلزم معتمد مختلف.');
  if (text.includes('already has an active posted opening import')) return fail('المشروع لديه استيراد افتتاحي مُرحَّل نشط. اعكسه أولًا قبل استيراد بديل.');
  if (text.includes('OPEN accounting period')) return fail('الترحيل يتطلب فترة محاسبية مفتوحة واحدة تغطي التاريخ المختار.');
  if (text.includes('does not reconcile exactly')) return fail('الاستيراد لا يوازن تمامًا. لا يمكن الاعتماد.');
  if (text.includes('control totals changed since validation')) return fail('تغيّرت مجاميع الرقابة بعد التحقق. أعد التحقق.');
  if (text.includes('still has rejected rows')) return fail('لا يمكن الاعتماد وبالاستيراد سطور مرفوضة. صحّحها في المصدر وأعد الاستيراد.');
  if (text.includes('use linked reversal')) return fail('الاستيراد المُرحَّل يُصحَّح بالعكس المرتبط فقط.');
  if (text.includes('dependent later postings')) return fail('توجد قيود لاحقة تعتمد على الرصيد الافتتاحي. اعكسها أولًا.');
  if (text.includes('frozen once the import leaves DRAFT')) return fail('سطور الاستيراد مجمدة بعد مغادرة حالة المسودة.');
  if (text.includes('unsupported reconciliation checkpoint')) return fail('نقطة المطابقة غير مدعومة.');
  if (text.includes('requires an explicit exception severity')) return fail('أي فرق غير صفري يتطلب تحديد درجة خطورة ومالك للاستثناء.');
  if (text.includes('exception owner must be an active member')) return fail('مالك الاستثناء يجب أن يكون عضوًا نشطًا في المنظمة.');
  if (text.includes('unresolved exception')) return fail('لا يمكن الاعتماد قبل معالجة استثناء الفرق.');
  if (text.includes('s7_checkpoint_maker_checker_check')) return fail('من سجّل نقطة المطابقة لا يمكنه اعتمادها. يلزم معتمد مختلف.');
  if (text.includes('already signed off')) return fail('تم اعتماد نقطة المطابقة بالفعل.');
  if (text.includes('at least one active owner')) return fail('لا يمكن ترك المنظمة بلا مالك نشط واحد على الأقل.');
  if (text.includes('membership not found')) return fail('العضوية غير موجودة في هذه المنظمة.');
  if (text.includes('only an executed UAT task')) return fail('لا يمكن قبول أو رفض مهمة اختبار لم تُنفَّذ بعد.');
  if (text.includes('must not be its executor')) return fail('من نفّذ مهمة الاختبار لا يمكنه قبولها أو رفضها. يلزم مراجع مختلف.');
  if (text.includes('accepted UAT task is immutable')) return fail('مهمة اختبار مقبولة لا يمكن تعديلها.');
  return fail(fallback);
}

async function rpc(name: string, args: Record<string, unknown>) {
  const s = await createClient();
  return s.rpc(name, args) as unknown as Promise<{ data: unknown; error: { message: string } | null }>;
}

/** Empty optional identifiers and selections travel to PostgreSQL as SQL null. */
function orNull(value: string | undefined): string | null {
  return value && value.length > 0 ? value : null;
}

export async function stageOpeningImportAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = stageOpeningImportSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات الاستيراد الافتتاحي غير صحيحة');

  const mappingCodes = form.getAll('mappingCode').map(String);
  const partyIds = form.getAll('partyId').map(String);
  const cashAccountIds = form.getAll('cashAccountId').map(String);
  const debits = form.getAll('debit').map(String);
  const credits = form.getAll('credit').map(String);
  const descriptions = form.getAll('description').map(String);
  const rowCount = mappingCodes.length;
  if (rowCount === 0) return fail('يجب إدخال سطر افتتاحي واحد على الأقل.');
  if ([partyIds, cashAccountIds, debits, credits, descriptions].some((column) => column.length !== rowCount)) {
    return fail('عدد القيم في الأعمدة غير متطابق. راجع الملف المصدر.');
  }

  const rows = compactOpeningRowSlots(mappingCodes.map((mappingCode, index) => ({
    mappingCode,
    partyId: partyIds[index] ?? '',
    cashAccountId: cashAccountIds[index] ?? '',
    debit: debits[index] ?? '',
    credit: credits[index] ?? '',
    description: descriptions[index] ?? '',
  })));
  if (rows.length === 0) return fail('يجب إدخال سطر افتتاحي واحد على الأقل.');
  const rowsParsed = openingImportRowSchema.array().safeParse(rows);
  if (!rowsParsed.success) return fail(rowsParsed.error.issues[0]?.message ?? 'سطور الملف الافتتاحي غير صحيحة');

  const input = parsed.data;
  const { error } = await rpc('s7_stage_opening_import', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_schema_version: input.schemaVersion,
    p_source_file_name: input.sourceFileName,
    p_source_file_checksum: input.sourceFileChecksum,
    p_mapping_codes: rowsParsed.data.map((row) => row.mappingCode),
    p_party_ids: rowsParsed.data.map((row) => orNull(row.partyId)),
    p_cash_account_ids: rowsParsed.data.map((row) => orNull(row.cashAccountId)),
    p_debits: rowsParsed.data.map((row) => row.debit),
    p_credits: rowsParsed.data.map((row) => row.credit),
    p_descriptions: rowsParsed.data.map((row) => row.description),
    p_declared_debit_total: input.declaredDebitTotal,
    p_declared_credit_total: input.declaredCreditTotal,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تجهيز الاستيراد الافتتاحي.');
  refresh(input.projectId);
  return {};
}

export async function validateOpeningImportAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = validateOpeningImportSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات التحقق غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_validate_opening_import', {
    p_organization_id: input.organizationId,
    p_import_id: input.importId,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر التحقق من الاستيراد الافتتاحي.');
  refresh(input.projectId);
  return {};
}

export async function reviewOpeningImportAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = reviewOpeningImportSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات المراجعة غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_review_opening_import', {
    p_organization_id: input.organizationId,
    p_import_id: input.importId,
    p_review_notes: orNull(input.reviewNotes),
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر ترشيح الاستيراد للاعتماد.');
  refresh(input.projectId);
  return {};
}

export async function approveOpeningImportAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = approveOpeningImportSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات الاعتماد غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_approve_opening_import', {
    p_organization_id: input.organizationId,
    p_import_id: input.importId,
    p_posting_date: input.postingDate,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر اعتماد وترحيل الاستيراد الافتتاحي.');
  refresh(input.projectId);
  return {};
}

export async function rejectOpeningImportAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = rejectOpeningImportSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات الرفض غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_reject_opening_import', {
    p_organization_id: input.organizationId,
    p_import_id: input.importId,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر رفض الاستيراد الافتتاحي.');
  refresh(input.projectId);
  return {};
}

export async function recordCheckpointAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = recordCheckpointSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات نقطة المطابقة غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_record_reconciliation_checkpoint', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_checkpoint_code: input.checkpointCode,
    p_as_of_date: input.asOfDate,
    p_external_value_minor_units: input.externalValue,
    p_external_source_reference: input.externalSourceReference,
    p_external_evidence_reference: input.externalEvidenceReference,
    p_exception_owner_id: orNull(input.exceptionOwnerId),
    p_exception_severity: orNull(input.exceptionSeverity),
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل نقطة المطابقة.');
  refresh(input.projectId);
  return {};
}

export async function resolveExceptionAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = resolveExceptionSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات معالجة الاستثناء غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_resolve_reconciliation_exception', {
    p_organization_id: input.organizationId,
    p_exception_id: input.exceptionId,
    p_resolution: input.resolution,
    p_evidence_reference: input.evidenceReference,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر إغلاق استثناء المطابقة.');
  refresh(input.projectId);
  return {};
}

export async function signOffCheckpointAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = signOffCheckpointSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات الاعتماد غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_sign_off_reconciliation_checkpoint', {
    p_organization_id: input.organizationId,
    p_checkpoint_id: input.checkpointId,
    p_evidence_reference: input.evidenceReference,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر اعتماد نقطة المطابقة.');
  refresh(input.projectId);
  return {};
}

export async function setMembershipStatusAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = setMembershipStatusSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات تغيير العضوية غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_set_membership_status', {
    p_organization_id: input.organizationId,
    p_user_id: input.userId,
    p_status: input.status,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تغيير حالة العضوية.');
  refresh(input.projectId);
  return {};
}

export async function registerUatTaskAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = registerUatTaskSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات مهمة الاختبار غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_register_uat_task', {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_task_code: input.taskCode,
    p_title: input.title,
    p_expected_outcome: input.expectedOutcome,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل مهمة اختبار القبول.');
  refresh(input.projectId);
  return {};
}

export async function recordUatExecutionAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = recordUatExecutionSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات تنفيذ الاختبار غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_record_uat_execution', {
    p_organization_id: input.organizationId,
    p_task_id: input.taskId,
    p_evidence_reference: input.evidenceReference,
    p_notes: orNull(input.notes),
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل تنفيذ مهمة الاختبار.');
  refresh(input.projectId);
  return {};
}

export async function acceptUatTaskAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = acceptUatTaskSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات قبول الاختبار غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_accept_uat_task', {
    p_organization_id: input.organizationId,
    p_task_id: input.taskId,
    p_acceptance_evidence_reference: input.acceptanceEvidenceReference,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل قبول العميل لمهمة الاختبار.');
  refresh(input.projectId);
  return {};
}

export async function rejectUatTaskAction(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = rejectUatTaskSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات رفض الاختبار غير صحيحة');
  const input = parsed.data;
  const { error } = await rpc('s7_reject_uat_task', {
    p_organization_id: input.organizationId,
    p_task_id: input.taskId,
    p_rejection_reason: input.rejectionReason,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر تسجيل رفض مهمة الاختبار.');
  refresh(input.projectId);
  return {};
}
