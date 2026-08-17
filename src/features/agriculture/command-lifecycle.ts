import type { ActionState } from '@/features/auth/actions';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';

export type AgricultureAction = (prev: ActionState, form: FormData) => Promise<ActionState>;

/**
 * Convert one mounted Agriculture form base key into the logical-command key.
 * A failed or response-lost attempt keeps the same successCount and therefore
 * the same effective key. Only a server-confirmed success advances the count.
 */
export async function withAgricultureCommandLifecycle(
  action: AgricultureAction,
  prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const baseKey = form.get('idempotencyKey');
  if (typeof baseKey !== 'string' || baseKey.length === 0) {
    return commandFailureState(prev, 'تعذر تجهيز مفتاح العملية الآمن. حدّث الصفحة ثم أعد المحاولة.');
  }

  form.set('idempotencyKey', `${baseKey}-${prev.successCount ?? 0}`);
  const result = await action(prev, form);
  if (result.error) return commandFailureState(prev, result.error);
  return commandSuccessState(prev);
}
