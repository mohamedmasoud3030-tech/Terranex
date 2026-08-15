'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/shared/supabase/server';
import type { ActionState } from '@/features/auth/actions';
import { parseMajorUnitsToMinor, parseSignedMajorUnitsToMinor } from '@/shared/money';
import {
  bankImportSchema,
  cashAccountSchema,
  contributionAttributionSchema,
  obligationSchema,
  authorizeObligationSchema,
  approvePaymentSchema,
  paymentSchema,
  reconcileSchema,
  reversalSchema,
  voidReconciliationSchema,
} from './schema';

function fail(message: string): ActionState {
  return { error: message };
}

function refreshProject(projectId: string) {
  revalidatePath('/');
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/costs`);
  revalidatePath(`/projects/${projectId}/cash`);
  revalidatePath(`/projects/${projectId}/intake`);
}

function domainError(message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('idempotency key payload mismatch')) {
    return fail('تعذر إعادة المحاولة لأن مفتاح العملية استُخدم سابقًا لبيانات مختلفة. حدّث الصفحة وحاول من جديد.');
  }
  if (text.includes('payment exceeds remaining payable')) {
    return fail('المبلغ يتجاوز المتبقي المستحق لهذا الالتزام.');
  }
  if (text.includes('payment exceeds available cash')) {
    return fail('الرصيد المتاح في الحساب النقدي لا يكفي لهذه الدفعة.');
  }
  if (text.includes('maker/checker')) {
    return fail('لا يجوز لمُعدّ مقترح الدفع اعتماده. يلزم مالك آخر مستقل.');
  }
  if (text.includes('payment proposal is already posted')) {
    return fail('تم اعتماد مقترح الدفع وترحيله بالفعل.');
  }
  if (text.includes('only a draft obligation')) {
    return fail('لا يمكن تعديل التزام بعد اعتماده. استخدم العكس للتصحيح.');
  }
  if (text.includes('duplicate fingerprint')) {
    return fail('هذا السطر مستورد مسبقًا في كشف الحساب (بصمة مكررة).');
  }
  if (text.includes('already reconciled')) {
    return fail('هذه الدفعة أو هذا السطر مربوط بمطابقة نشطة بالفعل.');
  }
  if (text.includes('does not match the payment amount')) {
    return fail('مبلغ السطر البنكي لا يطابق مبلغ الدفعة.');
  }
  if (text.includes('same cash account')) {
    return fail('الدفعة وسطر كشف الحساب يجب أن يكونا على نفس الحساب.');
  }
  if (text.includes('already voided')) {
    return fail('هذه المطابقة ملغاة بالفعل.');
  }
  if (text.includes('already reversed') || text.includes('cannot be reversed')) {
    return fail('لا يمكن عكس هذا القيد مرة أخرى.');
  }
  if (text.includes('reverse payments first')) {
    return fail('لا يمكن عكس الالتزام قبل عكس دفعاته النشطة.');
  }
  if (text.includes('void it first')) {
    return fail('لا يمكن عكس الدفعة قبل إلغاء مطابقتها النشطة.');
  }
  if (text.includes('forbidden: organization owner required')) {
    return fail('هذا الإجراء يتطلب صلاحية مالك المنظمة.');
  }
  return fail(fallback);
}

export async function createCashAccount(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = cashAccountSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('create_project_cash_account', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_name: parsed.data.name,
    p_currency: parsed.data.currency,
  });
  if (error) return domainError(error.message, 'تعذر إنشاء الحساب النقدي. تحقق من البيانات والصلاحيات.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function attachContributionCash(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = contributionAttributionSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('attach_contribution_cash', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_contribution_id: parsed.data.contributionId,
    p_cash_account_id: parsed.data.cashAccountId,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر إسناد المساهمة إلى الحساب النقدي. قد تكون مُسنَدة مسبقًا.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function createObligation(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = obligationSchema.safeParse({
    organizationId: form.get('organizationId'),
    projectId: form.get('projectId'),
    partyId: form.get('partyId'),
    description: form.get('description'),
    amount: form.get('amount'),
    currency: form.get('currency'),
    transactionDate: form.get('transactionDate'),
    costTreatment: form.get('costTreatment'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات الالتزام غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('create_cost_obligation', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_party_id: parsed.data.partyId,
    p_description: parsed.data.description,
    p_amount_minor_units: parseMajorUnitsToMinor(parsed.data.amount, parsed.data.currency),
    p_currency: parsed.data.currency,
    p_transaction_date: parsed.data.transactionDate,
    p_cost_treatment: parsed.data.costTreatment,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر حفظ الالتزام. تحقق من البيانات وحاول مجددًا.');
  refreshProject(parsed.data.projectId);
  return {};
}

export async function deleteObligationDraft(_: ActionState, form: FormData): Promise<ActionState> {
  const organizationId = String(form.get('organizationId') || '');
  const projectId = String(form.get('projectId') || '');
  const obligationId = String(form.get('obligationId') || '');
  if (!organizationId || !projectId || !obligationId) return fail('معرّفات غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('delete_cost_obligation_draft', {
    p_organization_id: organizationId,
    p_obligation_id: obligationId,
  });
  if (error) return domainError(error.message, 'تعذر حذف المسودة. لا يمكن حذف التزام معتمد.');
  refreshProject(projectId);
  return {};
}

export async function authorizeObligation(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = authorizeObligationSchema.safeParse({
    organizationId: form.get('organizationId'),
    obligationId: form.get('obligationId'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('authorize_cost_obligation', {
    p_organization_id: parsed.data.organizationId,
    p_obligation_id: parsed.data.obligationId,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر اعتماد الالتزام. يتطلب ذلك صلاحية مالك المنظمة.');
  refreshProject(String(form.get('projectId') || ''));
  return {};
}

export async function preparePayment(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = paymentSchema.safeParse({
    organizationId: form.get('organizationId'),
    obligationId: form.get('obligationId'),
    cashAccountId: form.get('cashAccountId'),
    amount: form.get('amount'),
    currency: form.get('currency'),
    paymentDate: form.get('paymentDate'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات مقترح الدفع غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('prepare_cost_payment', {
    p_organization_id: parsed.data.organizationId,
    p_obligation_id: parsed.data.obligationId,
    p_cash_account_id: parsed.data.cashAccountId,
    p_amount_minor_units: parseMajorUnitsToMinor(parsed.data.amount, parsed.data.currency),
    p_payment_date: parsed.data.paymentDate,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر إعداد مقترح الدفع. تحقق من الرصيد والمبلغ والفترة.');
  refreshProject(String(form.get('projectId') || ''));
  return {};
}

export async function approvePayment(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = approvePaymentSchema.safeParse({
    organizationId: form.get('organizationId'),
    paymentProposalId: form.get('paymentProposalId'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات اعتماد الدفع غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('approve_cost_payment', {
    p_organization_id: parsed.data.organizationId,
    p_payment_proposal_id: parsed.data.paymentProposalId,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر اعتماد الدفع. يلزم مالك مختلف ورصيد نقدي كافٍ.');
  refreshProject(String(form.get('projectId') || ''));
  return {};
}

/** Deterministic CSV contract for GF-004:
 * one line per row, columns: date,amount,currency,description,provider_reference
 * amount is signed decimal text (negative = money left the account).
 * An optional header row is skipped. Parsing is exact (shared money module);
 * no floating-point arithmetic is performed. */
function parseBankCsv(csv: string): {
  transactionDate: string;
  amount: string;
  currency: string;
  description: string;
  providerReference: string;
}[] {
  const rows = csv
    .split(/\r?\n/)
    .map((row) => row.trim())
    .filter((row) => row.length > 0);
  const lines = rows.filter((row, index) => {
    if (index === 0) {
      const first = row.toLowerCase();
      return !(first.startsWith('date') && first.includes('amount'));
    }
    return true;
  });
  return lines.map((row) => {
    const parts = row.split(',');
    if (parts.length < 4 || parts.length > 5) {
      throw new Error(`سطر غير صالح: يجب أن يحتوي على date,amount,currency,description[,provider_reference]`);
    }
    const [transactionDate, amount, currency, description, providerReference = ''] = parts.map((part) => part.trim());
    return { transactionDate, amount, currency, description, providerReference };
  });
}

export async function importBankStatement(_: ActionState, form: FormData): Promise<ActionState> {
  const organizationId = String(form.get('organizationId') || '');
  const cashAccountId = String(form.get('cashAccountId') || '');
  const idempotencyKey = String(form.get('idempotencyKey') || '');
  const csv = String(form.get('csv') || '');

  let rawLines: ReturnType<typeof parseBankCsv>;
  try {
    rawLines = parseBankCsv(csv);
  } catch (error) {
    return fail(error instanceof Error ? error.message : 'كشف الحساب غير صالح');
  }

  const parsed = bankImportSchema.safeParse({
    organizationId,
    cashAccountId,
    idempotencyKey,
    lines: rawLines,
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'كشف الحساب غير صحيح');
  if (!parsed.data.lines[0]?.currency) return fail('العملة مطلوبة');

  const currency = parsed.data.lines[0].currency;
  const supabase = await createClient();
  const { error } = await supabase.rpc('import_bank_statement_lines', {
    p_organization_id: parsed.data.organizationId,
    p_cash_account_id: parsed.data.cashAccountId,
    p_dates: parsed.data.lines.map((line) => line.transactionDate),
    p_amounts: parsed.data.lines.map((line) => parseSignedMajorUnitsToMinor(line.amount, currency)),
    p_currencies: parsed.data.lines.map(() => currency),
    p_descriptions: parsed.data.lines.map((line) => line.description),
    p_references: parsed.data.lines.map((line) => line.providerReference || null),
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر استيراد كشف الحساب. تأكد من تطابق العملة وعدم تكرار الأسطر.');
  refreshProject(String(form.get('projectId') || ''));
  return {};
}

export async function reconcilePayment(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = reconcileSchema.safeParse({
    organizationId: form.get('organizationId'),
    paymentId: form.get('paymentId'),
    statementLineId: form.get('statementLineId'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات المطابقة غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('reconcile_payment', {
    p_organization_id: parsed.data.organizationId,
    p_payment_id: parsed.data.paymentId,
    p_statement_line_id: parsed.data.statementLineId,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر إتمام المطابقة. تحقق من الحساب والعملة والمبلغ.');
  refreshProject(String(form.get('projectId') || ''));
  return {};
}

export async function voidReconciliation(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = voidReconciliationSchema.safeParse({
    organizationId: form.get('organizationId'),
    matchId: form.get('matchId'),
    reason: form.get('reason'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات الإلغاء غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('void_reconciliation', {
    p_organization_id: parsed.data.organizationId,
    p_match_id: parsed.data.matchId,
    p_reason: parsed.data.reason,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر إلغاء المطابقة.');
  refreshProject(String(form.get('projectId') || ''));
  return {};
}

export async function reverseJournalBatch(_: ActionState, form: FormData): Promise<ActionState> {
  const parsed = reversalSchema.safeParse({
    organizationId: form.get('organizationId'),
    batchId: form.get('batchId'),
    reason: form.get('reason'),
    idempotencyKey: form.get('idempotencyKey'),
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? 'بيانات العكس غير صحيحة');
  const supabase = await createClient();
  const { error } = await supabase.rpc('reverse_journal_batch', {
    p_organization_id: parsed.data.organizationId,
    p_batch_id: parsed.data.batchId,
    p_reason: parsed.data.reason,
    p_idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return domainError(error.message, 'تعذر عكس القيد. تحقق من ترتيب العكس والصلاحيات.');
  refreshProject(String(form.get('projectId') || ''));
  return {};
}
