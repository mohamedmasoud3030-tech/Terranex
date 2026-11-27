import { describe, expect, it } from 'vitest';
import { acceptInviteSchema, createInviteSchema, inviteToken, revokeInviteSchema } from '../src/features/invites/schema';
import { inviteStatusLabel } from '../src/features/invites/labels';

const ORG = '10000000-0000-4000-8000-000000000101';
const INVITE = '20000000-0000-4000-8000-000000000101';
const TOKEN = 'a'.repeat(64);

describe('organization invite validation', () => {
  it('accepts a well-formed create payload', () => {
    expect(createInviteSchema.safeParse({
      organizationId: ORG,
      note: 'محاسب الشركة',
      idempotencyKey: 'org-invite-create-test-0001',
    }).success).toBe(true);
  });

  it('turns an empty note into null and rejects overlong notes', () => {
    const parsed = createInviteSchema.safeParse({
      organizationId: ORG,
      note: '',
      idempotencyKey: 'org-invite-create-test-0002',
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.note).toBeNull();
    expect(createInviteSchema.safeParse({
      organizationId: ORG,
      note: 'x'.repeat(201),
      idempotencyKey: 'org-invite-create-test-0003',
    }).success).toBe(false);
  });

  it('requires an organization id and a command key', () => {
    expect(createInviteSchema.safeParse({ note: null }).success).toBe(false);
    expect(createInviteSchema.safeParse({
      organizationId: ORG,
      note: null,
      idempotencyKey: 'short',
    }).success).toBe(false);
  });

  it('accepts only a 64-char hex invite token', () => {
    expect(inviteToken.safeParse(TOKEN).success).toBe(true);
    expect(inviteToken.safeParse('a'.repeat(63)).success).toBe(false);
    expect(inviteToken.safeParse('g'.repeat(64)).success).toBe(false);
    expect(inviteToken.safeParse(`'${TOKEN}`).success).toBe(false);
  });

  it('validates revoke and accept payloads', () => {
    expect(revokeInviteSchema.safeParse({ organizationId: ORG, inviteId: INVITE }).success).toBe(true);
    expect(revokeInviteSchema.safeParse({ organizationId: ORG, inviteId: 'not-a-uuid' }).success).toBe(false);
    expect(acceptInviteSchema.safeParse({ token: TOKEN }).success).toBe(true);
    expect(acceptInviteSchema.safeParse({ token: 'abc' }).success).toBe(false);
  });
});

describe('organization invite labels', () => {
  it('labels every invite status in Arabic and never leaks raw codes', () => {
    expect(inviteStatusLabel('PENDING')).toBe('بانتظار القبول');
    expect(inviteStatusLabel('ACCEPTED')).toBe('مقبولة');
    expect(inviteStatusLabel('REVOKED')).toBe('ملغاة');
    expect(inviteStatusLabel('EXPIRED')).toBe('منتهية الصلاحية');
  });
});
