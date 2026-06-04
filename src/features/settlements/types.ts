import type { Currency } from '../../core/types/domain';

export type SettlementPaymentMethod = 'cash' | 'bank_transfer' | 'cheque' | 'card' | 'other' | 'unknown';

export type SettlementStatus = 'active' | 'reversed';

export type SettlementOrigin = 'user' | 'legacy_balance_migration';

/** A posted cash movement against one receivable or payable obligation. */
export interface Settlement {
  id: string;
  obligation_id: string;
  amount: number;
  currency: Currency;
  fx_rate: number;
  amount_egp: number;
  settlement_date: string;
  payment_method: SettlementPaymentMethod;
  reference_number?: string;
  receipt_document_id?: string;
  notes?: string;
  status: SettlementStatus;
  origin: SettlementOrigin;
  reversed_at?: string;
  reversal_reason?: string;
  created_at: string;
  updated_at: string;
}
