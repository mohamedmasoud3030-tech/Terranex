'use server';

import { revalidatePath } from 'next/cache';
import type { ZodType } from 'zod';
import type { ActionState } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';
import { livestockErrorMessage } from './errors';
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

function failed(error: string): ActionState {
  return { error };
}

async function invoke<T extends { projectId: string }>(
  schema: ZodType<T>,
  form: FormData,
  rpc: string,
  argumentsFor: (input: T) => Record<string, unknown>,
): Promise<ActionState> {
  const parsed = schema.safeParse(Object.fromEntries(form));
  if (!parsed.success) {
    return failed(parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة');
  }

  const { error } = await (await createClient()).rpc(rpc, argumentsFor(parsed.data));
  if (error) {
    return failed(livestockErrorMessage(error.message));
  }

  revalidatePath(`/projects/${parsed.data.projectId}/livestock`);
  return {};
}

export async function createLivestockProfile(
  _: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    livestockProfileSchema,
    form,
    'create_livestock_profile',
    profileRpcArguments,
  );
}

export async function createLivestockSite(
  _: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(livestockSiteSchema, form, 'create_livestock_site', siteRpcArguments);
}

export async function createLivestockHerd(
  _: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(livestockHerdSchema, form, 'create_livestock_herd', herdRpcArguments);
}

export async function createLivestockCohort(
  _: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    livestockCohortSchema,
    form,
    'create_livestock_cohort',
    cohortRpcArguments,
  );
}

export async function transitionLivestockCohort(
  _: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    livestockTransitionSchema,
    form,
    'transition_livestock_cohort',
    transitionRpcArguments,
  );
}
