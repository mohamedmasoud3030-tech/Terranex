import { beforeEach, describe, expect, it } from 'vitest';
import { obligationsStore } from './storage';
import type { Obligation } from '../../core/types/domain';

const KEY = 'terranex.obligations.v1';
const now = '2026-01-01T00:00:00.000Z';

function obligation(overrides: Partial<Obligation> = {}): Obligation {
  return {
    id: 'obl-1',
    project_id: 'project-1',
    partner_id: 'partner-1',
    direction: 'receivable',
    amount: 100,
    currency: 'EGP',
    amount_egp: 100,
    status: 'open',
    amount_settled_egp: 0,
    created_at: now,
    updated_at: now,
    ...overrides,
  };
}

function seed(item: Obligation) {
  localStorage.setItem(KEY, JSON.stringify([item]));
}

describe('obligationsStore.settle', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it.each([0, -1, Number.NaN, Number.POSITIVE_INFINITY])('rejects invalid settlement amount %s', (amount: number) => {
    seed(obligation());

    expect(() => obligationsStore.settle('obl-1', amount)).toThrow('قيمة التسوية يجب أن تكون رقماً صالحاً أكبر من صفر.');
    expect(obligationsStore.getAll()[0].amount_settled_egp).toBe(0);
  });

  it('rejects overpayment', () => {
    seed(obligation({ amount_settled_egp: 80, status: 'partial' }));

    expect(() => obligationsStore.settle('obl-1', 21)).toThrow('قيمة التسوية أكبر من الرصيد المتبقي.');
    expect(obligationsStore.getAll()[0].amount_settled_egp).toBe(80);
  });

  it('rejects settlement of already settled obligations', () => {
    seed(obligation({ status: 'settled', amount_settled_egp: 100 }));

    expect(() => obligationsStore.settle('obl-1', 1)).toThrow('لا يمكن تسوية التزام مسدد بالفعل.');
  });

  it('rejects settlement of written-off obligations', () => {
    seed(obligation({ status: 'written_off' }));

    expect(() => obligationsStore.settle('obl-1', 1)).toThrow('لا يمكن تسوية التزام مشطوب.');
  });

  it('allows valid partial settlement', () => {
    seed(obligation());

    obligationsStore.settle('obl-1', 40);

    expect(obligationsStore.getAll()[0]).toMatchObject({ amount_settled_egp: 40, status: 'partial' });
  });

  it('allows valid final settlement', () => {
    seed(obligation({ amount_settled_egp: 40, status: 'partial' }));

    obligationsStore.settle('obl-1', 60);

    expect(obligationsStore.getAll()[0]).toMatchObject({ amount_settled_egp: 100, status: 'settled' });
  });
});
