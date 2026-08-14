// @vitest-environment jsdom
import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { hydrateRoot } from 'react-dom/client';
import { renderToString } from 'react-dom/server';
import { SiteForm } from '@/app/(app)/projects/[projectId]/livestock/forms';

vi.mock('@/features/livestock/actions', () => ({
  createLivestockProfile: vi.fn(),
  createLivestockSite: vi.fn(),
  createLivestockHerd: vi.fn(),
  createLivestockCohort: vi.fn(),
  transitionLivestockCohort: vi.fn(),
}));

const nonce = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const expectedKey = `ls-site-${nonce}-0`;

const context = {
  organizationId: '00000000-0000-4000-8000-000000000001',
  projectId: '00000000-0000-4000-8000-000000000002',
  commandNonce: nonce,
};

function serverKeyFrom(html: string): string | undefined {
  const input = html.match(/<input[^>]*name="idempotencyKey"[^>]*>/)?.[0];
  return input?.match(/value="([^"]+)"/)?.[1];
}

describe('GF-020 nonce hydration safety (SSR → hydrate)', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('server render and client hydration agree on the idempotency key', async () => {
    const element = <SiteForm {...context} />;
    const serverHtml = renderToString(element);
    const serverKey = serverKeyFrom(serverHtml);
    expect(serverKey).toBe(expectedKey);

    const container = document.createElement('div');
    container.innerHTML = serverHtml;
    document.body.appendChild(container);

    // The node React must reuse (not replace) to prove hydration succeeded.
    const serverInput = container.querySelector('input[name="idempotencyKey"]');

    const errors: string[] = [];
    const spy = vi.spyOn(console, 'error').mockImplementation((...args) => {
      errors.push(args.map(String).join(' '));
    });

    let root: { unmount: () => void };
    await act(async () => {
      root = hydrateRoot(container, element);
    });

    const input = container.querySelector<HTMLInputElement>(
      'input[name="idempotencyKey"]',
    );
    expect(input).toBe(serverInput);
    expect(input?.value).toBe(expectedKey);
    expect(input?.value).toBe(serverKey);

    await act(async () => {
      root.unmount();
    });
    spy.mockRestore();

    const hydrationErrors = errors.filter((line) =>
      /hydration|did not match|mismatch|server-rendered|early update/i.test(line),
    );
    expect(hydrationErrors).toEqual([]);
  });

  it('the SiteForm server output derives its key deterministically from the nonce', () => {
    const first = renderToString(<SiteForm {...context} />);
    const second = renderToString(<SiteForm {...context} />);
    expect(first).toBe(second);
    expect(serverKeyFrom(first)).toBe(expectedKey);
  });
});
