import { requireClient } from '../../core/storage/supabaseClientRegistry';
import { assetsStore } from '../assets/storage';
import { stockAdjustmentsStore } from '../events/storage';
import { obligationsStore } from '../obligations/storage';
import { settlementAllocationsStore } from '../settlement-allocations/storage';
import { settlementsStore } from '../settlements/storage';
import { transactionsStore } from '../transactions/storage';

export const FINANCE_ATOMICITY_NOTICE = {
  ar: 'هذه العملية تُنفذ كمعاملة ذرية واحدة على الخادم، مع request_id لمنع التكرار وإعادة مزامنة البيانات بعد النجاح.',
  en: 'This operation runs as one server-side atomic transaction with request-id idempotency and refreshes data after success.',
};

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
 * Creates one durable idempotency key per user action. The caller keeps the
 * returned payload/request id when retrying the same action; a new action gets
 * a cryptographically strong UUID instead of a collision-prone content hash.
 */
export function generateRequestId(_operation?: string, ..._keys: string[]): string {
  return crypto.randomUUID();
}

const financeStores = [
  transactionsStore,
  obligationsStore,
  settlementsStore,
  settlementAllocationsStore,
];

const stockStores = [assetsStore, stockAdjustmentsStore];

async function rehydrate(stores: Array<{ rehydrate(): Promise<void> }>): Promise<void> {
  await Promise.all(stores.map((store) => store.rehydrate()));
}

export async function rehydrateFinanceStores(): Promise<void> {
  await rehydrate(financeStores);
}

export async function rehydrateStockStores(): Promise<void> {
  await rehydrate(stockStores);
}

function toRpcError(error: unknown, rpc: string): Error {
  if (error instanceof Error) return error;
  if (error && typeof error === 'object' && 'message' in error) {
    return new Error(String((error as { message: unknown }).message));
  }
  return new Error(`فشل تنفيذ العملية الذرية ${rpc}.`);
}

function unwrapRpcResult<T>(data: unknown): T {
  // PostgREST may expose a scalar JSON return directly. Some injected clients
  // and older generated wrappers expose the same scalar as a one-row array.
  if (Array.isArray(data) && data.length === 1) return data[0] as T;
  return data as T;
}

export interface InvokeFinanceRpcOptions {
  refresh?: 'finance' | 'stock' | 'none';
}

/**
 * The only production entry point for P1B financial writes.
 *
 * It calls `SupabaseClient.rpc()` directly, fails closed on any server error,
 * and rehydrates the affected stores so the optimistic local multi-write path
 * is never used to claim success.
 */
export async function invokeFinanceRpc<T>(
  rpc: P1BAtomicRpcName,
  params: Record<string, unknown>,
  options: InvokeFinanceRpcOptions = {},
): Promise<T> {
  const refresh = options.refresh ?? 'finance';
  const client = requireClient();
  const { data, error } = await client.rpc(rpc, params);

  if (error) {
    if (refresh === 'finance') await rehydrateFinanceStores();
    if (refresh === 'stock') await rehydrateStockStores();
    throw toRpcError(error, rpc);
  }

  if (refresh === 'finance') await rehydrateFinanceStores();
  if (refresh === 'stock') await rehydrateStockStores();
  return unwrapRpcResult<T>(data);
}

/**
 * Kept for non-P1B single-table writes. P1B transaction/settlement flows pass
 * an async RPC operation here; no local store flush is performed afterward.
 */
export async function executeFinanceWrite<T>(operation: () => T | Promise<T>): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    await rehydrateFinanceStores();
    throw error;
  }
}
