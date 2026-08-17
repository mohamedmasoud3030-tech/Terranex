'use client';

import { useRouter } from 'next/navigation';
import {
  ACTIVE_ORG_COOKIE,
  ACTIVE_ORG_COOKIE_MAX_AGE,
  type OrganizationSummary,
} from './active-org';

/**
 * Header organization switcher. Shown only when the user belongs to more than
 * one organization. Selecting an organization stores the preference in the
 * `terranex_active_org` cookie and refreshes server components; every
 * tenant-scoped query still passes through Supabase RLS, so the preference can
 * never grant access to a non-membership organization.
 */
export function OrganizationSwitcher({
  organizations,
  activeId,
}: {
  organizations: OrganizationSummary[];
  activeId: string | null;
}) {
  const router = useRouter();

  if (organizations.length <= 1) return null;

  return (
    <label className="org-switcher">
      <span className="muted">المنظمة</span>
      <select
        value={activeId ?? ''}
        aria-label="اختيار المنظمة النشطة"
        onChange={(event) => {
          const id = event.target.value;
          document.cookie = `${ACTIVE_ORG_COOKIE}=${encodeURIComponent(id)}; path=/; max-age=${ACTIVE_ORG_COOKIE_MAX_AGE}; samesite=lax`;
          router.refresh();
        }}
      >
        {organizations.map((org) => (
          <option key={org.id} value={org.id}>
            {org.name}
          </option>
        ))}
      </select>
    </label>
  );
}
