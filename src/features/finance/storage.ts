import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import { BASE_CURRENCY, type FinancialRecord, type FinancialRecordInput } from './types';

export const FINANCIAL_RECORDS_STORAGE_KEY = 'terranex.financialRecords.v1';

function isRecord(value: unknown): value is FinancialRecord {
  if (!value || typeof value !== 'object') return false;
  const record = value as FinancialRecord;

  return (
    typeof record.id === 'string' &&
    typeof record.date === 'string' &&
    ['income', 'expense', 'receivable', 'payable'].includes(record.type) &&
    ['real_estate', 'agriculture', 'livestock', 'general'].includes(record.sector) &&
    typeof record.title === 'string' &&
    typeof record.amount === 'number' &&
    Number.isFinite(record.amount) &&
    record.currency === BASE_CURRENCY &&
    typeof record.createdAt === 'string' &&
    typeof record.updatedAt === 'string'
  );
}

function parseRecords(value: unknown): FinancialRecord[] {
  if (!Array.isArray(value)) return [];
  return value.filter(isRecord).sort((a, b) => b.date.localeCompare(a.date));
}

function createId() {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID();
  }

  return `record-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function normalizeInput(input: FinancialRecordInput): FinancialRecordInput {
  return {
    ...input,
    title: input.title.trim(),
    counterparty: input.counterparty?.trim() || undefined,
    notes: input.notes?.trim() || undefined,
    amount: Math.round(input.amount * 100) / 100,
  };
}

export const financialRecordsStore = createLocalStorageStore<FinancialRecord[]>(
  FINANCIAL_RECORDS_STORAGE_KEY,
  [],
  parseRecords,
);

export function createFinancialRecord(input: FinancialRecordInput) {
  const now = new Date().toISOString();
  const normalized = normalizeInput(input);
  const nextRecord: FinancialRecord = {
    ...normalized,
    id: createId(),
    currency: BASE_CURRENCY,
    createdAt: now,
    updatedAt: now,
  };

  financialRecordsStore.setSnapshot([nextRecord, ...financialRecordsStore.getSnapshot()]);
  return nextRecord;
}

export function updateFinancialRecord(id: string, input: FinancialRecordInput) {
  const normalized = normalizeInput(input);
  const records = financialRecordsStore.getSnapshot();
  const nextRecords = records.map((record) =>
    record.id === id
      ? { ...record, ...normalized, currency: BASE_CURRENCY, updatedAt: new Date().toISOString() }
      : record,
  );

  financialRecordsStore.setSnapshot(nextRecords);
}

export function deleteFinancialRecord(id: string) {
  financialRecordsStore.setSnapshot(
    financialRecordsStore.getSnapshot().filter((record) => record.id !== id),
  );
}

export function resetFinancialRecords() {
  financialRecordsStore.clear();
}
