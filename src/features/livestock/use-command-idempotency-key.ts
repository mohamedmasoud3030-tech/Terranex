'use client';

import { useMemo, useState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import { commandIdempotencyKey } from './idempotency';

/**
 * Owns the current idempotency key for a mounted command form.
 *
 * The nonce is generated in the owning Server Component and passed in as
 * `serverNonce`, so the server-rendered HTML and the client hydration agree on
 * the exact same key — no random value is produced during a client render. The
 * key is stable while the action state reports the same `successCount` (failed
 * retries reuse it) and rotates exactly once after a confirmed success
 * increments `successCount`.
 */
export function useCommandIdempotencyKey(
  prefix: string,
  state: ActionState,
  serverNonce: string,
): string {
  const [nonce] = useState(serverNonce);
  const successCount = state.successCount ?? 0;
  return useMemo(
    () => commandIdempotencyKey(prefix, nonce, successCount),
    [prefix, nonce, successCount],
  );
}
