import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

const costsPage = readFileSync(
  'src/app/(app)/projects/[projectId]/costs/page.tsx',
  'utf8',
);
const safeForms = readFileSync(
  'src/app/(app)/projects/[projectId]/costs/finance-command-forms.tsx',
  'utf8',
);
const cashForms = readFileSync(
  'src/app/(app)/projects/[projectId]/cash/forms.tsx',
  'utf8',
);

describe('finance command form lifecycle guards', () => {
  it('routes active legacy finance commands through the retry-safe forms module', () => {
    expect(costsPage).toContain("from './finance-command-forms';");
    expect(safeForms).toContain('useCommandIdempotencyKey');
    expect(safeForms).not.toContain('crypto.randomUUID()');
  });

  it('seeds every active costs command form with a server nonce', () => {
    for (const component of [
      'ObligationForm',
      'AuthorizeObligationButton',
      'PaymentForm',
      'ApprovePaymentProposalButton',
      'ReverseBatchForm',
    ]) {
      const usage = new RegExp(`<${component}[\\s\\S]*?commandNonce=\\{newCommandNonce\\(\\)\\}[\\s\\S]*?/>`);
      expect(costsPage).toMatch(usage);
    }
  });

  it('keeps active cash forms free of sticky render-time UUID keys', () => {
    expect(cashForms).toContain('useCommandIdempotencyKey');
    expect(cashForms).not.toContain('crypto.randomUUID()');
  });
});
