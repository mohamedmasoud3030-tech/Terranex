import type { StockAdjustment } from '../../core/types/domain';
import {
  generateRequestId,
  invokeFinanceRpc,
  P1B_ATOMIC_RPC_NAMES,
} from '../finance/financeWriteBoundary';
import { stockAdjustmentsStore, type StockAdjustmentInput } from './storage';

interface RecordStockAdjustmentAtomicResult {
  adjustment_id: string;
  quantity_before: number;
  quantity_after: number;
  value_egp_before: number;
  value_egp_after: number;
}

export interface RecordStockAdjustmentAtomicPayload {
  p_request_id: string;
  p_adjustment: {
    id: string;
    asset_id: string;
    project_id: string;
    adjustment_date: string;
    quantity_delta: number;
    value_egp_delta: number;
    reason: StockAdjustmentInput['reason'];
    notes?: string;
  };
}

export function buildStockAdjustmentAtomicPayload(
  input: StockAdjustmentInput,
  adjustmentId: string,
  requestId = generateRequestId(P1B_ATOMIC_RPC_NAMES[5], adjustmentId),
): RecordStockAdjustmentAtomicPayload {
  return {
    p_request_id: requestId,
    p_adjustment: {
      id: adjustmentId,
      asset_id: input.asset_id,
      project_id: input.project_id,
      adjustment_date: input.adjustment_date,
      quantity_delta: input.quantity_after - input.quantity_before,
      value_egp_delta: input.value_egp_after - input.value_egp_before,
      reason: input.reason,
      notes: input.notes,
    },
  };
}

/**
 * Persists the adjustment row and updates the asset balance in one PostgreSQL
 * transaction. The server recalculates authoritative before/after values while
 * holding a row lock, so stale form data cannot overwrite a newer balance.
 */
export async function recordStockAdjustmentAtomic(
  input: StockAdjustmentInput,
): Promise<StockAdjustment> {
  const adjustmentId = crypto.randomUUID();
  const result = await invokeFinanceRpc<RecordStockAdjustmentAtomicResult>(
    P1B_ATOMIC_RPC_NAMES[5],
    buildStockAdjustmentAtomicPayload(input, adjustmentId),
    { refresh: 'stock' },
  );

  const adjustment = stockAdjustmentsStore.getAll().find((item) => item.id === result.adjustment_id);
  if (!adjustment) {
    throw new Error('نجح تصحيح المخزون على الخادم لكن تعذر تحميله بعد المزامنة.');
  }
  return adjustment;
}
