'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import type { ZodType } from 'zod';
import type { ActionState } from '@/features/auth/actions';
import { createClient } from '@/shared/supabase/server';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import { portfolioErrorMessage } from './errors';
import {
  assignProjectRpcArguments,
  createPortfolioRpcArguments,
  moveProjectRpcArguments,
  removeProjectRpcArguments,
  transitionPortfolioRpcArguments,
  updatePortfolioRpcArguments,
} from './rpc';
import {
  assignProjectSchema,
  createPortfolioSchema,
  moveProjectSchema,
  removeProjectSchema,
  portfolioTransitionSchema,
  updatePortfolioSchema,
} from './schema';

/**
 * R1 portfolio server actions. Every command is authenticated (Supabase
 * session), authorized and organization-scoped by the security-definer RPC,
 * idempotent by command key, and auditable in the database. Validation runs
 * at the boundary; the database remains authoritative.
 */

async function invoke<T extends { organizationId: string }>(
  prev: ActionState,
  schema: ZodType<T>,
  form: FormData,
  rpc: string,
  argumentsFor: (input: T) => Record<string, unknown>,
  revalidateFor: (input: T) => string,
): Promise<ActionState> {
  const parsed = schema.safeParse(Object.fromEntries(form));
  if (!parsed.success) {
    return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة');
  }
  const { error } = await (await createClient()).rpc(rpc, argumentsFor(parsed.data));
  if (error) {
    return commandFailureState(prev, portfolioErrorMessage(error.message));
  }
  revalidatePath(revalidateFor(parsed.data));
  return commandSuccessState(prev);
}

const portfolioPath = (input: { portfolioId: string }) => `/portfolios/${input.portfolioId}`;
/** Membership moves touch both the source and every portfolio list. */
const portfoliosPath = () => '/portfolios';

export async function createPortfolio(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const parsed = createPortfolioSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) {
    return commandFailureState(prev, parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة');
  }
  const { data, error } = await (
    await createClient()
  ).rpc('create_investment_portfolio', createPortfolioRpcArguments(parsed.data));
  if (error || !data) {
    return commandFailureState(prev, portfolioErrorMessage(error?.message));
  }
  redirect(`/portfolios/${data}`);
}

export async function updatePortfolio(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    updatePortfolioSchema,
    form,
    'update_investment_portfolio_metadata',
    updatePortfolioRpcArguments,
    portfolioPath,
  );
}

export async function transitionPortfolio(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    portfolioTransitionSchema,
    form,
    'transition_investment_portfolio',
    transitionPortfolioRpcArguments,
    portfolioPath,
  );
}

export async function assignProjectToPortfolio(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    assignProjectSchema,
    form,
    'assign_project_to_portfolio',
    assignProjectRpcArguments,
    portfolioPath,
  );
}

export async function removeProjectFromPortfolio(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    removeProjectSchema,
    form,
    'remove_project_from_portfolio',
    removeProjectRpcArguments,
    portfolioPath,
  );
}

export async function moveProjectToPortfolio(
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  return invoke(
    prev,
    moveProjectSchema,
    form,
    'move_project_to_portfolio',
    moveProjectRpcArguments,
    portfoliosPath,
  );
}
