import { z } from 'zod';

const uuid = z.string().uuid('معرّف غير صالح');
const idempotencyKey = z.string().trim().min(8).max(120);

/** 64 hex chars: two v4 UUIDs without dashes, as minted by the database. */
export const inviteToken = z
  .string()
  .trim()
  .regex(/^[0-9a-f]{64}$/, 'رابط الدعوة غير صالح');

export const createInviteSchema = z.object({
  organizationId: uuid,
  note: z.preprocess(
    (value) => (value === '' ? null : value),
    z.string().trim().max(200, 'الملاحظة طويلة جدًا').nullable(),
  ),
  idempotencyKey,
});

export const revokeInviteSchema = z.object({
  organizationId: uuid,
  inviteId: uuid,
});

export const acceptInviteSchema = z.object({
  token: inviteToken,
});
