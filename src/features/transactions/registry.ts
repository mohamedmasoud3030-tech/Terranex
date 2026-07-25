/**
 * Indirection that lets `referenceValidation.ts` read the current transactions
 * without importing `transactions/storage.ts`, which imports it back.
 *
 * `transactions/storage.ts` registers its reader at module load; until then the
 * registry reports an empty list AND `isReady()` is false, so callers can tell
 * "no transactions" apart from "not wired yet" instead of silently passing a
 * uniqueness check against an empty set.
 */
import type { Transaction } from '../../core/types/domain';

let reader: (() => Transaction[]) | null = null;

export const transactionsRegistry = {
  register(fn: () => Transaction[]): void {
    reader = fn;
  },
  isReady(): boolean {
    return reader !== null;
  },
  read(): Transaction[] {
    if (!reader) {
      throw new Error('لم يتم تهيئة مخزن المعاملات بعد. تعذر التحقق من تفرد الوثيقة الداعمة.');
    }
    return reader();
  },
};
