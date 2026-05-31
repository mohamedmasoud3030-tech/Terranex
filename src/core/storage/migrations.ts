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
  sector?: string;
  counterparty?: string;
  project_id?: string;
  partner_id?: string;
  notes?: string;
  createdAt?: string;
  updatedAt?: string;
};

interface MigrationState {
  completed: string[];
}

interface JsonReadResult {
  ok: boolean;
  exists: boolean;
  value?: unknown;
}

function readJson(key: string): JsonReadResult {
  if (typeof localStorage === 'undefined') return { ok: false, exists: false };
  try {
    const raw = localStorage.getItem(key);
    if (raw === null) return { ok: true, exists: false };
    try {
      return { ok: true, exists: true, value: JSON.parse(raw) as unknown };
    } catch {
      console.error(`تعذر تحليل البيانات المحلية للمفتاح ${key}. تم الإبقاء على البيانات دون تعديل.`);
      return { ok: false, exists: true };
    }
  } catch {
    console.error(`تعذر قراءة البيانات المحلية للمفتاح ${key}. تم تجاوز الترحيل للحفاظ على تشغيل التطبيق.`);
    return { ok: false, exists: false };
  }
}

function writeJson(key: string, value: unknown): boolean {
  if (typeof localStorage === 'undefined') return false;
  try {
    localStorage.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    console.error(`تعذر حفظ البيانات المحلية للمفتاح ${key}. تم الإبقاء على البيانات الأصلية دون حذف.`);
    return false;
  }
}

function removeKey(key: string): boolean {
  if (typeof localStorage === 'undefined') return false;
  try {
    localStorage.removeItem(key);
    return true;
  } catch {
    console.error(`تعذر حذف المفتاح المحلي ${key}. سيتم الاحتفاظ بالنسخة الأصلية.`);
    return false;
  }
}

function readArray<T>(key: string): { ok: boolean; value: T[] } {
  const result = readJson(key);
  if (!result.ok) return { ok: false, value: [] };
  if (!result.exists) return { ok: true, value: [] };
  if (!Array.isArray(result.value)) {
    console.error(`البيانات المحلية للمفتاح ${key} ليست قائمة صالحة. تم إيقاف الترحيل دون الكتابة فوقها.`);
    return { ok: false, value: [] };
  }
  return { ok: true, value: result.value as T[] };
}

function readMigrationState(): { ok: boolean; value: MigrationState } {
  const result = readJson(MIGRATION_KEY);
  if (!result.ok) return { ok: false, value: { completed: [] } };
  if (!result.exists) return { ok: true, value: { completed: [] } };
  if (!isRecord(result.value) || !Array.isArray(result.value.completed)) {
    console.error(`حالة الترحيلات المحلية غير صالحة. تم إيقاف الترحيل دون الكتابة فوقها.`);
    return { ok: false, value: { completed: [] } };
  }
  return {
    ok: true,
    value: { completed: result.value.completed.filter((item): item is string => typeof item === 'string') },
  };
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
    sector: typeof value.sector === 'string' ? value.sector : undefined,
    counterparty: typeof value.counterparty === 'string' ? value.counterparty : undefined,
    project_id: typeof value.project_id === 'string' ? value.project_id : undefined,
    partner_id: typeof value.partner_id === 'string' ? value.partner_id : undefined,
    notes: typeof value.notes === 'string' ? value.notes : undefined,
    createdAt: typeof value.createdAt === 'string' ? value.createdAt : undefined,
    updatedAt: typeof value.updatedAt === 'string' ? value.updatedAt : undefined,
  };
}

function makeAuditEntry(record: unknown, reason: string) {
  return {
    migration_id: MIGRATION_ID,
    preserved_reason_ar: reason,
    record,
  };
}

function appendUniqueAudit(existing: unknown[], additions: unknown[]) {
  const seen = new Set(existing.map((item) => JSON.stringify(item)));
  const next = [...existing];
  for (const item of additions) {
    const serialized = JSON.stringify(item);
    if (!seen.has(serialized)) {
      seen.add(serialized);
      next.push(item);
    }
  }
  return next;
}

function markCompleted(state: MigrationState) {
  return writeJson(MIGRATION_KEY, { completed: [...new Set([...state.completed, MIGRATION_ID])] });
}

function migrateLegacyFinancialRecords() {
  if (typeof localStorage === 'undefined') return;

  const stateResult = readMigrationState();
  if (!stateResult.ok) return;
  const state = stateResult.value;
  if (state.completed.includes(MIGRATION_ID)) return;

  const legacyResult = readJson(LEGACY_FINANCIAL_RECORDS_KEY);
  if (!legacyResult.ok) return;
  if (!legacyResult.exists) {
    markCompleted(state);
    return;
  }

  const transactionsResult = readArray<Transaction>(TRANSACTIONS_KEY);
  const obligationsResult = readArray<Obligation>(OBLIGATIONS_KEY);
  const auditResult = readArray<unknown>(LEGACY_AUDIT_KEY);
  if (!transactionsResult.ok || !obligationsResult.ok || !auditResult.ok) return;

  const sourceWasArray = Array.isArray(legacyResult.value);
  const rawRecords = sourceWasArray ? legacyResult.value as unknown[] : [legacyResult.value];
  const transactions = [...transactionsResult.value];
  const obligations = [...obligationsResult.value];
  const existingTransactionIds = new Set(transactions.map((transaction) => transaction.id));
  const existingObligationIds = new Set(obligations.map((obligation) => obligation.id));
  const auditAdditions: unknown[] = [];
  const now = new Date().toISOString();
  let transactionsChanged = false;
  let obligationsChanged = false;
  let hasUnmappableRecords = !sourceWasArray;

  if (!sourceWasArray) {
    auditAdditions.push(makeAuditEntry(legacyResult.value, 'صيغة مخزن السجلات المالية القديمة غير متوقعة. تم الاحتفاظ بالقيمة الأصلية دون تعديل.'));
  }

  for (const rawRecord of rawRecords) {
    const legacy = parseLegacyRecord(rawRecord);
    if (!legacy) {
      hasUnmappableRecords = true;
      auditAdditions.push(makeAuditEntry(rawRecord, 'السجل المالي القديم غير صالح للترحيل الآمن. تم الاحتفاظ به للمراجعة دون اختلاق بيانات.'));
      continue;
    }

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
        existingTransactionIds.add(id);
        transactionsChanged = true;
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
          notes: [legacy.title, legacy.counterparty, legacy.notes].filter(Boolean).join(' — ') || undefined,
          created_at: legacy.createdAt ?? now,
          updated_at: legacy.updatedAt ?? now,
        });
        existingObligationIds.add(id);
        obligationsChanged = true;
      }
      continue;
    }

    hasUnmappableRecords = true;
    auditAdditions.push(makeAuditEntry(rawRecord, 'تعذر ربط السجل بمشروع أو شريك صالح دون اختلاق بيانات. تم الاحتفاظ بالسجل القديم للمراجعة.'));
  }

  if (transactionsChanged && !writeJson(TRANSACTIONS_KEY, transactions.sort((a, b) => b.transaction_date.localeCompare(a.transaction_date)))) return;
  if (obligationsChanged && !writeJson(OBLIGATIONS_KEY, obligations.sort((a, b) => b.created_at.localeCompare(a.created_at)))) return;
  if (auditAdditions.length > 0 && !writeJson(LEGACY_AUDIT_KEY, appendUniqueAudit(auditResult.value, auditAdditions))) return;
  if (!markCompleted(state)) return;

  if (!hasUnmappableRecords) removeKey(LEGACY_FINANCIAL_RECORDS_KEY);
}

export function runAppStorageMigrations() {
  try {
    migrateLegacyFinancialRecords();
  } catch {
    console.error('تعذر إتمام ترحيل البيانات المحلية. تم تجاوز الترحيل للحفاظ على تشغيل التطبيق والبيانات الأصلية.');
  }
}
