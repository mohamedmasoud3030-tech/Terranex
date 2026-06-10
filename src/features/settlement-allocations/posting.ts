import type { Obligation } from '../../core/types/domain';
import type { Settlement } from '../settlements/types';
import { assertSettlementAllocationLimits } from './limits';
import { settlementAllocationsStore, type SettlementAllocationInput } from './storage';

export function recordSettlementAllocation(
  input: SettlementAllocationInput,
  settlements: Settlement[],
  obligations: Obligation[],
) {
  const allocations = settlementAllocationsStore.getAll();
  const activeObligationTotal = settlementAllocationsStore.getActiveTotalByObligation(input.obligation_id, settlements);
  assertSettlementAllocationLimits(
    input.settlement_id,
    input.obligation_id,
    input.allocated_amount_egp,
    settlements,
    obligations,
    allocations,
    activeObligationTotal,
  );
  return settlementAllocationsStore.create(input);
}
