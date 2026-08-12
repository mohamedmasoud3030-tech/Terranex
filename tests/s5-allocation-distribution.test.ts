import { describe, expect, it } from 'vitest';
import {
  approveAllocationSchema,
  approveDistributionSchema,
  configureRulesSchema,
  participantRuleSchema,
  payDistributionSchema,
  prepareAllocationSchema,
  prepareDistributionSchema,
} from '@/features/allocation/schema';

const organizationId = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';
const governingVersionId = '00000000-0000-4000-8000-000000000003';
const closeSnapshotId = '00000000-0000-4000-8000-000000000004';
const allocationRunId = '00000000-0000-4000-8000-000000000005';
const participantPartyId = '00000000-0000-4000-8000-000000000006';
const distributionId = '00000000-0000-4000-8000-000000000007';
const cashAccountId = '00000000-0000-4000-8000-000000000008';
const idempotencyKey = 's5-test-idempotency';

describe('S5 command schemas', () => {
  it('accepts an exact integer rule-set header and rejects fractional weights', () => {
    expect(configureRulesSchema.safeParse({
      organizationId, projectId, governingVersionId, policy: 'PRO_RATA', commonDenominator: '1000', idempotencyKey,
    }).success).toBe(true);
    expect(participantRuleSchema.safeParse({ partyId: participantPartyId, weightNumerator: '12.5' }).success).toBe(false);
  });

  it('rejects zero and negative allocation weights', () => {
    expect(participantRuleSchema.safeParse({ partyId: participantPartyId, weightNumerator: '0' }).success).toBe(false);
    expect(participantRuleSchema.safeParse({ partyId: participantPartyId, weightNumerator: '-1' }).success).toBe(false);
  });

  it('accepts allocation prepare and approval with explicit provenance/date', () => {
    expect(prepareAllocationSchema.safeParse({ organizationId, projectId, closeSnapshotId, governingVersionId, idempotencyKey }).success).toBe(true);
    expect(approveAllocationSchema.safeParse({ organizationId, projectId, allocationRunId, postingDate: '2026-08-12', idempotencyKey }).success).toBe(true);
  });

  it('rejects an allocation approval without a valid posting date', () => {
    expect(approveAllocationSchema.safeParse({ organizationId, projectId, allocationRunId, postingDate: '12/08/2026', idempotencyKey }).success).toBe(false);
  });

  it('requires distribution evidence and a currency code', () => {
    const base = { organizationId, projectId, allocationRunId, participantPartyId, amount: '10.25', currency: 'EGP', evidenceReference: 'BOARD-2026-08', idempotencyKey };
    expect(prepareDistributionSchema.safeParse(base).success).toBe(true);
    expect(prepareDistributionSchema.safeParse({ ...base, evidenceReference: '' }).success).toBe(false);
    expect(prepareDistributionSchema.safeParse({ ...base, currency: 'egp' }).success).toBe(false);
  });

  it('separates distribution approval from payment inputs', () => {
    expect(approveDistributionSchema.safeParse({ organizationId, projectId, distributionId, postingDate: '2026-08-12', idempotencyKey }).success).toBe(true);
    expect(payDistributionSchema.safeParse({
      organizationId, projectId, distributionId, cashAccountId, amount: '10.25', currency: 'EGP',
      paymentDate: '2026-08-12', evidenceReference: 'BANK-REF-001', idempotencyKey,
    }).success).toBe(true);
  });

  it('rejects payment without evidence or a valid cash account id', () => {
    const base = {
      organizationId, projectId, distributionId, cashAccountId, amount: '10.25', currency: 'EGP',
      paymentDate: '2026-08-12', evidenceReference: 'BANK-REF-001', idempotencyKey,
    };
    expect(payDistributionSchema.safeParse({ ...base, evidenceReference: '' }).success).toBe(false);
    expect(payDistributionSchema.safeParse({ ...base, cashAccountId: 'cash' }).success).toBe(false);
  });
});
