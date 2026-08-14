'use server';

import { revalidatePath } from 'next/cache';
import type { ZodType } from 'zod';
import type { ActionState } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';
import { livestockErrorMessage } from './errors';
import { commandFailureState, commandSuccessState } from './idempotency';
import {
  cohortRpcArguments,
  herdRpcArguments,
  profileRpcArguments,
  siteRpcArguments,
  transitionRpcArguments,
} from './rpc';
import {
  livestockCohortSchema,
  livestockHerdSchema,
  livestockProfileSchema,
  livestockSiteSchema,
  livestockTransitionSchema,
} from './schema';

async function invoke<T extends { projectId: string }>(
  prev: ActionState,
  schema: ZodType<T>,
  form: FormData,
  rpc: string,
  argumentsFor: (input: T) => Record<string, unknown>,
): Promise<ActionState> {
  const parsed = schema.safeParse(Object.fromEntries(form));
  if (!parsed.success) {
    return commandFailureState(
      prev,
      parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة',
    );
  }

  const { error } = await (await createClient()).rpc(rpc, argumentsFor(parsed.data));
  if (error) {
    return commandFailureState(prev, livestockErrorMessage(error.message));
  }

  revalidatePath(`/projects/${parsed.data.projectId}/livestock`);
  return commandSuccessState(prev);
}

export async function createLivestockProfile(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    livestockProfileSchema,
    form,
    'create_livestock_profile',
    profileRpcArguments,
  );
}

export async function createLivestockSite(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(prev, livestockSiteSchema, form, 'create_livestock_site', siteRpcArguments);
}

export async function createLivestockHerd(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(prev, livestockHerdSchema, form, 'create_livestock_herd', herdRpcArguments);
}

export async function createLivestockCohort(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    livestockCohortSchema,
    form,
    'create_livestock_cohort',
    cohortRpcArguments,
  );
}

export async function transitionLivestockCohort(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    livestockTransitionSchema,
    form,
    'transition_livestock_cohort',
    transitionRpcArguments,
  );
}
