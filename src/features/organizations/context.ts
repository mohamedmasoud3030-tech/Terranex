import { cookies } from 'next/headers';
import { getOrganizations } from './queries';
import {
  ACTIVE_ORG_COOKIE,
  resolveActiveOrganization,
  type OrganizationSummary,
} from './active-org';

/**
 * Server-side active-organization context for top-level organization-scoped
 * pages (Home, Projects, Portfolios, Assets, Intake, new Project/Portfolio).
 * Entity-scoped pages (a specific project or portfolio) keep resolving their
 * organization from the entity itself.
 */
export async function getActiveOrganization(): Promise<{
  organization: OrganizationSummary | null;
  organizations: OrganizationSummary[];
}> {
  const organizations = await getOrganizations();
  const jar = await cookies();
  const organization = resolveActiveOrganization(
    organizations,
    jar.get(ACTIVE_ORG_COOKIE)?.value,
  );
  return { organization, organizations };
}
