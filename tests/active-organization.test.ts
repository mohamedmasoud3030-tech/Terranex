import { describe, expect, it } from 'vitest';
import {
  ACTIVE_ORG_COOKIE,
  ACTIVE_ORG_COOKIE_MAX_AGE,
  resolveActiveOrganization,
} from '@/features/organizations/active-org';

const orgs = [
  { id: '00000000-0000-4000-8000-000000000001', name: 'المنظمة الأولى' },
  { id: '00000000-0000-4000-8000-000000000002', name: 'المنظمة الثانية' },
];

describe('resolveActiveOrganization', () => {
  it('returns null when the user has no organizations', () => {
    expect(resolveActiveOrganization([], undefined)).toBeNull();
  });

  it('falls back to the first organization without a cookie', () => {
    expect(resolveActiveOrganization(orgs, undefined)?.id).toBe(orgs[0].id);
    expect(resolveActiveOrganization(orgs, null)?.id).toBe(orgs[0].id);
    expect(resolveActiveOrganization(orgs, '')?.id).toBe(orgs[0].id);
    expect(resolveActiveOrganization(orgs, '   ')?.id).toBe(orgs[0].id);
  });

  it('ignores a stale cookie that names a non-membership organization', () => {
    expect(resolveActiveOrganization(orgs, '99999999-9999-4999-8999-999999999999')?.id).toBe(orgs[0].id);
  });

  it('honours a cookie that names an actual membership', () => {
    expect(resolveActiveOrganization(orgs, orgs[1].id)?.id).toBe(orgs[1].id);
  });

  it('keeps the cookie constants stable for both server and client', () => {
    expect(ACTIVE_ORG_COOKIE).toBe('terranex_active_org');
    expect(ACTIVE_ORG_COOKIE_MAX_AGE).toBe(60 * 60 * 24 * 365);
  });
});
