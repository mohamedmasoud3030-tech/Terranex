import type { Obligation, Transaction } from '../types/domain';
import { isFiniteNumber, isRecord } from '../lib/validation';

const LEGACY_FINANCIAL_RECORDS_KEY = 'terranex.financialRecords.v1';
const LEGACY_AUDIT_KEY = 'terranex.legacyFinancialRecords.audit.v1';
const MIGRATION_KEY = 'terranex.migrations.v1';
const TRANSACTIONS_KEY = 'terranex.transactions.v2';
const OBLIGATIONS_KEY = 'terranex.obligations.v1';
const MIGRATION_ID = 'legacy-financial-records-to-ledger-v1';

type LegacyFinancialRecord = {
  id: string;
  date: string;
  type: 'income' | 'expense' | 'receivable' | 'payable';
  title: string;
  amount: number;
  currency: 'EGP';
  project_id?: string;
  partner_id?: string;
  notes?: string;
  createdAt?: string;
  updatedAt?: string;
};

interface MigrationState {
  completed: string[];
}

function readJson<T>(key: string, fallback: T): T {
  if (typeof localStorage === 'undefined') return fallback;
  const raw = localStorage.getItem(key);
  if (!raw) return fallback;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

function writeJson(key: string, value: unknown) {
  if (typeof localStorage === 'undefined') return;
  localStorage.setItem(key, JSON.stringify(value));
}

function parseLegacyRecord(value: unknown): LegacyFinancialRecord | null {
  if (!isRecord(value)) return null;
  if (typeof value.id !== 'string') return null;
  if (typeof value.date !== 'string') return null;
  if (!['income', 'expense', 'receivable', 'payable'].includes(String(value.type))) return null;
  if (typeof value.title !== 'string') return null;
  if (!isFiniteNumber(value.amount) || value.amount <= 0) return null;
  if (value.currency !== 'EGP') return null;

  return {
    id: value.id,
    date: value.date,
    type: value.type as LegacyFinancialRecord['type'],
    title: value.title,
    amount: value.amount,
    currency: 'EGP',
    project_id: typeof value.project_id === 'string' ? value.project_id : undefined,
    partner_id: typeof value.partner_id === 'string' ? value.partner_id : undefined,
    notes: typeof value.notes === 'string' ? value.notes : undefined,
    createdAt: typeof value.createdAt === 'string' ? value.createdAt : undefined,
    updatedAt: typeof value.updatedAt === 'string' ? value.updatedAt : undefined,
  };
}

function migrateLegacyFinancialRecords() {
  if (typeof localStorage === 'undefined') return;

  const state = readJson<MigrationState>(MIGRATION_KEY, { completed: [] });
  if (state.completed.includes(MIGRATION_ID)) return;

  const rawLegacy = readJson<unknown>(LEGACY_FINANCIAL_RECORDS_KEY, []);
  const legacyRecords = Array.isArray(rawLegacy) ? rawLegacy.map(parseLegacyRecord).filter((record): record is LegacyFinancialRecord => record !== null) : [];
  const transactions = readJson<Transaction[]>(TRANSACTIONS_KEY, []);
  const obligations = readJson<Obligation[]>(OBLIGATIONS_KEY, []);
  const audit = readJson<unknown[]>(LEGACY_AUDIT_KEY, []);
  const existingTransactionIds = new Set(transactions.map((transaction) => transaction.id));
  const existingObligationIds = new Set(obligations.map((obligation) => obligation.id));
  const now = new Date().toISOString();
  const unmappable: unknown[] = [];

  for (const legacy of legacyRecords) {
    if ((legacy.type === 'income' || legacy.type === 'expense') && legacy.project_id) {
      const id = `migrated-${legacy.id}`;
      if (!existingTransactionIds.has(id)) {
        transactions.push({
          id,
          project_id: legacy.project_id,
          partner_id: legacy.partner_id,
          direction: legacy.type,
          category: 'other',
          amount: legacy.amount,
          currency: 'EGP',
          fx_rate: 1,
          amount_egp: legacy.amount,
          transaction_date: legacy.date,
          description: legacy.title,
          notes: legacy.notes,
          created_at: legacy.createdAt ?? now,
          updated_at: legacy.updatedAt ?? now,
        });
      }
      continue;
    }

    if ((legacy.type === 'receivable' || legacy.type === 'payable') && legacy.partner_id) {
      const id = `migrated-${legacy.id}`;
      if (!existingObligationIds.has(id)) {
        obligations.push({
          id,
          project_id: legacy.project_id,
          partner_id: legacy.partner_id,
          direction: legacy.type,
          amount: legacy.amount,
          currency: 'EGP',
          amount_egp: legacy.amount,
          status: 'open',
          amount_settled_egp: 0,
          notes: [legacy.title, legacy.notes].filter(Boolean).join(' — ') || undefined,
          created_at: legacy.createdAt ?? now,
          updated_at: legacy.updatedAt ?? now,
        });
      }
      continue;
    }

    unmappable.push({ ...legacy, preserved_reason_ar: 'تعذر ربط السجل بمشروع أو شريك صالح دون اختلاق بيانات.' });
  }

  if (legacyRecords.length > 0) {
    writeJson(TRANSACTIONS_KEY, transactions.sort((a, b) => b.transaction_date.localeCompare(a.transaction_date)));
    writeJson(OBLIGATIONS_KEY, obligations.sort((a, b) => b.created_at.localeCompare(a.created_at)));
  }
  if (unmappable.length > 0) writeJson(LEGACY_AUDIT_KEY, [...audit, ...unmappable]);
  localStorage.removeItem(LEGACY_FINANCIAL_RECORDS_KEY);
  writeJson(MIGRATION_KEY, { completed: [...new Set([...state.completed, MIGRATION_ID])] });
}

export function runAppStorageMigrations() {
  migrateLegacyFinancialRecords();
}
