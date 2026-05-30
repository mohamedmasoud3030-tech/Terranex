import { useState, useEffect, useCallback } from 'react';
import { obligationsStore, type ObligationInput } from './storage';
import type { Obligation } from '../../core/types/domain';

export function useObligations(projectId?: string) {
  const [obligations, setObligations] = useState<Obligation[]>(() =>
    projectId ? obligationsStore.getByProject(projectId) : obligationsStore.getAll(),
  );

  useEffect(() =>
    obligationsStore.subscribe((all) =>
      setObligations(projectId ? all.filter((o) => o.project_id === projectId) : all),
    ), [projectId],
  );

  const createObligation = useCallback((input: ObligationInput) => obligationsStore.create(input), []);
  const settleObligation = useCallback((id: string, amountEgp: number) => obligationsStore.settle(id, amountEgp), []);
  const deleteObligation = useCallback((id: string) => obligationsStore.remove(id), []);

  const open = obligations.filter((o) => o.status !== 'settled' && o.status !== 'written_off');
  const totalReceivableEgp = open.filter((o) => o.direction === 'receivable').reduce((s, o) => s + o.amount_egp - o.amount_settled_egp, 0);
  const totalPayableEgp = open.filter((o) => o.direction === 'payable').reduce((s, o) => s + o.amount_egp - o.amount_settled_egp, 0);

  return { obligations, open, totalReceivableEgp, totalPayableEgp, createObligation, settleObligation, deleteObligation };
}
