'use server';

import type { ActionState } from '@/features/auth/actions';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import {
  approveDisposition as approveDispositionLegacy,
  classifySellingCost as classifySellingCostLegacy,
  collectReceivable as collectReceivableLegacy,
  confirmControlTransfer as confirmControlTransferLegacy,
  createDisposition as createDispositionLegacy,
  recognizeSale as recognizeSaleLegacy,
  reconcileCollection as reconcileCollectionLegacy,
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

export async function createDisposition(prev: ActionState, form: FormData) {
  return runCommand(prev, form, createDispositionLegacy);
}
export async function approveDisposition(prev: ActionState, form: FormData) {
  return runCommand(prev, form, approveDispositionLegacy);
}
export async function confirmControlTransfer(prev: ActionState, form: FormData) {
  return runCommand(prev, form, confirmControlTransferLegacy);
}
export async function recognizeSale(prev: ActionState, form: FormData) {
  return runCommand(prev, form, recognizeSaleLegacy);
}
export async function collectReceivable(prev: ActionState, form: FormData) {
  return runCommand(prev, form, collectReceivableLegacy);
}
export async function reconcileCollection(prev: ActionState, form: FormData) {
  return runCommand(prev, form, reconcileCollectionLegacy);
}
export async function classifySellingCost(prev: ActionState, form: FormData) {
  return runCommand(prev, form, classifySellingCostLegacy);
}
