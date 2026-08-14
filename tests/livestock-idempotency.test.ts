import { describe, expect, it } from 'vitest';
import {
  commandFailureState,
  commandIdempotencyKey,
  commandSuccessState,
} from '../src/features/livestock/idempotency';

const prefix = 'ls-site';
const nonce = '11111111-1111-4111-8111-111111111111';

describe('GF-020 client idempotency-key lifecycle', () => {
  it('derives a stable key for a single logical attempt', () => {
    expect(commandIdempotencyKey(prefix, nonce, 0)).toBe(
      commandIdempotencyKey(prefix, nonce, 0),
    );
  });

  it('CASE A: a failed attempt preserves the key for the retry of the same command', () => {
    const failed = commandFailureState({}, 'بيانات غير صحيحة');
    expect(failed.successCount).toBe(0);
    expect(commandIdempotencyKey(prefix, nonce, failed.successCount ?? 0)).toBe(
      commandIdempotencyKey(prefix, nonce, 0),
    );
  });

  it('CASE B: confirmed success advances the marker and rotates the key', () => {
    const success = commandSuccessState({});
    expect(success.successCount).toBe(1);
    expect(commandIdempotencyKey(prefix, nonce, success.successCount ?? 0)).not.toBe(
      commandIdempotencyKey(prefix, nonce, 0),
    );
  });

  it('CASE C: two confirmed successes yield distinct keys for consecutive commands', () => {
    const first = commandSuccessState({});
    const second = commandSuccessState(first);
    expect(first.successCount).toBe(1);
    expect(second.successCount).toBe(2);
    const keys = new Set([
      commandIdempotencyKey(prefix, nonce, 0),
      commandIdempotencyKey(prefix, nonce, first.successCount ?? 0),
      commandIdempotencyKey(prefix, nonce, second.successCount ?? 0),
    ]);
    expect(keys.size).toBe(3);
  });

  it('CASE D: an in-flight (unconfirmed) attempt does not rotate the key', () => {
    const pending = {};
    expect(commandIdempotencyKey(prefix, nonce, pending.successCount ?? 0)).toBe(
      commandIdempotencyKey(prefix, nonce, 0),
    );
  });

  it('CASE E: repeated failures of the same command keep the same key', () => {
    let state = {};
    for (let attempt = 0; attempt < 3; attempt += 1) {
      state = commandFailureState(state, `خطأ ${attempt}`);
    }
    expect(state.successCount).toBe(0);
    expect(commandIdempotencyKey(prefix, nonce, state.successCount ?? 0)).toBe(
      commandIdempotencyKey(prefix, nonce, 0),
    );
  });

  it('preserves the success marker across a failure after a prior success', () => {
    const afterSuccess = commandSuccessState({});
    const thenFailed = commandFailureState(afterSuccess, 'خطأ');
    expect(thenFailed.successCount).toBe(1);
    expect(thenFailed.error).toBe('خطأ');
    // The second logical command must keep its own key, not regress to the first.
    expect(commandIdempotencyKey(prefix, nonce, thenFailed.successCount ?? 0)).toBe(
      commandIdempotencyKey(prefix, nonce, 1),
    );
  });

  it('distinguishes initial, failure, and success without relying on error absence', () => {
    expect({}.successCount).toBeUndefined();
    expect(commandFailureState({}, 'خطأ').successCount).toBe(0);
    expect(commandSuccessState({}).successCount).toBe(1);
  });
});
