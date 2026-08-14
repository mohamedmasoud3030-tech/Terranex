'use server';

import { revalidatePath } from 'next/cache';
import type { ZodType } from 'zod';
import type { ActionState } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';
import { livestockErrorMessage } from './errors';
import { commandFailureState, commandSuccessState } from './idempotency';
import {
  feedIssueRpcArguments,
  feedItemRpcArguments,
  healthEventRpcArguments,
  identifyAnimalRpcArguments,
  medicineProductRpcArguments,
  reproductionEventRpcArguments,
} from './operations-rpc';
import {
  feedIssueSchema,
  feedItemSchema,
  healthEventSchema,
  identifyAnimalSchema,
  medicineProductSchema,
  reproductionEventSchema,
} from './operations-schema';

async function invoke<T extends { projectId: string }>(
  prev: ActionState,
  schema: ZodType<T>,
  form: FormData,
  rpc: string,
  argumentsFor: (input: T) => Record<string, unknown>,
): Promise<ActionState> {
  const parsed = schema.safeParse(Object.fromEntries(form));
  if (!parsed.success) {
    return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة');
  }
  const { error } = await (await createClient()).rpc(rpc, argumentsFor(parsed.data));
  if (error) return commandFailureState(prev, livestockErrorMessage(error.message));
  revalidatePath(`/projects/${parsed.data.projectId}/livestock/operations`);
  return commandSuccessState(prev);
}

export async function createMedicineProduct(prev: ActionState, form: FormData) {
  return invoke(prev, medicineProductSchema, form, 'create_livestock_medicine_product', medicineProductRpcArguments);
}
export async function identifyAnimal(prev: ActionState, form: FormData) {
  return invoke(prev, identifyAnimalSchema, form, 'identify_livestock_animal', identifyAnimalRpcArguments);
}
export async function recordHealthEvent(prev: ActionState, form: FormData) {
  return invoke(prev, healthEventSchema, form, 'record_livestock_health_event', healthEventRpcArguments);
}
export async function recordReproductionEvent(prev: ActionState, form: FormData) {
  return invoke(prev, reproductionEventSchema, form, 'record_livestock_reproduction_event', reproductionEventRpcArguments);
}
export async function createFeedItem(prev: ActionState, form: FormData) {
  return invoke(prev, feedItemSchema, form, 'create_livestock_feed_item', feedItemRpcArguments);
}
export async function recordFeedIssue(prev: ActionState, form: FormData) {
  return invoke(prev, feedIssueSchema, form, 'record_livestock_feed_issue', feedIssueRpcArguments);
}
