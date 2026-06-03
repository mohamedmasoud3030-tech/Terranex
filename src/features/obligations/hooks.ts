import { useCallback, useEffect, useState } from 'react';
import { obligationsStore, type ObligationInput } from './storage';
import type { Obligation } from '../../core/types/domain';

export function useObligations(projectId?: string) {
  const [obligations, setObligations] = useState<Obligation[]>(() =>
    projectId ? obligationsStore.getByProject(projectId) : obligationsStore.getAll(),
  );

  useEffect(() => obligationsStore.subscribe((all) => {
    setObligations(projectId ? all.filter((item) => item.project_id === projectId) : all);
  }), [projectId]);

  const createObligation = useCallback((input: ObligationInput) => obligationsStore.create(input), []);
  const updateObligation = useCallback((id: string, input: Partial<ObligationInput>) => obligationsStore.update(id, input), []);
  const deleteObligation = useCallback((id: string) => obligationsStore.remove(id), []);

  const open = obligations.filter((item) => item.status !== 'settled' && item.status !== 'written_off');
  const totalReceivableEgp = open.filter((item) => item.direction === 'receivable').reduce((sum, item) => sum + item.amount_egp - item.amount_settled_egp, 0);
  const totalPayableEgp = open.filter((item) => item.direction === 'payable').reduce((sum, item) => sum + item.amount_egp - item.amount_settled_egp, 0);

  return { obligations, open, totalReceivableEgp, totalPayableEgp, createObligation, updateObligation, deleteObligation };
}
