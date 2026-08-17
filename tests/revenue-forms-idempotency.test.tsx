// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, waitFor } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import { createDisposition } from '@/features/revenue/command-actions';
import { DispositionForm } from '@/app/(app)/projects/[projectId]/operations/revenue-forms';

vi.mock('@/features/revenue/command-actions', () => ({
  approveDisposition: vi.fn(),
  classifySellingCost: vi.fn(),
  collectReceivable: vi.fn(),
  confirmControlTransfer: vi.fn(),
  createDisposition: vi.fn(),
  recognizeSale: vi.fn(),
  reconcileCollection: vi.fn(),
}));

const organizationId = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';

function currentKey(container: HTMLElement): string {
  return container.querySelector<HTMLInputElement>('input[name="idempotencyKey"]')?.value ?? '';
}

async function ready(container: HTMLElement) {
  await waitFor(() => {
    expect(currentKey(container)).not.toBe('');
    expect(container.querySelector<HTMLButtonElement>('button')?.disabled).toBe(false);
  });
}

async function submitAndSettle(container: HTMLElement) {
  const form = container.querySelector('form');
  if (!form) throw new Error('form not found');
  fireEvent.submit(form);
  await waitFor(() => {
    expect(container.querySelector<HTMLButtonElement>('button')?.disabled ?? false).toBe(false);
  });
}

describe('property revenue command idempotency lifecycle', () => {
  beforeEach(() => vi.mocked(createDisposition).mockReset());
  afterEach(() => cleanup());

  it('keeps a disposition key on failure and rotates only after confirmed success', async () => {
    vi.mocked(createDisposition)
      .mockImplementationOnce(async (prev) => commandFailureState(prev ?? {}, 'تعذر الحفظ'))
      .mockImplementationOnce(async (prev) => commandSuccessState(prev ?? {}));

    const { container } = render(
      <DispositionForm
        organizationId={organizationId}
        projectId={projectId}
        currency="EGP"
        assets={[]}
        parties={[]}
      />,
    );
    await ready(container);

    const firstKey = currentKey(container);
    expect(firstKey).toMatch(/^re-disposition-.+-0$/);

    await submitAndSettle(container);
    expect(currentKey(container)).toBe(firstKey);

    await submitAndSettle(container);
    const secondKey = currentKey(container);
    expect(secondKey).toMatch(/^re-disposition-.+-1$/);
    expect(secondKey).not.toBe(firstKey);
  });

  it('keeps rental lifecycle isolated and removes sticky UUID keys from the sale chain', () => {
    const saleSource = readFileSync(resolve('src/app/(app)/projects/[projectId]/operations/revenue-forms.tsx'), 'utf8');
    const rentalSource = readFileSync(resolve('src/app/(app)/projects/[projectId]/revenue/rental-forms.tsx'), 'utf8');
    const adapterSource = readFileSync(resolve('src/features/revenue/command-actions.ts'), 'utf8');

    expect(saleSource).not.toContain('useMemo');
    expect(saleSource).not.toContain('crypto.randomUUID()');
    expect(saleSource).toContain("@/features/revenue/command-actions");
    expect(saleSource).toContain('commandIdempotencyKey');
    expect(saleSource.match(/state=\{state\}/g)?.length ?? 0).toBeGreaterThanOrEqual(7);
    expect(adapterSource).toContain('commandSuccessState');
    expect(adapterSource).toContain('commandFailureState');

    expect(rentalSource).toContain('useCommandIdempotencyKey');
    expect(rentalSource).not.toContain('crypto.randomUUID()');
  });
});
