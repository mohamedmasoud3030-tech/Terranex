'use server';

import { revalidatePath } from 'next/cache';
import type { ZodType } from 'zod';
import type { ActionState } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';
import { livestockErrorMessage } from './errors';
import { commandFailureState, commandSuccessState } from './idempotency';
import {
  birthRpcArguments,
  cohortRpcArguments,
  herdRpcArguments,
  mergeRpcArguments,
  mortalityRpcArguments,
  movementRpcArguments,
  profileRpcArguments,
  siteRpcArguments,
  splitRpcArguments,
  transitionRpcArguments,
  weightEventRpcArguments,
} from './rpc';
import {
  livestockBirthSchema,
  livestockCohortSchema,
  livestockHerdSchema,
  livestockMergeSchema,
  livestockMortalitySchema,
  livestockMovementSchema,
  livestockProfileSchema,
  livestockSiteSchema,
  livestockSplitSchema,
  livestockTransitionSchema,
  livestockWeightEventSchema,
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

export async function recordLivestockMovement(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    livestockMovementSchema,
    form,
    'record_livestock_movement',
    movementRpcArguments,
  );
}

export async function recordLivestockWeightEvent(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    livestockWeightEventSchema,
    form,
    'record_livestock_weight_event',
    weightEventRpcArguments,
  );
}

export async function recordLivestockBirth(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(prev, livestockBirthSchema, form, 'record_livestock_birth', birthRpcArguments);
}

export async function recordLivestockMortality(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    livestockMortalitySchema,
    form,
    'record_livestock_mortality',
    mortalityRpcArguments,
  );
}

export async function splitLivestockCohort(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    livestockSplitSchema,
    form,
    'split_livestock_cohort',
    splitRpcArguments,
  );
}

/**
 * Merge is the only Livestock command with repeated fields: one
 * `sourceCohortIds` / `quantities` pair per merged Cohort. `Object.fromEntries`
 * keeps only the last value of a repeated key, so the two array fields are
 * collected with `getAll` before validation.
 */
export async function mergeLivestockCohorts(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const parsed = livestockMergeSchema.safeParse({
    ...Object.fromEntries(form),
    sourceCohortIds: form.getAll('sourceCohortIds'),
    quantities: form.getAll('quantities'),
  });
  if (!parsed.success) {
    return commandFailureState(
      prev,
      parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة',
    );
  }

  const { error } = await (await createClient()).rpc(
    'merge_livestock_cohorts',
    mergeRpcArguments(parsed.data),
  );
  if (error) {
    return commandFailureState(prev, livestockErrorMessage(error.message));
  }

  revalidatePath(`/projects/${parsed.data.projectId}/livestock`);
  return commandSuccessState(prev);
}

// ---------------------------------------------------------------------------
// GF-024 — Livestock commercial, profitability & closeout.
//
// Purchase and sale carry multi-line JSON (`linesJson`) that the schemas
// normalize into positionally-aligned arrays. Money is parsed to exact minor
// units only inside the RPC argument mappers; the browser never supplies
// authoritative balances, actor, approval outcome, or result figures.
// ---------------------------------------------------------------------------
import {
  livestockCloseoutSchema,
  livestockCostAttributionReversalSchema,
  livestockCostAttributionSchema,
  livestockPurchaseSchema,
  livestockSaleApprovalSchema,
  livestockSaleCollectionSchema,
  livestockSaleRecognitionSchema,
  livestockSaleSchema,
} from './schema';
import {
  closeoutRpcArguments,
  costAttributionReversalRpcArguments,
  costAttributionRpcArguments,
  purchaseRpcArguments,
  saleApprovalRpcArguments,
  saleCollectionRpcArguments,
  saleRecognitionRpcArguments,
  saleRpcArguments,
} from './rpc';

function gf024Invoke<T extends { projectId: string }>(
  prev: ActionState,
  schema: ZodType<T>,
  form: FormData,
  rpc: string,
  argumentsFor: (input: T) => Record<string, unknown>,
): Promise<ActionState> {
  const parsed = schema.safeParse(Object.fromEntries(form));
  if (!parsed.success) {
    return Promise.resolve(commandFailureState(
      prev,
      parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة',
    ));
  }
  return (async () => {
    const { error } = await (await createClient()).rpc(rpc, argumentsFor(parsed.data));
    if (error) {
      return commandFailureState(prev, livestockErrorMessage(error.message));
    }
    revalidatePath(`/projects/${parsed.data.projectId}`);
    revalidatePath(`/projects/${parsed.data.projectId}/livestock`);
    return commandSuccessState(prev);
  })();
}

export async function recordLivestockPurchase(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return gf024Invoke(
    prev,
    livestockPurchaseSchema,
    form,
    'record_livestock_purchase',
    purchaseRpcArguments,
  );
}

export async function createLivestockSale(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return gf024Invoke(
    prev,
    livestockSaleSchema,
    form,
    'create_livestock_sale',
    saleRpcArguments,
  );
}

export async function approveLivestockSale(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return gf024Invoke(
    prev,
    livestockSaleApprovalSchema,
    form,
    'approve_livestock_sale',
    saleApprovalRpcArguments,
  );
}

export async function recognizeLivestockSale(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return gf024Invoke(
    prev,
    livestockSaleRecognitionSchema,
    form,
    'recognize_livestock_sale',
    saleRecognitionRpcArguments,
  );
}

export async function collectLivestockSaleReceivable(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return gf024Invoke(
    prev,
    livestockSaleCollectionSchema,
    form,
    'collect_livestock_sale_receivable',
    saleCollectionRpcArguments,
  );
}

export async function attributeLivestockCohortCost(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return gf024Invoke(
    prev,
    livestockCostAttributionSchema,
    form,
    'attribute_livestock_cohort_cost',
    costAttributionRpcArguments,
  );
}

export async function reverseLivestockCohortCostAttribution(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return gf024Invoke(
    prev,
    livestockCostAttributionReversalSchema,
    form,
    'reverse_livestock_cohort_cost_attribution',
    costAttributionReversalRpcArguments,
  );
}

export async function closeLivestockCohort(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return gf024Invoke(
    prev,
    livestockCloseoutSchema,
    form,
    'close_livestock_cohort',
    closeoutRpcArguments,
  );
}
