import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { ActionState } from '@/features/auth/actions';
import { createFarm } from '@/features/agriculture/actions';
import * as domain from '@/features/agriculture/domain-actions';

vi.mock('@/features/agriculture/domain-actions', () => ({ createFarm: vi.fn() }));

function commandForm(baseKey?: string): FormData {
  const form = new FormData();
  if (baseKey !== undefined) form.set('idempotencyKey', baseKey);
  return form;
}

describe('Agriculture command idempotency lifecycle', () => {
  beforeEach(() => vi.mocked(domain.createFarm).mockReset());

  it('reuses the effective key after failure and rotates only after confirmed success', async () => {
    const seenKeys: string[] = [];
    vi.mocked(domain.createFarm).mockImplementation(async (_prev, form) => {
      seenKeys.push(String(form.get('idempotencyKey')));
      if (seenKeys.length === 1) return { error: 'تعذر التسجيل' };
      return {};
    });

    const first: ActionState = await createFarm({}, commandForm('ag-farm-stable'));
    expect(first).toEqual({ error: 'تعذر التسجيل', successCount: 0 });
    expect(seenKeys).toEqual(['ag-farm-stable-0']);

    const retry: ActionState = await createFarm(first, commandForm('ag-farm-stable'));
    expect(retry).toEqual({ successCount: 1 });
    expect(seenKeys).toEqual(['ag-farm-stable-0', 'ag-farm-stable-0']);

    const next: ActionState = await createFarm(retry, commandForm('ag-farm-stable'));
    expect(next).toEqual({ successCount: 2 });
    expect(seenKeys).toEqual(['ag-farm-stable-0', 'ag-farm-stable-0', 'ag-farm-stable-1']);
  });

  it('refuses to call the domain action when the base key is missing', async () => {
    const state = await createFarm({ successCount: 4 }, commandForm());
    expect(state).toEqual({ error: 'تعذر تجهيز مفتاح العملية الآمن. حدّث الصفحة ثم أعد المحاولة.', successCount: 4 });
    expect(domain.createFarm).not.toHaveBeenCalled();
  });
});
