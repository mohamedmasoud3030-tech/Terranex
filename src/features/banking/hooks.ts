import { useCallback, useEffect, useState } from 'react';
import type {
  BankAccount,
  BankTransaction,
  CompanySettings,
} from '../../core/types/domain';
import type {
  BankAccountInput,
  BankAccountWithBalance,
  BankTransactionInput,
  BankTransferResult,
  TransferInput,
} from './types';
import {
  archiveBankAccount,
  createBankAccount,
  listAccountBalances,
  listBankAccounts,
  listBankTransactions,
  recordManualBankTransaction,
  recordTransfer,
  updateBankAccount,
} from './storage';

// --- Lightweight local-state hooks (matching the existing pattern in Terranex) ---
// For Phase 1 we keep this simple and consistent with the rest of the codebase.
// A future pass can migrate these stores to createSupabaseStore + TanStack Query.

export function useBankAccounts() {
  const [accounts, setAccounts] = useState<BankAccountWithBalance[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const [accts, balances] = await Promise.all([listBankAccounts(), listAccountBalances()]);
      const balMap = new Map<string, { balance: number; balance_base: number }>(
        (balances as Array<{ id: string; balance: number; balance_base: number }>).map(
          (b) => [b.id, b],
        ),
      );
      const withBalance: BankAccountWithBalance[] = accts.map((a) => {
        const b = balMap.get(a.id);
        return {
          ...a,
          balance: b?.balance ?? a.opening_balance,
          balance_base: b?.balance_base ?? a.opening_balance,
        };
      });
      setAccounts(withBalance);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  return { accounts, loading, error, refresh };
}

export function useBankTransactions(accountId?: string) {
  const [transactions, setTransactions] = useState<BankTransaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const rows = await listBankTransactions(accountId);
      setTransactions(rows);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [accountId]);

  useEffect(() => { void refresh(); }, [refresh]);

  return { transactions, loading, error, refresh };
}

// --- Commands ---

export async function addBankAccount(input: BankAccountInput): Promise<BankAccount> {
  return createBankAccount(input);
}

export async function editBankAccount(id: string, patch: Partial<BankAccountInput>): Promise<BankAccount> {
  return updateBankAccount(id, patch);
}

export async function archiveAccount(id: string): Promise<void> {
  return archiveBankAccount(id);
}

export async function addManualTransaction(input: BankTransactionInput): Promise<string> {
  return recordManualBankTransaction(input);
}

export async function transferBetweenAccounts(input: TransferInput): Promise<BankTransferResult> {
  return recordTransfer(input);
}

// --- Company settings (used to get base currency) ---

export function useCompanySettings() {
  const [settings, setSettings] = useState<CompanySettings | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      // Lazy require to avoid circular imports
      const { requireClient } = await import('../../core/storage/supabaseClientRegistry');
      const supabase = requireClient();
      const { data, error } = await supabase
        .from('company_settings')
        .select('*')
        .maybeSingle();
      if (error) throw error;
      setSettings((data as CompanySettings) ?? null);
    } catch {
      // settings row might not exist yet — acceptable
      setSettings(null);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  return { settings, loading, refresh };
}
