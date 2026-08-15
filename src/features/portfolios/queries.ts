import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';
import type { PortfolioStatus } from './schema';

/**
 * R1 portfolio read models. All reads go through the security_invoker
 * views created by the R1 migration, so row-level security applies with
 * the caller's identity. Portfolio is a management/reporting parent: no
 * financial roll-up is read or derived here (that is R2 scope and must
 * stay traceable to project truth).
 */

export type PortfolioRead = {
  id: string;
  organization_id: string;
  name: string;
  description: string | null;
  status: PortfolioStatus;
  responsible_manager_id: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
};

export type PortfolioStatusHistoryRead = {
  id: string;
  organization_id: string;
  portfolio_id: string;
  previous_status: PortfolioStatus | null;
  new_status: PortfolioStatus;
  reason: string | null;
  changed_by: string;
  changed_at: string;
};

export type PortfolioMembershipRead = {
  id: string;
  organization_id: string;
  portfolio_id: string;
  investment_project_id: string;
  project_name: string;
  project_sector: 'REAL_ESTATE' | 'AGRICULTURE' | 'LIVESTOCK';
  project_internal_reference: string | null;
  project_lifecycle_state: string;
  assigned_by: string;
  assigned_at: string;
  removed_by: string | null;
  removed_at: string | null;
  removal_reason: string | null;
};

export type OrganizationMember = {
  user_id: string;
  role: string;
  status: string;
};

export async function getPortfolios(organizationId: string): Promise<PortfolioRead[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('investment_portfolios_read')
    .select('*')
    .eq('organization_id', organizationId)
    .order('created_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as PortfolioRead[];
}

export async function getPortfolio(id: string): Promise<PortfolioRead | null> {
  const s = await createClient();
  const { data, error } = await s
    .from('investment_portfolios_read')
    .select('*')
    .eq('id', id)
    .maybeSingle();
  if (error) throwOperatorQuery(error);
  return (data ?? null) as PortfolioRead | null;
}

export async function getPortfolioStatusHistory(
  portfolioId: string,
): Promise<PortfolioStatusHistoryRead[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('investment_portfolio_state_history_read')
    .select('*')
    .eq('portfolio_id', portfolioId)
    .order('changed_at', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as PortfolioStatusHistoryRead[];
}

export async function getPortfolioMemberships(
  portfolioId: string,
): Promise<PortfolioMembershipRead[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('portfolio_project_assignments_read')
    .select('*')
    .eq('portfolio_id', portfolioId)
    .order('assigned_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as PortfolioMembershipRead[];
}

/** Current (non-removed) memberships for one portfolio. */
export async function getActivePortfolioMemberships(
  portfolioId: string,
): Promise<PortfolioMembershipRead[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('portfolio_project_assignments_read')
    .select('*')
    .eq('portfolio_id', portfolioId)
    .is('removed_at', null)
    .order('assigned_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as PortfolioMembershipRead[];
}

/** All current (non-removed) memberships in one organization. */
export async function getOrganizationActiveMemberships(
  organizationId: string,
): Promise<PortfolioMembershipRead[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('portfolio_project_assignments_read')
    .select('*')
    .eq('organization_id', organizationId)
    .is('removed_at', null)
    .order('assigned_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as PortfolioMembershipRead[];
}

/**
 * Org projects that are NOT currently assigned to any portfolio, i.e. the
 * candidates an operator may assign. Projects already under a parent are
 * excluded because the canonical hierarchy allows one current parent.
 */
export async function getAssignableProjects(organizationId: string) {
  const s = await createClient();
  const { data, error } = await s
    .from('investment_projects')
    .select('id,name,internal_reference,sector,lifecycle_state')
    .eq('organization_id', organizationId)
    .order('created_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  const projects = data ?? [];

  const { data: memberships, error: membershipError } = await s
    .from('portfolio_project_assignments_read')
    .select('investment_project_id')
    .eq('organization_id', organizationId)
    .is('removed_at', null);
  if (membershipError) throwOperatorQuery(membershipError);
  const assigned = new Set((memberships ?? []).map((m) => m.investment_project_id));

  return projects.filter((p) => !assigned.has(p.id));
}

export async function getOrganizationMembers(
  organizationId: string,
): Promise<OrganizationMember[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('memberships')
    .select('user_id,role,status')
    .eq('organization_id', organizationId)
    .eq('status', 'ACTIVE')
    .order('created_at', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as OrganizationMember[];
}
