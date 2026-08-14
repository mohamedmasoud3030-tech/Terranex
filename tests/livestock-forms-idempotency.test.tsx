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
import { createLivestockSite } from '@/features/livestock/actions';
import {
  commandFailureState,
  commandSuccessState,
} from '@/features/livestock/idempotency';
import { SiteForm } from '@/app/(app)/projects/[projectId]/livestock/forms';

vi.mock('@/features/livestock/actions', () => ({
  createLivestockProfile: vi.fn(),
  createLivestockSite: vi.fn(),
  createLivestockHerd: vi.fn(),
  createLivestockCohort: vi.fn(),
  transitionLivestockCohort: vi.fn(),
}));

const context = {
  organizationId: '00000000-0000-4000-8000-000000000001',
  projectId: '00000000-0000-4000-8000-000000000002',
  commandNonce: '11111111-2222-4333-8444-555555555555',
};

/** The deterministic key the SiteForm must derive from the server nonce. */
const keyAt = (successCount: number) => `ls-site-${context.commandNonce}-${successCount}`;

function formElement(container: HTMLElement): HTMLFormElement {
  const form = container.querySelector('form');
  if (!form) throw new Error('form not found');
  return form;
}

function currentKey(container: HTMLElement): string {
  const input = container.querySelector<HTMLInputElement>('input[name="idempotencyKey"]');
  return input?.value ?? '';
}

function fillSite(container: HTMLElement, name: string, reference: string) {
  const nameInput = container.querySelector<HTMLInputElement>('input[name="name"]');
  const referenceInput = container.querySelector<HTMLInputElement>(
    'input[name="internalReference"]',
  );
  if (!nameInput || !referenceInput) throw new Error('Site inputs not found');
  fireEvent.change(nameInput, { target: { value: name } });
  fireEvent.change(referenceInput, { target: { value: reference } });
}

function submitButton(): HTMLButtonElement {
  return screen.getByRole('button', { name: 'إضافة موقع التشغيل' }) as HTMLButtonElement;
}

/** Fires the form's submit event and waits for the pending flag to clear. */
async function submitAndSettle(container: HTMLElement) {
  fireEvent.submit(formElement(container));
  await waitFor(() => expect(submitButton().disabled).toBe(false));
}

describe('GF-020 idempotency-key lifecycle (SiteForm integration)', () => {
  beforeEach(() => {
    vi.mocked(createLivestockSite).mockReset();
  });

  afterEach(() => {
    cleanup();
  });

  it('CASE A: a failed attempt preserves the same key for the retried command', async () => {
    const submitted: string[] = [];
    vi.mocked(createLivestockSite).mockImplementation(async (prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return commandFailureState(prev ?? {}, 'البيانات غير صحيحة');
    });

    const { container } = render(<SiteForm {...context} />);
    const firstKey = currentKey(container);
    expect(firstKey).toBe(keyAt(0));

    fillSite(container, 'مزرعة التسمين', 'SITE-A');
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
    vi.mocked(createLivestockSite).mockImplementation(async (prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return commandSuccessState(prev ?? {});
    });

    const { container } = render(<SiteForm {...context} />);
    const firstKey = currentKey(container);

    fillSite(container, 'مزرعة التسمين', 'SITE-A');
    await submitAndSettle(container);

    expect(submitted).toHaveLength(1);
    expect(submitted[0]).toBe(firstKey);

    const nextKey = currentKey(container);
    expect(nextKey).toBe(keyAt(1));
    expect(nextKey).not.toBe(firstKey);
  });

  it('CASE C: two distinct successful commands work from the same mounted form', async () => {
    const submitted: string[] = [];
    vi.mocked(createLivestockSite).mockImplementation(async (prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return commandSuccessState(prev ?? {});
    });

    const { container } = render(<SiteForm {...context} />);
    const firstKey = currentKey(container);

    fillSite(container, 'مزرعة التسمين', 'SITE-A');
    await submitAndSettle(container);
    expect(submitted[0]).toBe(firstKey);

    const secondKey = currentKey(container);
    expect(secondKey).not.toBe(firstKey);

    // A second, distinct payload without any remount or refresh.
    fillSite(container, 'حظيرة العجول', 'SITE-B');
    await submitAndSettle(container);

    expect(submitted).toHaveLength(2);
    expect(submitted[1]).toBe(secondKey);
    expect(submitted[1]).not.toBe(firstKey);

    const thirdKey = currentKey(container);
    expect(thirdKey).toBe(keyAt(2));
  });

  it('CASE D: a pending submit does not rotate the key before confirmed success', async () => {
    const submitted: string[] = [];
    let resolveAction: (state: ActionState) => void = () => {};
    vi.mocked(createLivestockSite).mockImplementation((_prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return new Promise<ActionState>((resolve) => {
        resolveAction = resolve;
      });
    });

    const { container } = render(<SiteForm {...context} />);
    const firstKey = currentKey(container);

    fillSite(container, 'مزرعة التسمين', 'SITE-A');
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
    vi.mocked(createLivestockSite).mockImplementation(async (prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return commandFailureState(prev ?? {}, 'تعذر الحفظ');
    });

    const { container } = render(<SiteForm {...context} />);
    const firstKey = currentKey(container);
    expect(firstKey).toBe(keyAt(0));

    fillSite(container, 'مزرعة التسمين', 'SITE-A');
    await submitAndSettle(container);
    await submitAndSettle(container);
    await submitAndSettle(container);

    expect(submitted).toHaveLength(3);
    expect(submitted.every((key) => key === firstKey)).toBe(true);
    expect(currentKey(container)).toBe(firstKey);
  });
});
