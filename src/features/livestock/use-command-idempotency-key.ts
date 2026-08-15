/**
 * GF-020 command-form idempotency hook.
 *
 * R1 (Portfolio Foundation) promoted the canonical implementation to
 * `@/shared/idempotency`. This shim preserves the existing GF-020 import
 * path and behavior exactly.
 */
export { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
