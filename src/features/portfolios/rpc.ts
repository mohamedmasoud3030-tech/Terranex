import type {
  AssignProjectInput,
  CreatePortfolioInput,
  MoveProjectInput,
  PortfolioTransitionInput,
  RemoveProjectInput,
  UpdatePortfolioInput,
} from './schema';

/**
 * Pure RPC argument builders for the R1 portfolio commands. The database
 * functions are the authoritative boundary; these builders only shape the
 * validated inputs for `supabase.rpc`.
 */

export const createPortfolioRpcArguments = (input: CreatePortfolioInput) => ({
  p_organization_id: input.organizationId,
  p_name: input.name,
  p_description: input.description || null,
  p_responsible_manager_id: input.responsibleManagerId || null,
  p_idempotency_key: input.idempotencyKey,
});

export const updatePortfolioRpcArguments = (input: UpdatePortfolioInput) => ({
  p_organization_id: input.organizationId,
  p_portfolio_id: input.portfolioId,
  p_name: input.name,
  p_description: input.description || null,
  p_responsible_manager_id: input.responsibleManagerId || null,
  p_idempotency_key: input.idempotencyKey,
});

export const transitionPortfolioRpcArguments = (input: PortfolioTransitionInput) => ({
  p_organization_id: input.organizationId,
  p_portfolio_id: input.portfolioId,
  p_expected_status: input.expectedStatus,
  p_new_status: input.newStatus,
  p_reason: input.reason,
  p_idempotency_key: input.idempotencyKey,
});

export const assignProjectRpcArguments = (input: AssignProjectInput) => ({
  p_organization_id: input.organizationId,
  p_portfolio_id: input.portfolioId,
  p_project_id: input.projectId,
  p_idempotency_key: input.idempotencyKey,
});

export const removeProjectRpcArguments = (input: RemoveProjectInput) => ({
  p_organization_id: input.organizationId,
  p_portfolio_id: input.portfolioId,
  p_project_id: input.projectId,
  p_reason: input.reason,
  p_idempotency_key: input.idempotencyKey,
});

export const moveProjectRpcArguments = (input: MoveProjectInput) => ({
  p_organization_id: input.organizationId,
  p_project_id: input.projectId,
  p_target_portfolio_id: input.targetPortfolioId,
  p_reason: input.reason,
  p_idempotency_key: input.idempotencyKey,
});
