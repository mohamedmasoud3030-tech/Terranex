import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { bankImportSchema } from '../src/features/finance/schema';

const orgId = '00000000-0000-4000-8000-000000000001';
const accountId = '00000000-0000-4000-8000-000000000005';
const hardeningMigration = readFileSync(
  'supabase/migrations/20260811000310_s2_integrity_hardening.sql',
  'utf8',
);

describe('S2 independent-review integrity regressions', () => {
  it('rejects mixed-currency bank statement rows instead of coercing them to the first row currency', () => {
    const parsed = bankImportSchema.safeParse({
      organizationId: orgId,
      cashAccountId: accountId,
      idempotencyKey: 'import-mixed-0001',
      lines: [
        {
          transactionDate: '2026-08-25',
          amount: '-100.00',
          currency: 'EGP',
          description: 'دفعة أولى',
          providerReference: 'BANK-1',
        },
        {
          transactionDate: '2026-08-26',
          amount: '-100.00',
          currency: 'USD',
          description: 'دفعة بعملة مختلفة',
          providerReference: 'BANK-2',
        },
      ],
    });

    expect(parsed.success).toBe(false);
  });

  it('serializes one-active-source posting by financial source, not only by retry key', () => {
    expect(hardeningMigration).toContain("'s2-active-source:'");
    expect(hardeningMigration).toContain('pg_advisory_xact_lock');
    expect(hardeningMigration).toContain('source already has an active posting');
  });

  it('requires an active obligation authorization posting for every payment insert', () => {
    expect(hardeningMigration).toContain('s2_guard_payment_requires_active_obligation_posting');
    expect(hardeningMigration).toContain('payment requires an active obligation authorization posting');
    expect(hardeningMigration).toContain('reversal_of_batch_id = jb.id');
  });
});
