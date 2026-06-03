import { isFiniteNumber } from '../../core/lib/validation';
import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import { settlementsStore } from '../settlements/storage';
import type { Obligation } from '../../core/types/domain';

const KEY = 'terranex.obligations.v1';

function parse(raw: unknown): Obligation[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (record): record is Obligation =>
      Boolean(record) && typeof record === 'object' &&
      typeof record.id === 'string' &&
      typeof record.partner_id === 'string',
  ).sort((a, b) => b.created_at.localeCompare(a.created_at));
}

function makeId() {
  return `obl-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

function deriveStatus(obligation: Obligation, settledEgp: number): Obligation['status'] {
  if (obligation.status === 'written_off' || obligation.status === 'disputed') return obligation.status;
  if (settledEgp >= obligation.amount_egp) return 'settled';
  if (settledEgp > 0) return 'partial';
  return 'open';
}

const store = createLocalStorageStore<Obligation[]>(KEY, [], parse);

export type ObligationInput = Omit<Obligation, 'id' | 'created_at' | 'updated_at' | 'amount_settled_egp'>;

export const obligationsStore = {
  getAll: () => store.get(),
  getById: (id: string) => store.get().find((item) => item.id === id),
  getOpen: () => store.get().filter((item) => item.status !== 'settled' && item.status !== 'written_off'),
  getByProject: (projectId: string) => store.get().filter((item) => item.project_id === projectId),
  getByPartner: (partnerId: string) => store.get().filter((item) => item.partner_id === partnerId),
  create: (input: ObligationInput): Obligation => {
    const now = new Date().toISOString();
    const obligation: Obligation = { ...input, id: makeId(), amount_settled_egp: 0, created_at: now, updated_at: now };
    store.update((all) => [obligation, ...all]);
    return obligation;
  },
  syncSettlementTotal: (id: string, amountSettledEgp: number): void => {
    if (!isFiniteNumber(amountSettledEgp) || amountSettledEgp < 0) throw new Error('إجمالي التسويات غير صالح.');
    store.update((all) => all.map((obligation) => {
      if (obligation.id !== id) return obligation;
      if (amountSettledEgp > obligation.amount_egp) throw new Error('إجمالي التسويات أكبر من قيمة الالتزام.');
      return {
        ...obligation,
        amount_settled_egp: amountSettledEgp,
        status: deriveStatus(obligation, amountSettledEgp),
        updated_at: new Date().toISOString(),
      };
    }));
  },
  update: (id: string, input: Partial<ObligationInput>): void => {
    store.update((all) => all.map((obligation) => {
      if (obligation.id !== id) return obligation;
      const next = { ...obligation, ...input };
      const activeSettlementTotal = settlementsStore.getActiveTotalByObligation(id);
      if (next.amount_egp < activeSettlementTotal) throw new Error('لا يمكن خفض قيمة الالتزام عن إجمالي التسويات النشطة.');
      return {
        ...next,
        amount_settled_egp: activeSettlementTotal,
        status: deriveStatus(next, activeSettlementTotal),
        updated_at: new Date().toISOString(),
      };
    }));
  },
  remove: (id: string): void => {
    if (settlementsStore.getByObligation(id).length > 0) throw new Error('لا يمكن حذف التزام له سجل تسويات. اعكس التسويات أو احتفظ بالسجل للمراجعة.');
    store.update((all) => all.filter((item) => item.id !== id));
  },
  subscribe: store.subscribe,
  reset: store.reset,
};
