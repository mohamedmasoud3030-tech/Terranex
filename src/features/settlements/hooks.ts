import { useCallback, useEffect, useState } from 'react';
import { settlementsStore } from './storage';
import { recordSettlement, reverseSettlement, type RecordSettlementInput } from './workflow';
import type { Settlement } from './types';

export function useSettlements(obligationId: string) {
  const [settlements, setSettlements] = useState<Settlement[]>(() => settlementsStore.getByObligation(obligationId));

  useEffect(() => settlementsStore.subscribe((all) => {
    setSettlements(all.filter((item) => item.obligation_id === obligationId));
  }), [obligationId]);

  const createSettlement = useCallback((input: RecordSettlementInput) => recordSettlement(obligationId, input), [obligationId]);
  const reverse = useCallback((settlementId: string, reason: string) => reverseSettlement(settlementId, reason), []);
  const activeTotalEgp = settlements.filter((item) => item.status === 'active').reduce((sum, item) => sum + item.amount_egp, 0);

  return { settlements, activeTotalEgp, createSettlement, reverseSettlement: reverse };
}
