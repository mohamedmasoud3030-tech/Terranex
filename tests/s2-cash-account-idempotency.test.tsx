// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import {
  commandFailureState,
  commandSuccessState,
} from '@/shared/idempotency';
import { createCashAccountCommand } from '@/features/finance/command-actions';
import { CashAccountForm } from '@/app/(app)/projects/[projectId]/cash/forms';

vi.mock('@/features/finance/command-actions', () => ({
  createCashAccountCommand: vi.fn(),
  attachContributionCashCommand: vi.fn(),
  importBankStatementCommand: vi.fn(),
  reconcilePaymentCommand: vi.fn(),
  reverseJournalBatchCommand: vi.fn(),
  voidReconciliationCommand: vi.fn(),
}));

const context = {
  organizationId: '00000000-0000-4000-8000-000000000001',
  projectId: '00000000-0000-4000-8000-000000000002',
  currency: 'OMR',
  commandNonce: '11111111-2222-4333-8444-666666666666',
};

function currentKey(container: HTMLElement): string {
  return container.querySelector<HTMLInputElement>('input[name="idempotencyKey"]')?.value ?? '';
}

async function submitAndSettle(container: HTMLElement) {
  const form = container.querySelector('form');
  if (!form) throw new Error('form not found');
  fireEvent.submit(form);
  await waitFor(() => {
    const button = screen.getByRole('button', { name: 'إنشاء حساب نقدي' }) as HTMLButtonElement;
    expect(button.disabled).toBe(false);
  });
}

describe('S2 cash-account idempotency correction', () => {
  beforeEach(() => vi.mocked(createCashAccountCommand).mockReset());
  afterEach(() => cleanup());

  it('keeps the same key after failure and rotates only after confirmed success', async () => {
    vi.mocked(createCashAccountCommand)
      .mockImplementationOnce(async (prev) => commandFailureState(prev ?? {}, 'تعذر الإنشاء'))
      .mockImplementationOnce(async (prev) => commandSuccessState(prev ?? {}));

    const { container } = render(<CashAccountForm {...context} />);
    const firstKey = currentKey(container);
    expect(firstKey).toBe(`cash-account-${context.commandNonce}-0`);

    fireEvent.change(container.querySelector('input[name="name"]')!, {
      target: { value: 'حساب المشروع' },
    });

    await submitAndSettle(container);
    expect(currentKey(container)).toBe(firstKey);

    await submitAndSettle(container);
    expect(currentKey(container)).toBe(`cash-account-${context.commandNonce}-1`);
  });

  it('locks the forward migration to a retry-safe RPC contract with a safe legacy overload', () => {
    const sql = readFileSync(
      'supabase/migrations/20260817010000_s2_cash_account_idempotency.sql',
      'utf8',
    );

    expect(sql).toContain('p_idempotency_key text');
    expect(sql).toContain('project_cash_accounts_idempotency_uidx');
    expect(sql).toContain('pg_advisory_xact_lock');
    expect(sql).toContain('idempotency key payload mismatch');
    expect(sql).toContain('return v_existing.id');
    expect(sql).toContain('drop function public.create_project_cash_account(uuid, uuid, text, text)');
    expect(sql).toContain("'legacy-' || pg_catalog.md5(");
    expect(sql).toContain('security invoker');
    expect(sql).toContain(
      'grant execute on function public.create_project_cash_account(uuid, uuid, text, text, text)',
    );
    expect(sql).toContain(
      'grant execute on function public.create_project_cash_account(uuid, uuid, text, text)',
    );
  });

  it('removes sticky render-time random UUID keys from the active cash forms', () => {
    const source = readFileSync(
      'src/app/(app)/projects/[projectId]/cash/forms.tsx',
      'utf8',
    );
    expect(source).not.toContain('crypto.randomUUID()');
    expect(source).toContain('useCommandIdempotencyKey');
  });
});
