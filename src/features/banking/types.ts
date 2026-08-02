import type { BankAccount, BankTransaction, Currency } from '../../core/types/domain';

export interface BankAccountInput {
  name_ar: string;
  name_en?: string;
  account_type: 'bank' | 'cash' | 'wallet';
  currency: Currency;
  opening_balance: number;
  opening_date: string;
  bank_name?: string;
  account_number?: string;
  iban?: string;
}

export interface BankTransactionInput {
  bank_account_id: string;
  direction: 'deposit' | 'withdrawal';
  amount: number;
  currency: Currency;
  fx_rate_to_base: number;
  transaction_date: string;
  memo?: string;
  partner_id?: string;
  document_id?: string;
  reference_type?: 'manual';
}

export interface TransferInput {
  from_account: string;
  to_account: string;
  amount: number;
  currency: Currency;
  fx_rate_from: number;
  fx_rate_to: number;
  transaction_date: string;
  memo?: string;
}

export interface BankAccountWithBalance extends BankAccount {
  balance: number;
  balance_base: number;
}

export interface BankTransferResult {
  withdrawal_id: string;
  deposit_id: string;
}

export interface BankingState {
  accounts: BankAccountWithBalance[];
  transactions: BankTransaction[];
  isLoaded: boolean;
  error?: string;
}
