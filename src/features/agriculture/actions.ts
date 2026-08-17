'use server';

import type { ActionState } from '@/features/auth/actions';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import * as domain from './domain-actions';

type AgricultureAction = (prev: ActionState, form: FormData) => Promise<ActionState>;

/**
 * The mounted Agriculture forms intentionally keep one stable random base key.
 * Turn that base into the authoritative logical-command key at the server
 * boundary by suffixing the last server-confirmed success count.
 *
 * Lost/failed response => the client still has the previous success count and
 * therefore retries the exact same effective key. Confirmed success => the
 * returned count advances and the next distinct submit gets a fresh key.
 */
async function withCommandLifecycle(
  action: AgricultureAction,
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const baseKey = form.get('idempotencyKey');
  if (typeof baseKey !== 'string' || baseKey.length === 0) {
    return commandFailureState(prev, 'تعذر تجهيز مفتاح العملية الآمن. حدّث الصفحة ثم أعد المحاولة.');
  }

  form.set('idempotencyKey', `${baseKey}-${prev.successCount ?? 0}`);
  const result = await action(prev, form);
  if (result.error) return commandFailureState(prev, result.error);
  return commandSuccessState(prev);
}

export async function createAgricultureProfile(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.createAgricultureProfile, prev, form);
}
export async function createAgriculturalLandAsset(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.createAgriculturalLandAsset, prev, form);
}
export async function linkFarmToAgriculturalLandAsset(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.linkFarmToAgriculturalLandAsset, prev, form);
}
export async function createFarm(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.createFarm, prev, form);
}
export async function createField(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.createField, prev, form);
}
export async function createCropCycle(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.createCropCycle, prev, form);
}
export async function transitionCropCycle(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.transitionCropCycle, prev, form);
}
export async function assignCropCycleToField(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.assignCropCycleToField, prev, form);
}
export async function createFieldActivity(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.createFieldActivity, prev, form);
}
export async function createInputItem(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.createInputItem, prev, form);
}
export async function createInputLot(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.createInputLot, prev, form);
}
export async function recordInputApplication(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.recordInputApplication, prev, form);
}
export async function createStorageLocation(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.createStorageLocation, prev, form);
}
export async function recordHarvestEvent(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.recordHarvestEvent, prev, form);
}
export async function transferHarvestInventory(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.transferHarvestInventory, prev, form);
}
export async function recordHarvestInventoryAdjustment(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.recordHarvestInventoryAdjustment, prev, form);
}
export async function createAgricultureSale(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.createAgricultureSale, prev, form);
}
export async function approveAgricultureSale(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.approveAgricultureSale, prev, form);
}
export async function recognizeAgricultureSale(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.recognizeAgricultureSale, prev, form);
}
export async function collectAgricultureSaleReceivable(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.collectAgricultureSaleReceivable, prev, form);
}
export async function attributeCropCycleCost(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.attributeCropCycleCost, prev, form);
}
export async function closeCropCycle(prev: ActionState, form: FormData) {
  return withCommandLifecycle(domain.closeCropCycle, prev, form);
}
