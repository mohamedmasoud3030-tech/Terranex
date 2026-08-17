'use server';

import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import { createClient } from '@/shared/supabase/server';
import { cashAccountSchema } from './schema';
import {
  approvePayment,
  attachContributionCash,
  authorizeObligation,
  createObligation,
  importBankStatement,
  preparePayment,
  reconcilePayment,
  reverseJournalBatch,
  voidReconciliation,
} from './actions';

type FinanceAction = (prev: ActionState, form: FormData) => Promise<ActionState>;

function refreshProject(projectId: string) {
  revalidatePath('/');
  revalidatePath(`/projects/${projectId}`);
  revalidatePath(`/projects/${projectId}/costs`);
  revalidatePath(`/projects/${projectId}/cash`);
  revalidatePath(`/projects/${projectId}/intake`);
}

async function withCommandLifecycle(
  action: FinanceAction,
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const result = await action(prev, form);
  if (result.error) return commandFailureState(prev, result.error);
  return commandSuccessState(prev);
}

export async function createCashAccountCommand(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const parsed = cashAccountSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) {
    return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'بيانات غير صحيحة');
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc('create_project_cash_account', {
    p_organization_id: parsed.data.organizationId,
    p_project_id: parsed.data.projectId,
    p_name: parsed.data.name,
    p_currency: parsed.data.currency,
    p_idempotency_key: parsed.data.idempotencyKey,
  });

  if (error) {
    const message = error.message?.includes('idempotency key payload mismatch')
      ? 'تعذر إعادة المحاولة لأن مفتاح العملية استُخدم سابقًا لبيانات مختلفة. حدّث الصفحة وحاول من جديد.'
      : 'تعذر إنشاء الحساب النقدي. تحقق من البيانات والصلاحيات.';
    return commandFailureState(prev, message);
  }

  refreshProject(parsed.data.projectId);
  return commandSuccessState(prev);
}

export async function attachContributionCashCommand(prev: ActionState, form: FormData) {
  return withCommandLifecycle(attachContributionCash, prev, form);
}

export async function createObligationCommand(prev: ActionState, form: FormData) {
  return withCommandLifecycle(createObligation, prev, form);
}

export async function authorizeObligationCommand(prev: ActionState, form: FormData) {
  return withCommandLifecycle(authorizeObligation, prev, form);
}

export async function preparePaymentCommand(prev: ActionState, form: FormData) {
  return withCommandLifecycle(preparePayment, prev, form);
}

export async function approvePaymentCommand(prev: ActionState, form: FormData) {
  return withCommandLifecycle(approvePayment, prev, form);
}

export async function importBankStatementCommand(prev: ActionState, form: FormData) {
  return withCommandLifecycle(importBankStatement, prev, form);
}

export async function reconcilePaymentCommand(prev: ActionState, form: FormData) {
  return withCommandLifecycle(reconcilePayment, prev, form);
}

export async function voidReconciliationCommand(prev: ActionState, form: FormData) {
  return withCommandLifecycle(voidReconciliation, prev, form);
}

export async function reverseJournalBatchCommand(prev: ActionState, form: FormData) {
  return withCommandLifecycle(reverseJournalBatch, prev, form);
}
