import { describe, expect, it, vi } from 'vitest';
import type { ActionState } from '@/features/auth/actions';
import { withAgricultureCommandLifecycle } from '@/features/agriculture/command-lifecycle';

function commandForm(baseKey?: string): FormData {
  const form = new FormData();
  if (baseKey !== undefined) form.set('idempotencyKey', baseKey);
  return form;
}

describe('Agriculture command idempotency lifecycle', () => {
  it('reuses the effective key after failure and rotates only after confirmed success', async () => {
    const seenKeys: string[] = [];
    const action = vi.fn(async (_prev: ActionState, form: FormData): Promise<ActionState> => {
      seenKeys.push(String(form.get('idempotencyKey')));
      if (seenKeys.length === 1) return { error: 'تعذر التسجيل' };
      return {};
    });

    const first = await withAgricultureCommandLifecycle(action, {}, commandForm('ag-farm-stable'));
    expect(first).toEqual({ error: 'تعذر التسجيل', successCount: 0 });
    expect(seenKeys).toEqual(['ag-farm-stable-0']);

    const retry = await withAgricultureCommandLifecycle(action, first, commandForm('ag-farm-stable'));
    expect(retry).toEqual({ successCount: 1 });
    expect(seenKeys).toEqual(['ag-farm-stable-0', 'ag-farm-stable-0']);

    const next = await withAgricultureCommandLifecycle(action, retry, commandForm('ag-farm-stable'));
    expect(next).toEqual({ successCount: 2 });
    expect(seenKeys).toEqual(['ag-farm-stable-0', 'ag-farm-stable-0', 'ag-farm-stable-1']);
  });

  it('refuses to call the domain action when the base key is missing', async () => {
    const action = vi.fn(async (): Promise<ActionState> => ({}));
    const state = await withAgricultureCommandLifecycle(action, { successCount: 4 }, commandForm());

    expect(state).toEqual({
      error: 'تعذر تجهيز مفتاح العملية الآمن. حدّث الصفحة ثم أعد المحاولة.',
      successCount: 4,
    });
    expect(action).not.toHaveBeenCalled();
  });
});
