'use client';

import { useMemo, useState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import { commandIdempotencyKey, newCommandNonce } from './idempotency';

/**
 * Owns the current idempotency key for a mounted command form.
 *
 * The returned key is stable while the action state reports the same
 * `successCount` — failed retries reuse it — and rotates exactly once after a
 * confirmed success increments `successCount`. A per-mount nonce keeps keys
 * unique across remounts without touching the server/database guarantees.
 */
export function useCommandIdempotencyKey(prefix: string, state: ActionState): string {
  const [nonce] = useState(newCommandNonce);
  const successCount = state.successCount ?? 0;
  return useMemo(
    () => commandIdempotencyKey(prefix, nonce, successCount),
    [prefix, nonce, successCount],
  );
}
