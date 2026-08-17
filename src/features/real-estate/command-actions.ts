'use server';

import type { ActionState } from '@/features/auth/actions';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import {
  approveBudget as approveBudgetLegacy,
  approveValuation as approveValuationLegacy,
  classifyCost as classifyCostLegacy,
  confirmSectorEvent as confirmSectorEventLegacy,
  createAsset as createAssetLegacy,
  createMilestone as createMilestoneLegacy,
  createParcel as createParcelLegacy,
  createPhase as createPhaseLegacy,
  createProfile as createProfileLegacy,
  proposeBudget as proposeBudgetLegacy,
  proposeValuation as proposeValuationLegacy,
  recordAcquisition as recordAcquisitionLegacy,
  recordControl as recordControlLegacy,
  transitionMilestone as transitionMilestoneLegacy,
  transitionPhase as transitionPhaseLegacy,
  transitionProperty as transitionPropertyLegacy,
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

export async function createProfile(prev: ActionState, form: FormData) {
  return runCommand(prev, form, createProfileLegacy);
}
export async function createAsset(prev: ActionState, form: FormData) {
  return runCommand(prev, form, createAssetLegacy);
}
export async function createParcel(prev: ActionState, form: FormData) {
  return runCommand(prev, form, createParcelLegacy);
}
export async function recordAcquisition(prev: ActionState, form: FormData) {
  return runCommand(prev, form, recordAcquisitionLegacy);
}
export async function recordControl(prev: ActionState, form: FormData) {
  return runCommand(prev, form, recordControlLegacy);
}
export async function transitionProperty(prev: ActionState, form: FormData) {
  return runCommand(prev, form, transitionPropertyLegacy);
}
export async function createPhase(prev: ActionState, form: FormData) {
  return runCommand(prev, form, createPhaseLegacy);
}
export async function transitionPhase(prev: ActionState, form: FormData) {
  return runCommand(prev, form, transitionPhaseLegacy);
}
export async function createMilestone(prev: ActionState, form: FormData) {
  return runCommand(prev, form, createMilestoneLegacy);
}
export async function transitionMilestone(prev: ActionState, form: FormData) {
  return runCommand(prev, form, transitionMilestoneLegacy);
}
export async function proposeBudget(prev: ActionState, form: FormData) {
  return runCommand(prev, form, proposeBudgetLegacy);
}
export async function approveBudget(prev: ActionState, form: FormData) {
  return runCommand(prev, form, approveBudgetLegacy);
}
export async function classifyCost(prev: ActionState, form: FormData) {
  return runCommand(prev, form, classifyCostLegacy);
}
export async function proposeValuation(prev: ActionState, form: FormData) {
  return runCommand(prev, form, proposeValuationLegacy);
}
export async function approveValuation(prev: ActionState, form: FormData) {
  return runCommand(prev, form, approveValuationLegacy);
}
export async function confirmSectorEvent(prev: ActionState, form: FormData) {
  return runCommand(prev, form, confirmSectorEventLegacy);
}
