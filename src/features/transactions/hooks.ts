import { useState, useEffect, useCallback } from 'react';
import { createTransactionWithOptionalPayable, updateTransactionWithLinkedPayable, type DeferredExpenseTransactionInput } from './deferredExpenseWorkflow';
import { transactionsStore, type TransactionInput } from './storage';
import type { Transaction } from '../../core/types/domain';

export function useTransactions(projectId?: string) {
  const [transactions, setTransactions] = useState<Transaction[]>(() =>
    projectId ? transactionsStore.getByProject(projectId) : transactionsStore.getAll(),
  );

  useEffect(() =>
    transactionsStore.subscribe((all) =>
      setTransactions(projectId ? all.filter((t) => t.project_id === projectId) : all),
    ), [projectId],
  );

  const createTransaction = useCallback((input: DeferredExpenseTransactionInput) => createTransactionWithOptionalPayable(input), []);
  const updateTransaction = useCallback((id: string, input: Partial<TransactionInput>) => updateTransactionWithLinkedPayable(id, input), []);
  const deleteTransaction = useCallback((id: string) => transactionsStore.remove(id), []);

  const totalIncomeEgp = transactions.filter((t) => t.direction === 'income').reduce((s, t) => s + t.amount_egp, 0);
  const totalExpenseEgp = transactions.filter((t) => t.direction === 'expense').reduce((s, t) => s + t.amount_egp, 0);
  const netProfitEgp = totalIncomeEgp - totalExpenseEgp;

  return { transactions, totalIncomeEgp, totalExpenseEgp, netProfitEgp, createTransaction, updateTransaction, deleteTransaction };
}
