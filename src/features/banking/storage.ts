/**
 * Storage layer for bank accounts + bank transactions.
 * Uses createSupabaseStore (existing pattern) plus direct RPC calls for
 * atomic operations (transfers, manual transactions, opening balance).
 */
import { requireClient } from '../../core/storage/supabaseClientRegistry';
import type {
  BankAccount,
  BankTransaction,
  Currency,
} from '../../core/types/domain';
import type {
  BankAccountInput,
  BankTransactionInput,
  BankTransferResult,
  TransferInput,
} from './types';

const TABLE_ACCOUNTS = 'bank_accounts';
const TABLE_TX = 'bank_transactions';
const VIEW_BALANCES = 'bank_account_balances';

function randomSuffix(): string {
  // Web Crypto (CSPRNG) is used exclusively for the request-id suffix to
  // guarantee collision-safe idempotency keys without Math.random fallback.
  const buf = new Uint8Array(8);
  crypto.getRandomValues(buf);
  return Array.from(buf, b => b.toString(16).padStart(2, '0')).join('');
}

export function generateRequestId(prefix: string): string {
  return `${prefix}_${Date.now()}_${randomSuffix()}`;
}

// ---- Bank accounts ----

export async function listBankAccounts(): Promise<BankAccount[]> {
  const supabase = requireClient();
  const { data, error } = await supabase
    .from(TABLE_ACCOUNTS)
    .select('*')
    .order('created_at', { ascending: true });
  if (error) throw new Error(`تعذر تحميل الحسابات البنكية: ${error.message}`);
  return (data ?? []) as BankAccount[];
}

export async function listAccountBalances() {
  const supabase = requireClient();
  const { data, error } = await supabase
    .from(VIEW_BALANCES)
    .select('*');
  if (error) throw new Error(`تعذر تحميل أرصدة الحسابات: ${error.message}`);
  return data ?? [];
}

export async function createBankAccount(input: BankAccountInput): Promise<BankAccount> {
  const supabase = requireClient();
  const { data, error } = await supabase
    .from(TABLE_ACCOUNTS)
    .insert({ ...input, is_archived: false })
    .select()
    .single();
  if (error) throw new Error(`تعذر إضافة الحساب: ${error.message}`);
  return data as BankAccount;
}

export async function updateBankAccount(id: string, patch: Partial<BankAccountInput>): Promise<BankAccount> {
  const supabase = requireClient();
  const { data, error } = await supabase
    .from(TABLE_ACCOUNTS)
    .update(patch)
    .eq('id', id)
    .select()
    .single();
  if (error) throw new Error(`تعذر تحديث الحساب: ${error.message}`);
  return data as BankAccount;
}

export async function archiveBankAccount(id: string): Promise<void> {
  await updateBankAccount(id, {} as Partial<BankAccountInput>);
  const supabase = requireClient();
  const { error } = await supabase
    .from(TABLE_ACCOUNTS)
    .update({ is_archived: true })
    .eq('id', id);
  if (error) throw new Error(`تعذر أرشفة الحساب: ${error.message}`);
}

// ---- Bank transactions ----

export async function listBankTransactions(accountId?: string): Promise<BankTransaction[]> {
  const supabase = requireClient();
  let q = supabase.from(TABLE_TX).select('*').order('transaction_date', { ascending: false });
  if (accountId) q = q.eq('bank_account_id', accountId);
  const { data, error } = await q;
  if (error) throw new Error(`تعذر تحميل حركات البنك: ${error.message}`);
  return (data ?? []) as BankTransaction[];
}

/** Record a manual deposit/withdrawal — calls the atomic RPC. */
export async function recordManualBankTransaction(input: BankTransactionInput): Promise<string> {
  const supabase = requireClient();
  const request_id = generateRequestId('btx');
  const { data, error } = await supabase.rpc('record_bank_transaction', {
    p_bank_account: input.bank_account_id,
    p_direction: input.direction,
    p_amount: input.amount,
    p_currency: input.currency,
    p_fx_rate: input.fx_rate_to_base,
    p_date: input.transaction_date,
    p_memo: input.memo ?? null,
    p_partner_id: input.partner_id ?? null,
    p_document_id: input.document_id ?? null,
    p_request_id: request_id,
  });
  if (error) throw new Error(`تعذر تسجيل الحركة: ${error.message}`);
  return data as string;
}

/**
 * Link a financial transaction or settlement to a bank_transaction row
 * (idempotent — safe to call on retries).
 * Returns the bank_transaction id or null if no bank account was selected.
 */
export interface LinkMovementInput {
  reference_type: 'transaction' | 'settlement' | 'distribution_payment';
  reference_id: string;
  bank_account_id?: string | null;
  direction: 'deposit' | 'withdrawal';
  amount: number;
  currency: Currency;
  fx_rate_to_base: number;
  transaction_date: string;
  memo?: string | null;
  partner_id?: string | null;
  document_id?: string | null;
}

export async function linkFinancialMovement(
  input: LinkMovementInput,
  requestId?: string,
): Promise<string | null> {
  if (!input.bank_account_id) return null;
  const supabase = requireClient();
  const { data, error } = await supabase.rpc('link_financial_movement', {
    p_request_id: requestId ?? generateRequestId(`lnk_${input.reference_type}`),
    p_reference_type: input.reference_type,
    p_reference_id: input.reference_id,
    p_bank_account: input.bank_account_id,
    p_direction: input.direction,
    p_amount: input.amount,
    p_currency: input.currency,
    p_fx_rate: input.fx_rate_to_base,
    p_date: input.transaction_date,
    p_memo: input.memo ?? null,
    p_partner_id: input.partner_id ?? null,
    p_document_id: input.document_id ?? null,
  });
  if (error) throw new Error(`تعذر ربط الحركة بالحساب البنكي: ${error.message}`);
  return (data as string | null) ?? null;
}

/** Record an account-to-account transfer atomically. */
export async function recordTransfer(input: TransferInput): Promise<BankTransferResult> {
  const supabase = requireClient();
  const request_id = generateRequestId('btf');
  const { data, error } = await supabase.rpc('record_bank_transfer', {
    p_from_account: input.from_account,
    p_to_account: input.to_account,
    p_amount: input.amount,
    p_currency: input.currency,
    p_fx_rate_from: input.fx_rate_from,
    p_fx_rate_to: input.fx_rate_to,
    p_date: input.transaction_date,
    p_memo: input.memo ?? null,
    p_request_id: request_id,
  });
  if (error) throw new Error(`تعذر تسجيل التحويل: ${error.message}`);
  // RPC returns a table (withdrawal_id, deposit_id)
  const row = Array.isArray(data) ? data[0] : data;
  return {
    withdrawal_id: (row as { withdrawal_id: string }).withdrawal_id,
    deposit_id: (row as { deposit_id: string }).deposit_id,
  };
}

/** Default fx rate helper: 1 for base currency; lookup from exchange rates or return 1. */
export function defaultFxFor(currency: Currency, baseCurrency: Currency): number {
  if (currency === baseCurrency) return 1;
  // caller should supply the actual rate from the exchange-rate panel
  return 1;
}
