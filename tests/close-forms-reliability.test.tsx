// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, waitFor } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import {
  approveCloseRunAction,
  createAccountingPeriodAction,
} from '@/features/close/command-actions';
import {
  ApproveCloseForm,
  CreateAccountingPeriodForm,
} from '@/app/(app)/projects/[projectId]/close/forms';

vi.mock('@/features/close/command-actions', () => ({
  approveCloseExceptionAction: vi.fn(),
  approveCloseRunAction: vi.fn(),
  approveCorrectionAction: vi.fn(),
  createAccountingPeriodAction: vi.fn(),
  executeCorrectionAction: vi.fn(),
  prepareCloseRunAction: vi.fn(),
  reopenPeriodAction: vi.fn(),
  requestCloseExceptionAction: vi.fn(),
  requestCorrectionAction: vi.fn(),
}));

const organizationId = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';
const closeRunId = '00000000-0000-4000-8000-000000000003';

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

describe('period-close client command reliability', () => {
  beforeEach(() => {
    vi.mocked(approveCloseRunAction).mockReset();
    vi.mocked(createAccountingPeriodAction).mockReset();
  });
  afterEach(() => cleanup());

  it('keeps the approval key across failure and rotates only after confirmed success', async () => {
    vi.mocked(approveCloseRunAction)
      .mockImplementationOnce(async (prev) => commandFailureState(prev ?? {}, 'تعذر الاعتماد'))
      .mockImplementationOnce(async (prev) => commandSuccessState(prev ?? {}));

    const { container } = render(
      <ApproveCloseForm
        organizationId={organizationId}
        projectId={projectId}
        closeRunId={closeRunId}
      />,
    );
    await ready(container);

    const firstKey = currentKey(container);
    expect(firstKey).toMatch(/^close-approve-.+-0$/);

    await submitAndSettle(container);
    expect(currentKey(container)).toBe(firstKey);

    await submitAndSettle(container);
    const secondKey = currentKey(container);
    expect(secondKey).toMatch(/^close-approve-.+-1$/);
    expect(secondKey).not.toBe(firstKey);
  });

  it('gives newly keyed period creation the same retry/rotate contract', async () => {
    vi.mocked(createAccountingPeriodAction)
      .mockImplementationOnce(async (prev) => commandFailureState(prev ?? {}, 'تعذر فتح الفترة'))
      .mockImplementationOnce(async (prev) => commandSuccessState(prev ?? {}));

    const { container } = render(
      <CreateAccountingPeriodForm
        organizationId={organizationId}
        projectId={projectId}
        startDate="2026-09-01"
        endDate="2026-09-30"
      />,
    );
    await ready(container);

    const firstKey = currentKey(container);
    expect(firstKey).toMatch(/^close-period-create-.+-0$/);

    await submitAndSettle(container);
    expect(currentKey(container)).toBe(firstKey);

    await submitAndSettle(container);
    const secondKey = currentKey(container);
    expect(secondKey).toMatch(/^close-period-create-.+-1$/);
    expect(secondKey).not.toBe(firstKey);
  });

  it('actually disables owner-only controls when the caller is not authorized', () => {
    const { container } = render(
      <CreateAccountingPeriodForm
        organizationId={organizationId}
        projectId={projectId}
        disabled
      />,
    );
    expect(container.querySelector<HTMLButtonElement>('button')?.disabled).toBe(true);
  });

  it('guards the complete S6 command surface against sticky keys and stale client behavior', () => {
    const formSource = readFileSync(resolve('src/app/(app)/projects/[projectId]/close/forms.tsx'), 'utf8');
    const adapterSource = readFileSync(resolve('src/features/close/command-actions.ts'), 'utf8');
    const actionSource = readFileSync(resolve('src/features/close/actions.ts'), 'utf8');

    expect(formSource).not.toContain('useFormStatus');
    expect(formSource).not.toContain('useStableIdempotencyKey');
    expect(formSource).not.toContain('useTodayDate');
    expect(formSource).not.toContain('useId');
    expect(formSource).not.toContain("'2026-08-11'");
    expect(formSource).not.toContain('defaultValue={today}');
    expect(formSource).not.toContain("@/features/close/actions");
    expect(formSource).toContain("@/features/close/command-actions");
    expect(formSource).toContain('useResolvedCommandNonce');
    expect(formSource.match(/<CommandKey value=\{key\}/g)?.length ?? 0).toBe(9);
    expect(formSource).not.toContain('لا تعرض الواجهة مفتاحًا وهميًا');

    expect(adapterSource).toContain('commandSuccessState');
    expect(adapterSource).toContain('commandFailureState');
    expect(adapterSource).toContain('createAccountingPeriodLegacy');
    expect(adapterSource).toContain('requestCorrectionLegacy');
    expect(adapterSource).toContain('executeCorrectionLegacy');

    expect(actionSource.match(/p_idempotency_key: input\.idempotencyKey/g)?.length ?? 0).toBe(9);
  });
});
