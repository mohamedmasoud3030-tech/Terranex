'use server';

import type { ActionState } from '@/features/auth/actions';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import {
  approveCloseExceptionAction as approveCloseExceptionLegacy,
  approveCloseRunAction as approveCloseRunLegacy,
  approveCorrectionAction as approveCorrectionLegacy,
  createAccountingPeriodAction as createAccountingPeriodLegacy,
  executeCorrectionAction as executeCorrectionLegacy,
  prepareCloseRunAction as prepareCloseRunLegacy,
  reopenPeriodAction as reopenPeriodLegacy,
  requestCloseExceptionAction as requestCloseExceptionLegacy,
  requestCorrectionAction as requestCorrectionLegacy,
} from './actions';

type LegacyAction = (prev: ActionState, form: FormData) => Promise<ActionState>;

async function runCommand(
  prev: ActionState,
  form: FormData,
  action: LegacyAction,
): Promise<ActionState> {
  const result = await action(prev, form);
  return result.error
    ? commandFailureState(prev, result.error)
    : commandSuccessState(prev);
}

export async function createAccountingPeriodAction(prev: ActionState, form: FormData) {
  return runCommand(prev, form, createAccountingPeriodLegacy);
}

export async function prepareCloseRunAction(prev: ActionState, form: FormData) {
  return runCommand(prev, form, prepareCloseRunLegacy);
}

export async function approveCloseRunAction(prev: ActionState, form: FormData) {
  return runCommand(prev, form, approveCloseRunLegacy);
}

export async function requestCloseExceptionAction(prev: ActionState, form: FormData) {
  return runCommand(prev, form, requestCloseExceptionLegacy);
}

export async function approveCloseExceptionAction(prev: ActionState, form: FormData) {
  return runCommand(prev, form, approveCloseExceptionLegacy);
}

export async function reopenPeriodAction(prev: ActionState, form: FormData) {
  return runCommand(prev, form, reopenPeriodLegacy);
}

export async function requestCorrectionAction(prev: ActionState, form: FormData) {
  return runCommand(prev, form, requestCorrectionLegacy);
}

export async function approveCorrectionAction(prev: ActionState, form: FormData) {
  return runCommand(prev, form, approveCorrectionLegacy);
}

export async function executeCorrectionAction(prev: ActionState, form: FormData) {
  return runCommand(prev, form, executeCorrectionLegacy);
}
