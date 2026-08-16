import { describe, expect, it } from 'vitest';
import { obligationSchema, paymentSchema } from '@/features/finance/schema';

const ids = {
  organizationId: '00000000-0000-4000-8000-000000000001',
  projectId: '00000000-0000-4000-8000-000000000002',
  partyId: '00000000-0000-4000-8000-000000000003',
  obligationId: '00000000-0000-4000-8000-000000000004',
  cashAccountId: '00000000-0000-4000-8000-000000000005',
};

const idempotencyKey = 'currency-validation-test-key';

describe('finance currency-aware amount validation', () => {
  it('accepts three-decimal OMR obligations and payments', () => {
    const obligation = obligationSchema.safeParse({
      organizationId: ids.organizationId,
      projectId: ids.projectId,
      partyId: ids.partyId,
      description: 'OMR obligation',
      amount: '1.234',
      currency: 'OMR',
      transactionDate: '2026-08-17',
      costTreatment: 'EXPENSE',
      idempotencyKey,
    });

    const payment = paymentSchema.safeParse({
      organizationId: ids.organizationId,
      obligationId: ids.obligationId,
      cashAccountId: ids.cashAccountId,
      amount: '1.234',
      currency: 'OMR',
      paymentDate: '2026-08-17',
      idempotencyKey,
    });

    expect(obligation.success).toBe(true);
    expect(payment.success).toBe(true);
  });

  it('rejects precision beyond the selected currency minor unit', () => {
    const omr = paymentSchema.safeParse({
      organizationId: ids.organizationId,
      obligationId: ids.obligationId,
      cashAccountId: ids.cashAccountId,
      amount: '1.2345',
      currency: 'OMR',
      paymentDate: '2026-08-17',
      idempotencyKey,
    });

    const egp = paymentSchema.safeParse({
      organizationId: ids.organizationId,
      obligationId: ids.obligationId,
      cashAccountId: ids.cashAccountId,
      amount: '1.234',
      currency: 'EGP',
      paymentDate: '2026-08-17',
      idempotencyKey,
    });

    expect(omr.success).toBe(false);
    expect(egp.success).toBe(false);
  });
});
