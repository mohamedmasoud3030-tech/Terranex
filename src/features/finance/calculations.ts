import type { FinancialRecord, FinancialRecordSector } from './types';

export interface FinancialSummary {
  totalIncome: number;
  totalExpenses: number;
  netProfit: number;
  openReceivables: number;
  openPayables: number;
  bySector: Record<FinancialRecordSector, number>;
}

const emptySectorTotals: Record<FinancialRecordSector, number> = {
  real_estate: 0,
  agriculture: 0,
  livestock: 0,
  general: 0,
};

export function calculateFinancialSummary(records: FinancialRecord[]): FinancialSummary {
  const summary = records.reduce<FinancialSummary>(
    (acc, record) => {
      if (record.type === 'income') acc.totalIncome += record.amount;
      if (record.type === 'expense') acc.totalExpenses += record.amount;
      if (record.type === 'receivable') acc.openReceivables += record.amount;
      if (record.type === 'payable') acc.openPayables += record.amount;

      acc.bySector[record.sector] += 1;
      return acc;
    },
    {
      totalIncome: 0,
      totalExpenses: 0,
      netProfit: 0,
      openReceivables: 0,
      openPayables: 0,
      bySector: { ...emptySectorTotals },
    },
  );

  summary.netProfit = summary.totalIncome - summary.totalExpenses;
  return summary;
}
