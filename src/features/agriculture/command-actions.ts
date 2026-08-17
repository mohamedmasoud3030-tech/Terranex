'use server';

import type { ActionState } from '@/features/auth/actions';
import { withAgricultureCommandLifecycle } from './command-lifecycle';
import * as domain from './actions';

export async function createAgricultureProfile(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.createAgricultureProfile, prev, form); }
export async function createAgriculturalLandAsset(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.createAgriculturalLandAsset, prev, form); }
export async function linkFarmToAgriculturalLandAsset(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.linkFarmToAgriculturalLandAsset, prev, form); }
export async function createFarm(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.createFarm, prev, form); }
export async function createField(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.createField, prev, form); }
export async function createCropCycle(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.createCropCycle, prev, form); }
export async function transitionCropCycle(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.transitionCropCycle, prev, form); }
export async function assignCropCycleToField(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.assignCropCycleToField, prev, form); }
export async function createFieldActivity(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.createFieldActivity, prev, form); }
export async function createInputItem(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.createInputItem, prev, form); }
export async function createInputLot(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.createInputLot, prev, form); }
export async function recordInputApplication(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.recordInputApplication, prev, form); }
export async function createStorageLocation(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.createStorageLocation, prev, form); }
export async function recordHarvestEvent(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.recordHarvestEvent, prev, form); }
export async function transferHarvestInventory(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.transferHarvestInventory, prev, form); }
export async function recordHarvestInventoryAdjustment(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.recordHarvestInventoryAdjustment, prev, form); }
export async function createAgricultureSale(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.createAgricultureSale, prev, form); }
export async function approveAgricultureSale(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.approveAgricultureSale, prev, form); }
export async function recognizeAgricultureSale(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.recognizeAgricultureSale, prev, form); }
export async function collectAgricultureSaleReceivable(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.collectAgricultureSaleReceivable, prev, form); }
export async function attributeCropCycleCost(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.attributeCropCycleCost, prev, form); }
export async function closeCropCycle(prev: ActionState, form: FormData) { return withAgricultureCommandLifecycle(domain.closeCropCycle, prev, form); }
