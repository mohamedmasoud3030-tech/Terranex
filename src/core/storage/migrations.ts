import { readJsonValue, removeJsonValue, writeJsonValue } from './localStorageStore';
import { LocalStorageError } from './storageErrors';

export const LOCAL_SCHEMA_VERSION = 2;
const SCHEMA_KEY = 'terranex.localSchema.version';
const MIGRATION_AUDIT_KEY = 'terranex.migrationAudit.v1';
const LEGACY_FINANCIAL_KEY = 'terranex.' + 'financialRecords.v1';
const LEGACY_FINANCIAL_BACKUP_KEY = 'terranex.legacyFinancialRecords.backup.v1';

const ARRAY_KEYS = [
  'terranex.projects.v1',
  'terranex.transactions.v2',
  'terranex.assets.v1',
  'terranex.obligations.v1',
  'terranex.documents.v1',
  'terranex.partners.v1',
  'terranex.projectPartners.v1',
  'terranex.operationalEvents.v1',
  'terranex.stockAdjustments.v1',
] as const;

type AuditEntry = {
  id: string;
  at: string;
  step: string;
  message_ar: string;
  preserved_count?: number;
  migrated_count?: number;
};

type LegacyFinancialRecord = {
  id?: string;
  project_id?: string;
  date?: string;
  type?: string;
  title?: string;
  counterparty?: string;
  amount?: number;
  currency?: string;
  notes?: string;
  createdAt?: string;
  updatedAt?: string;
};

function isObject(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object';
}

function getArrayKey(key: string) {
  const value = readJsonValue(key);
  return Array.isArray(value) ? value : [];
}

function appendAudit(entry: Omit<AuditEntry, 'id' | 'at'>) {
  const current = getArrayKey(MIGRATION_AUDIT_KEY) as AuditEntry[];
  writeJsonValue(MIGRATION_AUDIT_KEY, [
    { ...entry, id: `mig-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, at: new Date().toISOString() },
    ...current,
  ]);
}

function normalizeArrayKeys() {
  for (const key of ARRAY_KEYS) {
    const value = readJsonValue(key);
    if (value === null) continue;
    if (Array.isArray(value)) continue;
    writeJsonValue(key, []);
    appendAudit({
      step: 'normalize-array-key',
      message_ar: `تم تجاهل قيمة غير قابلة للاستخدام في ${key} مع الحفاظ على استقرار التطبيق.`,
      preserved_count: 0,
    });
  }
}

function mapLegacyRecord(record: LegacyFinancialRecord, index: number) {
  const amount = record.amount;
  if (!record.date || !record.type || !record.title || typeof amount !== 'number' || !Number.isFinite(amount) || amount <= 0 || record.currency !== 'EGP') {
    return null;
  }

  const now = new Date().toISOString();
  const id = record.id ?? `legacy-${index}`;
  const created = record.createdAt ?? now;
  const updated = record.updatedAt ?? created;

  if (record.type === 'income' || record.type === 'expense') {
    if (!record.project_id) {
      return {
        kind: 'unmapped' as const,
        value: record,
        reason_ar: 'لا يمكن ترحيل الدخل أو المصروف القديم بأمان بدون معرف مشروع مرتبط.',
      };
    }

    return {
      kind: 'transaction' as const,
      value: {
        id: `legacy-trx-${id}`,
        project_id: record.project_id,
        direction: record.type,
        category: 'other',
        amount,
        currency: 'EGP',
        fx_rate: 1,
        amount_egp: amount,
        transaction_date: record.date,
        description: record.title,
        notes: record.notes,
        created_at: created,
        updated_at: updated,
      },
    };
  }

  if (record.type === 'receivable' || record.type === 'payable') {
    return {
      kind: 'unmapped' as const,
      value: record,
      reason_ar: 'لا يمكن ترحيل الذمة القديمة بأمان بدون معرف طرف مرتبط.',
    };
  }

  return null;
}

function migrateLegacyFinancialRecords() {
  const raw = readJsonValue(LEGACY_FINANCIAL_KEY);
  if (!Array.isArray(raw)) return;

  const existingTransactions = getArrayKey('terranex.transactions.v2');
  const existingIds = new Set(existingTransactions.filter(isObject).map((item) => String(item.id)));
  const migrated: unknown[] = [];
  const preserved: unknown[] = [];

  raw.forEach((item, index) => {
    if (!isObject(item)) {
      preserved.push({ item, reason_ar: 'السجل القديم ليس كائناً قابلاً للقراءة.' });
      return;
    }
    const mapped = mapLegacyRecord(item, index);
    if (!mapped) {
      preserved.push({ item, reason_ar: 'السجل القديم لا يحتوي على بيانات مالية قابلة للترحيل بأمان.' });
      return;
    }
    if (mapped.kind === 'unmapped') {
      preserved.push({ item: mapped.value, reason_ar: mapped.reason_ar });
      return;
    }
    if (!existingIds.has(mapped.value.id)) {
      migrated.push(mapped.value);
      existingIds.add(mapped.value.id);
    }
  });

  if (migrated.length > 0) writeJsonValue('terranex.transactions.v2', [...migrated, ...existingTransactions]);
  if (preserved.length > 0) writeJsonValue(LEGACY_FINANCIAL_BACKUP_KEY, preserved);
  removeJsonValue(LEGACY_FINANCIAL_KEY);
  appendAudit({
    step: 'legacy-financial-records',
    message_ar: 'تم ترحيل سجلات الدخل والمصروف القديمة القابلة للترحيل وحفظ غير القابل للترحيل كنسخة احتياطية.',
    migrated_count: migrated.length,
    preserved_count: preserved.length,
  });
}

export function runLocalStorageMigrations() {
  if (typeof window === 'undefined') return;
  try {
    const current = Number(readJsonValue(SCHEMA_KEY) ?? 0);
    normalizeArrayKeys();
    if (current < 2) migrateLegacyFinancialRecords();
    writeJsonValue(SCHEMA_KEY, LOCAL_SCHEMA_VERSION);
  } catch (error) {
    throw new LocalStorageError('migration', SCHEMA_KEY, error);
  }
}
