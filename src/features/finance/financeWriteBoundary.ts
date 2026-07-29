import { obligationsStore } from '../obligations/storage';
import { settlementAllocationsStore } from '../settlement-allocations/storage';
import { settlementsStore } from '../settlements/storage';
import { transactionsStore } from '../transactions/storage';

export const FINANCE_ATOMICITY_NOTICE = {
  ar: 'هذه العملية تستخدم دوال ذرية على الخادم عبر request_id لمنع التكرار. لا تُعرض كناجحة قبل اكتمال كل الكتابات.',
  en: 'This operation uses server-side atomic RPCs with request_id to prevent duplication. It is not reported as successful until every write finishes.',
};

/**
 * P1B Atomic RPC names — these are the 6 Postgres functions that replace
 * multi-request write patterns with single-transaction atomic operations.
 * Each accepts a request_id for idempotency (prevents double-click effects).
 */
export const P1B_ATOMIC_RPC_NAMES = [
  'record_transaction_atomic',
  'update_transaction_atomic',
  'delete_transaction_atomic',
  'record_settlement_atomic',
  'reverse_settlement_atomic',
  'record_stock_adjustment_atomic',
] as const;

export type P1BAtomicRpcName = typeof P1B_ATOMIC_RPC_NAMES[number];

/**
 * Generates a deterministic request_id for idempotency. The same operation
 * with the same inputs produces the same request_id, preventing duplicate
 * financial effects from network retries or double-clicks.
 */
export function generateRequestId(operation: string, ...keys: string[]): string {
  const input = [operation, ...keys].join(':');
  // Simple hash-based UUID generation for idempotency
  let hash = 0;
  for (let i = 0; i < input.length; i++) {
    const char = input.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  const hex = Math.abs(hash).toString(16).padStart(8, '0');
  return `${hex.slice(0, 8)}-${hex.slice(0, 4)}-4${hex.slice(1, 4)}-8${hex.slice(1, 4)}-${hex.padEnd(12, '0').slice(0, 12)}`;
}

const stores = [
  transactionsStore,
  obligationsStore,
  settlementsStore,
  settlementAllocationsStore,
];

async function rehydrateFinanceStores(): Promise<void> {
  await Promise.all(stores.map((store) => store.rehydrate()));
}

export async function flushFinanceWrites(): Promise<void> {
  try {
    await Promise.all(stores.map((store) => store.flush()));
  } catch (error) {
    await rehydrateFinanceStores();
    throw error;
  }
}

export async function executeFinanceWrite<T>(operation: () => T): Promise<T> {
  try {
    const result = operation();
    await flushFinanceWrites();
    return result;
  } catch (error) {
    await rehydrateFinanceStores();
    throw error;
  }
}
