import type { ActionState } from '@/features/auth/actions';

/**
 * Canonical client-side idempotency-key lifecycle for command forms.
 *
 * Codified in AGENTS.md ("Client idempotency-key lifecycle") and proven by
 * the GF-020 Livestock forms. Shared because at least two real consumers
 * exist (Livestock sector forms and R1 Portfolio forms).
 *
 * Invariant: one logical command attempt owns exactly one idempotency key.
 *
 * The key MUST survive double-submit protection, network/server retries,
 * validation failure, authentication/authorization failure and any other
 * unsuccessful result, because in every one of those cases the operator is
 * still retrying the SAME logical command. A NEW key is issued only after the
 * server has CONFIRMED success, so the same mounted form can immediately run a
 * second, logically distinct command without a page refresh, a route remount,
 * or a payload-mismatch error.
 *
 * Confirmed success is communicated through a monotonic `successCount` on the
 * action state rather than through the absence of an error, which would be
 * ambiguous with the initial state. A failure carries the previous count
 * forward (same key); a confirmed success increments it (fresh key).
 *
 * The per-mount nonce is generated in the owning Server Component and passed
 * into the Client Component as a serializable prop. It is never produced
 * during a client render, so the server-rendered HTML and the hydrated client
 * derive the exact same key for the first submit.
 */

/** Generates a per-mount nonce. Call this only from a Server Component. */
export function newCommandNonce(): string {
  return crypto.randomUUID();
}

/** Derives the key owned by the current logical attempt. */
export function commandIdempotencyKey(
  prefix: string,
  nonce: string,
  successCount: number,
): string {
  return `${prefix}-${nonce}-${successCount}`;
}

/** Confirmed success: advance the monotonic marker so the next attempt rotates. */
export function commandSuccessState(prev: ActionState): ActionState {
  return { successCount: (prev.successCount ?? 0) + 1 };
}

/** Unsuccessful result: carry the marker forward so the current key survives. */
export function commandFailureState(prev: ActionState, error: string): ActionState {
  return { error, successCount: prev.successCount ?? 0 };
}
