/**
 * Active-organization selection — pure, environment-free constants and the
 * resolver used by both the server context and the client switcher.
 *
 * The active organization is a UI preference scoped to this browser, carried
 * in a first-party cookie. It is ALWAYS validated against the user's actual
 * memberships server-side; the cookie can never grant access to an
 * organization the user is not a member of, and every tenant-scoped query
 * still passes through Supabase RLS.
 */

export const ACTIVE_ORG_COOKIE = 'terranex_active_org';

/** One year; a pure preference cookie, refreshed on every switch. */
export const ACTIVE_ORG_COOKIE_MAX_AGE = 60 * 60 * 24 * 365;

export type OrganizationSummary = {
  id: string;
  name: string;
};

/**
 * Resolves the organization a user operates on:
 * - no organizations → null;
 * - cookie names a membership the user actually has → that organization;
 * - missing/stale/unknown cookie → the first (oldest) organization, which
 *   preserves the historical `organizations[0]` behavior.
 */
export function resolveActiveOrganization(
  organizations: OrganizationSummary[],
  cookieValue: string | null | undefined,
): OrganizationSummary | null {
  if (organizations.length === 0) return null;
  const requested = (cookieValue ?? '').trim();
  if (requested) {
    const match = organizations.find((org) => org.id === requested);
    if (match) return match;
  }
  return organizations[0];
}
