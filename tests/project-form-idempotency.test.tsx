// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import NewProjectForm from '@/app/(app)/projects/new/project-form';
import { createProject } from '@/features/projects/actions';
import { commandFailureState } from '@/shared/idempotency';

vi.mock('@/features/projects/actions', () => ({
  createProject: vi.fn(),
}));

const organizationId = '10000000-0000-4000-8000-000000000001';
const commandNonce = '11111111-2222-4333-8444-666666666666';
const expectedKey = `project-create-${commandNonce}-0`;

function formElement(container: HTMLElement): HTMLFormElement {
  const form = container.querySelector('form');
  if (!form) throw new Error('form not found');
  return form;
}

function currentKey(container: HTMLElement): string {
  return container.querySelector<HTMLInputElement>('input[name="idempotencyKey"]')?.value ?? '';
}

function fillName(container: HTMLElement, value: string) {
  const input = container.querySelector<HTMLInputElement>('input[name="name"]');
  if (!input) throw new Error('project name input not found');
  fireEvent.change(input, { target: { value } });
}

async function submitAndSettle(container: HTMLElement) {
  fireEvent.submit(formElement(container));
  await waitFor(() => {
    expect((screen.getByRole('button', { name: 'إنشاء المشروع' }) as HTMLButtonElement).disabled).toBe(false);
  });
}

describe('Project creation idempotency lifecycle', () => {
  beforeEach(() => {
    vi.mocked(createProject).mockReset();
  });

  afterEach(() => {
    cleanup();
  });

  it('derives the first command key from the server-provided nonce', () => {
    const { container } = render(
      <NewProjectForm organizationId={organizationId} commandNonce={commandNonce} />,
    );
    expect(currentKey(container)).toBe(expectedKey);
  });

  it('preserves the same key across failed retries of the logical command', async () => {
    const submitted: string[] = [];
    vi.mocked(createProject).mockImplementation(async (prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return commandFailureState(prev ?? {}, 'تعذر الحفظ');
    });

    const { container } = render(
      <NewProjectForm organizationId={organizationId} commandNonce={commandNonce} />,
    );
    fillName(container, 'مشروع اختبار idempotency');

    await submitAndSettle(container);
    await submitAndSettle(container);

    expect(submitted).toEqual([expectedKey, expectedKey]);
    expect(currentKey(container)).toBe(expectedKey);
  });
});
