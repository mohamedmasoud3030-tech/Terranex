// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import type { ActionState } from '@/features/auth/actions';
import { createPortfolio } from '@/features/portfolios/actions';
import {
  commandFailureState,
  commandSuccessState,
} from '@/shared/idempotency';
import { PortfolioForm } from '@/app/(app)/portfolios/forms';

vi.mock('@/features/portfolios/actions', () => ({
  createPortfolio: vi.fn(),
  updatePortfolio: vi.fn(),
  transitionPortfolio: vi.fn(),
  assignProjectToPortfolio: vi.fn(),
  removeProjectFromPortfolio: vi.fn(),
  moveProjectToPortfolio: vi.fn(),
}));

const context = {
  organizationId: '00000000-0000-4000-8000-000000000001',
  commandNonce: '11111111-2222-4333-8444-666666666666',
  members: [],
};

/** The deterministic key the PortfolioForm must derive from the server nonce. */
const keyAt = (successCount: number) => `pf-create-${context.commandNonce}-${successCount}`;

function formElement(container: HTMLElement): HTMLFormElement {
  const form = container.querySelector('form');
  if (!form) throw new Error('form not found');
  return form;
}

function currentKey(container: HTMLElement): string {
  const input = container.querySelector<HTMLInputElement>('input[name="idempotencyKey"]');
  return input?.value ?? '';
}

function fillPortfolio(container: HTMLElement, name: string, purpose: string) {
  const nameInput = container.querySelector<HTMLInputElement>('input[name="name"]');
  const descriptionInput = container.querySelector<HTMLTextAreaElement>(
    'textarea[name="description"]',
  );
  if (!nameInput || !descriptionInput) throw new Error('Portfolio inputs not found');
  fireEvent.change(nameInput, { target: { value: name } });
  fireEvent.change(descriptionInput, { target: { value: purpose } });
}

function submitButton(): HTMLButtonElement {
  return screen.getByRole('button', { name: 'إنشاء المحفظة' }) as HTMLButtonElement;
}

/** Fires the form's submit event and waits for the pending flag to clear. */
async function submitAndSettle(container: HTMLElement) {
  fireEvent.submit(formElement(container));
  await waitFor(() => expect(submitButton().disabled).toBe(false));
}

describe('R1 idempotency-key lifecycle (PortfolioForm integration)', () => {
  beforeEach(() => {
    vi.mocked(createPortfolio).mockReset();
  });

  afterEach(() => {
    cleanup();
  });

  it('CASE A: a failed attempt preserves the same key for the retried command', async () => {
    const submitted: string[] = [];
    vi.mocked(createPortfolio).mockImplementation(async (prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return commandFailureState(prev ?? {}, 'اسم المحفظة مطلوب');
    });

    const { container } = render(<PortfolioForm {...context} />);
    const firstKey = currentKey(container);
    expect(firstKey).toBe(keyAt(0));

    fillPortfolio(container, 'محفظة النمو', 'تنظيم مشاريع النمو');
    await submitAndSettle(container);

    expect(submitted).toHaveLength(1);
    expect(submitted[0]).toBe(firstKey);
    expect(currentKey(container)).toBe(firstKey);

    // Retry the same logical command: the same key is sent again.
    await submitAndSettle(container);

    expect(submitted).toHaveLength(2);
    expect(submitted[1]).toBe(firstKey);
    expect(currentKey(container)).toBe(firstKey);
  });

  it('CASE B: a confirmed success rotates to a fresh key', async () => {
    const submitted: string[] = [];
    vi.mocked(createPortfolio).mockImplementation(async (prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return commandSuccessState(prev ?? {});
    });

    const { container } = render(<PortfolioForm {...context} />);
    const firstKey = currentKey(container);

    fillPortfolio(container, 'محفظة النمو', 'تنظيم مشاريع النمو');
    await submitAndSettle(container);

    expect(submitted).toHaveLength(1);
    expect(submitted[0]).toBe(firstKey);

    const nextKey = currentKey(container);
    expect(nextKey).toBe(keyAt(1));
    expect(nextKey).not.toBe(firstKey);
  });

  it('CASE C: two distinct successful submissions use distinct keys (no GF-020 nonce reuse)', async () => {
    const submitted: string[] = [];
    vi.mocked(createPortfolio).mockImplementation(async (prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return commandSuccessState(prev ?? {});
    });

    const { container } = render(<PortfolioForm {...context} />);
    const firstKey = currentKey(container);

    fillPortfolio(container, 'محفظة النمو', 'تنظيم مشاريع النمو');
    await submitAndSettle(container);
    expect(submitted[0]).toBe(firstKey);

    const secondKey = currentKey(container);
    expect(secondKey).not.toBe(firstKey);

    // A second, distinct portfolio from the same mounted form/session.
    fillPortfolio(container, 'محفظة الدخل', 'تنظيم مشاريع الدخل');
    await submitAndSettle(container);

    expect(submitted).toHaveLength(2);
    expect(submitted[1]).toBe(secondKey);
    expect(submitted[1]).not.toBe(firstKey);

    expect(currentKey(container)).toBe(keyAt(2));
  });

  it('CASE D: a pending submit does not rotate the key before confirmed success', async () => {
    const submitted: string[] = [];
    let resolveAction: (state: ActionState) => void = () => {};
    vi.mocked(createPortfolio).mockImplementation((_prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return new Promise<ActionState>((resolve) => {
        resolveAction = resolve;
      });
    });

    const { container } = render(<PortfolioForm {...context} />);
    const firstKey = currentKey(container);

    fillPortfolio(container, 'محفظة النمو', 'تنظيم مشاريع النمو');
    fireEvent.submit(formElement(container));
    await waitFor(() => expect(submitted).toHaveLength(1));

    // While the submit is still pending, the key must not have rotated.
    expect(submitted[0]).toBe(firstKey);
    expect(currentKey(container)).toBe(firstKey);

    // Confirm success: only now does the key rotate.
    await act(async () => {
      resolveAction(commandSuccessState({}));
    });
    await waitFor(() => expect(currentKey(container)).toBe(keyAt(1)));
  });

  it('CASE E: repeated failures of the same command keep the same key', async () => {
    const submitted: string[] = [];
    vi.mocked(createPortfolio).mockImplementation(async (prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return commandFailureState(prev ?? {}, 'تعذر الحفظ');
    });

    const { container } = render(<PortfolioForm {...context} />);
    const firstKey = currentKey(container);
    expect(firstKey).toBe(keyAt(0));

    fillPortfolio(container, 'محفظة النمو', 'تنظيم مشاريع النمو');
    await submitAndSettle(container);
    await submitAndSettle(container);
    await submitAndSettle(container);

    expect(submitted).toHaveLength(3);
    expect(submitted.every((key) => key === firstKey)).toBe(true);
    expect(currentKey(container)).toBe(firstKey);
  });
});
