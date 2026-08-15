/**
 * GF-020 command-form idempotency helpers.
 *
 * R1 (Portfolio Foundation) made the client idempotency-key lifecycle a
 * second real consumer, so the canonical implementation now lives in
 * `@/shared/idempotency`. This module is kept as a re-export shim so every
 * existing GF-020 import path and test continues to work unchanged.
 */
export {
  commandFailureState,
  commandIdempotencyKey,
  commandSuccessState,
  newCommandNonce,
} from '@/shared/idempotency';
