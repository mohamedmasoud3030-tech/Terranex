import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import { clampRemainingBalance, isFiniteNumber } from '../../core/lib/validation';
import type { Obligation } from '../../core/types/domain';

const KEY = 'terranex.obligations.v1';

function parse(raw: unknown): Obligation[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (r): r is Obligation =>
      r && typeof r === 'object' &&
      typeof r.id === 'string' &&
      typeof r.partner_id === 'string',
  ).sort((a, b) => b.created_at.localeCompare(a.created_at));
}

function makeId() {
  return `obl-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

const store = createLocalStorageStore<Obligation[]>(KEY, [], parse);

export type ObligationInput = Omit<Obligation, 'id' | 'created_at' | 'updated_at' | 'amount_settled_egp'>;

export const obligationsStore = {
  getAll: () => store.get(),
  getOpen: () => store.get().filter((o) => o.status !== 'settled' && o.status !== 'written_off'),
  getByProject: (projectId: string) => store.get().filter((o) => o.project_id === projectId),
  getByPartner: (partnerId: string) => store.get().filter((o) => o.partner_id === partnerId),
  create: (input: ObligationInput): Obligation => {
    const now = new Date().toISOString();
    const obl: Obligation = { ...input, id: makeId(), amount_settled_egp: 0, created_at: now, updated_at: now };
    store.update((all) => [obl, ...all]);
    return obl;
  },
  settle: (id: string, amountEgp: number): void => {
    if (!isFiniteNumber(amountEgp) || amountEgp <= 0) {
      throw new Error('قيمة التسوية يجب أن تكون رقماً صالحاً أكبر من صفر.');
    }
    store.update((all) =>
      all.map((o) => {
        if (o.id !== id) return o;
        if (o.status === 'settled') throw new Error('لا يمكن تسوية التزام مسدد بالفعل.');
        if (o.status === 'written_off') throw new Error('لا يمكن تسوية التزام مشطوب.');
        const remaining = clampRemainingBalance(o.amount_egp, o.amount_settled_egp);
        if (amountEgp > remaining) throw new Error('قيمة التسوية أكبر من الرصيد المتبقي.');
        const newSettled = o.amount_settled_egp + amountEgp;
        const safeSettled = Math.min(o.amount_egp, newSettled);
        const status: Obligation['status'] = safeSettled >= o.amount_egp ? 'settled' : 'partial';
        return { ...o, amount_settled_egp: safeSettled, status, updated_at: new Date().toISOString() };
      }),
    );
  },
  update: (id: string, input: Partial<ObligationInput>): void => {
    store.update((all) =>
      all.map((o) => o.id === id ? { ...o, ...input, updated_at: new Date().toISOString() } : o),
    );
  },
  remove: (id: string): void => {
    store.update((all) => all.filter((o) => o.id !== id));
  },
  subscribe: store.subscribe,
  reset: store.reset,
};
