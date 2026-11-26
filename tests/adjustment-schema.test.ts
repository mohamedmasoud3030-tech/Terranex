import { describe, expect, it } from 'vitest';
import { adjustmentSchema } from '@/features/adjustments/schema';

const base = {
  organizationId: '11111111-1111-4111-8111-111111111111',
  projectId: '22222222-2222-4222-8222-222222222222',
  currency: 'EGP',
  fromRole: 'DEVELOPMENT_WIP',
  toRole: 'PROJECT_EXPENSE',
  amount: '1500.50',
  entryDate: '2026-11-01',
  memo: 'إعادة تصنيف',
  evidenceReference: 'DOC-1',
  idempotencyKey: 'manual-adjustment-abc12345',
};

describe('adjustmentSchema', () => {
  it('accepts a valid reclassification', () => {
    expect(adjustmentSchema.safeParse(base).success).toBe(true);
  });
  it('rejects cash and revenue roles', () => {
    expect(adjustmentSchema.safeParse({ ...base, toRole: 'CASH' }).success).toBe(false);
    expect(adjustmentSchema.safeParse({ ...base, fromRole: 'REVENUE' }).success).toBe(false);
  });
  it('rejects same account on both sides', () => {
    expect(adjustmentSchema.safeParse({ ...base, toRole: 'DEVELOPMENT_WIP' }).success).toBe(false);
  });
  it('rejects zero and malformed amounts', () => {
    expect(adjustmentSchema.safeParse({ ...base, amount: '0' }).success).toBe(false);
    expect(adjustmentSchema.safeParse({ ...base, amount: 'abc' }).success).toBe(false);
  });
});
