import { isFiniteNumber } from '../../core/lib/validation';
import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import { migrateLegacySettlementBalances, resetLegacySettlementMigration, SETTLEMENTS_KEY } from './migration';
import type { Settlement, SettlementPaymentMethod } from './types';

export type { RecordSettlementInput } from './workflow';

function sortSettlements(items: Settlement[]) {
  return items.sort((a, b) => b.settlement_date.localeCompare(a.settlement_date) || b.created_at.localeCompare(a.created_at));
}

function parse(raw: unknown): Settlement[] {
  if (!Array.isArray(raw)) return [];
  return sortSettlements(raw.filter(
    (record): record is Settlement =>
      Boolean(record) && typeof record === 'object' &&
      typeof record.id === 'string' &&
      typeof record.obligation_id === 'string' &&
      typeof record.settlement_date === 'string' &&
      isFiniteNumber(record.amount_egp),
  ));
}

function makeId() {
  return `set-${crypto.randomUUID()}`;
}

const store = createLocalStorageStore<Settlement[]>(SETTLEMENTS_KEY, [], parse);

export interface SettlementInput {
  obligation_id: string;
  amount: number;
  currency: Settlement['currency'];
  fx_rate: number;
  settlement_date: string;
  payment_method: SettlementPaymentMethod;
  reference_number?: string;
  receipt_document_id?: string;
  notes?: string;
  origin?: Settlement['origin'];
}

function normalizeInput(input: SettlementInput) {
  const obligationId = input.obligation_id.trim();
  const date = input.settlement_date.trim();
  if (!obligationId) throw new Error('يجب ربط التسوية بالتزام.');
  if (!isFiniteNumber(input.amount) || input.amount <= 0) throw new Error('قيمة التسوية يجب أن تكون رقماً صالحاً أكبر من صفر.');
  if (!isFiniteNumber(input.fx_rate) || input.fx_rate <= 0) throw new Error('سعر الصرف يجب أن يكون رقماً صالحاً أكبر من صفر.');
  if (!date) throw new Error('تاريخ التسوية مطلوب.');
  if (!input.payment_method) throw new Error('طريقة الدفع مطلوبة.');
  if ((input.origin ?? 'user') === 'user' && input.payment_method === 'unknown') throw new Error('اختر طريقة دفع صالحة.');
  return {
    ...input,
    obligation_id: obligationId,
    settlement_date: date,
    reference_number: input.reference_number?.trim() || undefined,
    receipt_document_id: input.receipt_document_id?.trim() || undefined,
    notes: input.notes?.trim() || undefined,
    amount_egp: input.amount * input.fx_rate,
    origin: input.origin ?? 'user',
  };
}

function readAll() {
  migrateLegacySettlementBalances();
  return store.get();
}

export const settlementsStore = {
  getAll: readAll,
  getById: (id: string) => readAll().find((item) => item.id === id),
  getByObligation: (obligationId: string) => readAll().filter((item) => item.obligation_id === obligationId),
  getByReceiptDocument: (documentId: string) => readAll().filter((item) => item.receipt_document_id === documentId),
  getActiveTotalByObligation: (obligationId: string) => readAll()
    .filter((item) => item.obligation_id === obligationId && item.status === 'active')
    .reduce((sum, item) => sum + item.amount_egp, 0),
  create: (input: SettlementInput): Settlement => {
    migrateLegacySettlementBalances();
    const now = new Date().toISOString();
    const settlement: Settlement = { ...normalizeInput(input), id: makeId(), status: 'active', created_at: now, updated_at: now };
    store.update((all) => sortSettlements([settlement, ...all]));
    return settlement;
  },
  reverse: (id: string, reason: string): Settlement => {
    migrateLegacySettlementBalances();
    const normalizedReason = reason.trim();
    if (!normalizedReason) throw new Error('سبب عكس التسوية مطلوب.');
    let reversed: Settlement | undefined;
    store.update((all) => all.map((item) => {
      if (item.id !== id) return item;
      if (item.status === 'reversed') throw new Error('تم عكس هذه التسوية بالفعل.');
      const now = new Date().toISOString();
      reversed = { ...item, status: 'reversed', reversed_at: now, reversal_reason: normalizedReason, updated_at: now };
      return reversed;
    }));
    if (!reversed) throw new Error('تعذر العثور على التسوية المطلوبة.');
    return reversed;
  },
  subscribe: (listener: (items: Settlement[]) => void) => {
    migrateLegacySettlementBalances();
    return store.subscribe(listener);
  },
  reset: () => {
    store.reset();
    resetLegacySettlementMigration();
  },
};
