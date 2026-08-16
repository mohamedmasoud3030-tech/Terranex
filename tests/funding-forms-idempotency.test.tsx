// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, waitFor } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createAgreementDraft, createCapitalCall } from '@/features/funding/actions';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import { AgreementDraftForm } from '@/app/(app)/projects/[projectId]/terms/forms';
import { CapitalCallForm } from '@/app/(app)/projects/[projectId]/funding/forms';

vi.mock('@/features/funding/actions', () => ({
  createParty: vi.fn(),
  addParticipant: vi.fn(),
  createAgreementDraft: vi.fn(),
  activateAgreementVersion: vi.fn(),
  createCapitalCall: vi.fn(),
  recordContribution: vi.fn(),
}));

const organizationId = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';
const participantId = '00000000-0000-4000-8000-000000000003';
const versionId = '00000000-0000-4000-8000-000000000004';
const serverNonce = '11111111-2222-4333-8444-666666666666';

const participant = {
  id: participantId,
  project_id: projectId,
  party_id: '00000000-0000-4000-8000-000000000005',
  parties: { legal_name: 'مستثمر الاختبار' },
};

function currentKey(container: HTMLElement): string {
  return container.querySelector<HTMLInputElement>('input[name="idempotencyKey"]')?.value ?? '';
}

async function submitAndSettle(container: HTMLElement) {
  const form = container.querySelector('form');
  if (!form) throw new Error('form not found');
  fireEvent.submit(form);
  await waitFor(() => {
    const button = container.querySelector<HTMLButtonElement>('button[type="submit"], button:not([type])');
    expect(button?.disabled ?? false).toBe(false);
  });
}

describe('funding command idempotency lifecycle', () => {
  beforeEach(() => {
    vi.mocked(createAgreementDraft).mockReset();
    vi.mocked(createCapitalCall).mockReset();
  });

  afterEach(() => cleanup());

  it('keeps the agreement key on failure and rotates it only after confirmed success', async () => {
    vi.mocked(createAgreementDraft)
      .mockImplementationOnce(async (prev) => commandFailureState(prev ?? {}, 'تعذر الحفظ'))
      .mockImplementationOnce(async (prev) => commandSuccessState(prev ?? {}));

    const { container } = render(
      <AgreementDraftForm
        organizationId={organizationId}
        projectId={projectId}
        participants={[participant] as never}
        currency="EGP"
        serverNonce={serverNonce}
      />,
    );

    const firstKey = currentKey(container);
    expect(firstKey).toBe(`agreement-${serverNonce}-0`);

    await submitAndSettle(container);
    expect(currentKey(container)).toBe(firstKey);

    await submitAndSettle(container);
    expect(currentKey(container)).toBe(`agreement-${serverNonce}-1`);
    expect(currentKey(container)).not.toBe(firstKey);
  });

  it('rotates capital-call keys across distinct successful commands', async () => {
    vi.mocked(createCapitalCall).mockImplementation(async (prev) => commandSuccessState(prev ?? {}));

    const commitments = [{
      id: '00000000-0000-4000-8000-000000000006',
      agreement_version_id: versionId,
      participant_id: participantId,
      commitment_minor_units: '100000',
      currency: 'EGP',
    }];

    const { container } = render(
      <CapitalCallForm
        organizationId={organizationId}
        projectId={projectId}
        versionId={versionId}
        currency="EGP"
        participants={[participant] as never}
        commitments={commitments as never}
        serverNonce={serverNonce}
      />,
    );

    const firstKey = currentKey(container);
    expect(firstKey).toBe(`call-${serverNonce}-0`);

    await submitAndSettle(container);
    const secondKey = currentKey(container);
    expect(secondKey).toBe(`call-${serverNonce}-1`);

    await submitAndSettle(container);
    expect(currentKey(container)).toBe(`call-${serverNonce}-2`);
    expect(secondKey).not.toBe(firstKey);
  });

  it('does not reintroduce render-time random UUID keys in funding forms', () => {
    const termsSource = readFileSync(resolve('src/app/(app)/projects/[projectId]/terms/forms.tsx'), 'utf8');
    const fundingSource = readFileSync(resolve('src/app/(app)/projects/[projectId]/funding/forms.tsx'), 'utf8');

    expect(termsSource).not.toContain('crypto.randomUUID()');
    expect(fundingSource).not.toContain('crypto.randomUUID()');
    expect(termsSource).toContain('useCommandIdempotencyKey');
    expect(fundingSource.match(/useCommandIdempotencyKey/g)?.length ?? 0).toBeGreaterThanOrEqual(3);
  });
});
