import { isFiniteNumber } from '../../core/lib/validation';
import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import { migrateLegacySettlementBalances } from '../settlements/migration';
import type { Settlement } from '../settlements/types';
import {
  migrateLegacySettlementAllocations,
  resetLegacySettlementAllocationMigration,
  SETTLEMENT_ALLOCATIONS_KEY,
} from './migration';
import type { SettlementAllocation } from './types';

function parse(raw: unknown): SettlementAllocation[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (record): record is SettlementAllocation =>
      Boolean(record) && typeof record === 'object' &&
      typeof record.id === 'string' &&
      typeof record.settlement_id === 'string' &&
      typeof record.obligation_id === 'string' &&
      isFiniteNumber(record.allocated_amount_egp) &&
      record.allocated_amount_egp > 0 &&
      typeof record.created_at === 'string',
  );
}

function makeId() {
  return `alloc-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

const store = createLocalStorageStore<SettlementAllocation[]>(SETTLEMENT_ALLOCATIONS_KEY, [], parse);

export interface SettlementAllocationInput {
  settlement_id: string;
  obligation_id: string;
  allocated_amount_egp: number;
}

function normalizeInput(input: SettlementAllocationInput): SettlementAllocationInput {
  const settlementId = input.settlement_id.trim();
  const obligationId = input.obligation_id.trim();
  if (!settlementId) throw new Error('يجب ربط التوزيع بتسوية.');
  if (!obligationId) throw new Error('يجب ربط التوزيع بالتزام.');
  if (!isFiniteNumber(input.allocated_amount_egp) || input.allocated_amount_egp <= 0) {
    throw new Error('قيمة توزيع التسوية يجب أن تكون رقماً صالحاً أكبر من صفر.');
  }
  return { settlement_id: settlementId, obligation_id: obligationId, allocated_amount_egp: input.allocated_amount_egp };
}

function readAll() {
  migrateLegacySettlementBalances();
  migrateLegacySettlementAllocations();
  return store.get();
}

function getActiveTotalByObligation(obligationId: string, settlements: Settlement[]) {
  const activeSettlementIds = new Set(settlements.filter((item) => item.status === 'active').map((item) => item.id));
  return readAll()
    .filter((item) => item.obligation_id === obligationId && activeSettlementIds.has(item.settlement_id))
    .reduce((sum, item) => sum + item.allocated_amount_egp, 0);
}

export const settlementAllocationsStore = {
  getAll: readAll,
  getBySettlement: (settlementId: string) => readAll().filter((item) => item.settlement_id === settlementId),
  getByObligation: (obligationId: string) => readAll().filter((item) => item.obligation_id === obligationId),
  getActiveTotalByObligation,
  create: (input: SettlementAllocationInput): SettlementAllocation => {
    const normalized = normalizeInput(input);
    if (readAll().some((item) => item.settlement_id === normalized.settlement_id && item.obligation_id === normalized.obligation_id)) {
      throw new Error('يوجد توزيع مسجل بالفعل لنفس التسوية والالتزام.');
    }
    const allocation: SettlementAllocation = { ...normalized, id: makeId(), created_at: new Date().toISOString() };
    store.update((all) => [allocation, ...all]);
    return allocation;
  },
  removeForRollback: (id: string): void => {
    store.update((all) => all.filter((item) => item.id !== id));
  },
  reset: () => {
    store.reset();
    resetLegacySettlementAllocationMigration();
  },
};
