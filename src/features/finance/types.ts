export const BASE_CURRENCY = 'EGP' as const;

export type FinancialRecordType = 'income' | 'expense' | 'receivable' | 'payable';

export type FinancialRecordSector = 'real_estate' | 'agriculture' | 'livestock' | 'general';

export interface FinancialRecord {
  id: string;
  date: string;
  type: FinancialRecordType;
  sector: FinancialRecordSector;
  title: string;
  counterparty?: string;
  amount: number;
  currency: typeof BASE_CURRENCY;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

export type FinancialRecordInput = Pick<
  FinancialRecord,
  'date' | 'type' | 'sector' | 'title' | 'counterparty' | 'amount' | 'notes'
>;

export const RECORD_TYPE_LABELS_AR: Record<FinancialRecordType, string> = {
  income: 'إيراد',
  expense: 'مصروف',
  receivable: 'ذمة مدينة',
  payable: 'ذمة دائنة',
};

export const SECTOR_LABELS_AR: Record<FinancialRecordSector, string> = {
  real_estate: 'العقاري',
  agriculture: 'الزراعي',
  livestock: 'الحيواني',
  general: 'عام',
};
