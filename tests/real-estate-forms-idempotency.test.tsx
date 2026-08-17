// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, waitFor } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import { createAsset } from '@/features/real-estate/command-actions';
import { AssetForm } from '@/app/(app)/projects/[projectId]/operations/forms';

vi.mock('@/features/real-estate/command-actions', () => ({
  approveBudget: vi.fn(),
  approveValuation: vi.fn(),
  classifyCost: vi.fn(),
  confirmSectorEvent: vi.fn(),
  createAsset: vi.fn(),
  createMilestone: vi.fn(),
  createParcel: vi.fn(),
  createPhase: vi.fn(),
  createProfile: vi.fn(),
  proposeBudget: vi.fn(),
  proposeValuation: vi.fn(),
  recordAcquisition: vi.fn(),
  recordControl: vi.fn(),
  transitionMilestone: vi.fn(),
  transitionPhase: vi.fn(),
  transitionProperty: vi.fn(),
}));

const organizationId = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';

function currentKey(container: HTMLElement): string {
  return container.querySelector<HTMLInputElement>('input[name="idempotencyKey"]')?.value ?? '';
}

async function ready(container: HTMLElement) {
  await waitFor(() => {
    expect(currentKey(container)).not.toBe('');
    const button = container.querySelector<HTMLButtonElement>('button');
    expect(button?.disabled).toBe(false);
  });
}

async function submitAndSettle(container: HTMLElement) {
  const form = container.querySelector('form');
  if (!form) throw new Error('form not found');
  fireEvent.submit(form);
  await waitFor(() => {
    const button = container.querySelector<HTMLButtonElement>('button');
    expect(button?.disabled ?? false).toBe(false);
  });
}

describe('real-estate command idempotency lifecycle', () => {
  beforeEach(() => {
    vi.mocked(createAsset).mockReset();
  });

  afterEach(() => cleanup());

  it('preserves one logical command key across failure and rotates after confirmed success', async () => {
    vi.mocked(createAsset)
      .mockImplementationOnce(async (prev) => commandFailureState(prev ?? {}, 'تعذر الحفظ'))
      .mockImplementationOnce(async (prev) => commandSuccessState(prev ?? {}));

    const { container } = render(<AssetForm organizationId={organizationId} projectId={projectId} />);
    await ready(container);

    const firstKey = currentKey(container);
    expect(firstKey).toMatch(/^re-asset-.+-0$/);

    await submitAndSettle(container);
    expect(currentKey(container)).toBe(firstKey);

    await submitAndSettle(container);
    const secondKey = currentKey(container);
    expect(secondKey).toMatch(/^re-asset-.+-1$/);
    expect(secondKey).not.toBe(firstKey);
  });

  it('removes render-time sticky UUID keys from every active real-estate command form', () => {
    const formsSource = readFileSync(resolve('src/app/(app)/projects/[projectId]/operations/forms.tsx'), 'utf8');
    const adapterSource = readFileSync(resolve('src/features/real-estate/command-actions.ts'), 'utf8');

    expect(formsSource).not.toContain('useMemo');
    expect(formsSource).not.toContain('crypto.randomUUID()');
    expect(formsSource).toContain("@/features/real-estate/command-actions");
    expect(formsSource).toContain('commandIdempotencyKey');
    expect(formsSource).toContain('state={state}');
    expect(adapterSource).toContain('commandSuccessState');
    expect(adapterSource).toContain('commandFailureState');
  });
});
