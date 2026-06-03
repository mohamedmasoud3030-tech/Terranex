import { isFiniteNumber } from '../../core/lib/validation';
import { safeJsonParse } from '../../core/storage/localStorageStore';
import type { Obligation } from '../../core/types/domain';
import type { Settlement } from './types';

export const SETTLEMENTS_KEY = 'terranex.settlements.v1';
const OBLIGATIONS_KEY = 'terranex.obligations.v1';
const MIGRATION_KEY = 'terranex.settlements.legacy-balance-migration.v1';

function readArray(key: string) {
  const value = safeJsonParse(localStorage.getItem(key), key);
  return value === null ? [] : Array.isArray(value) ? value : null;
}

export function migrateLegacySettlementBalances() {
  if (typeof localStorage === 'undefined' || localStorage.getItem(MIGRATION_KEY)) return;
  try {
    const obligations = readArray(OBLIGATIONS_KEY) as Obligation[] | null;
    const settlements = readArray(SETTLEMENTS_KEY) as Settlement[] | null;
    if (!obligations || !settlements) return;
    const next = [...settlements];
    for (const obligation of obligations) {
      const settled = isFiniteNumber(obligation.amount_settled_egp) ? obligation.amount_settled_egp : 0;
      const active = next.filter((item) => item.obligation_id === obligation.id && item.status === 'active').reduce((sum, item) => sum + item.amount_egp, 0);
      const amount = settled - active;
      if (amount <= 0) continue;
      const id = `set-legacy-${obligation.id}`;
      if (next.some((item) => item.id === id)) continue;
      const timestamp = obligation.updated_at || obligation.created_at || new Date().toISOString();
      next.push({ id, obligation_id: obligation.id, amount, currency: 'EGP', fx_rate: 1, amount_egp: amount, settlement_date: timestamp.slice(0, 10), payment_method: 'unknown', reference_number: `LEGACY-${obligation.id}`, notes: 'رصيد سابق تم ترحيله للمراجعة.', status: 'active', origin: 'legacy_balance_migration', created_at: timestamp, updated_at: timestamp });
    }
    if (next.length !== settlements.length) localStorage.setItem(SETTLEMENTS_KEY, JSON.stringify(next));
    localStorage.setItem(MIGRATION_KEY, new Date().toISOString());
  } catch {
    console.error('تعذر ترحيل أرصدة التسويات السابقة. تم الإبقاء على البيانات دون تعديل.');
  }
}

export function resetLegacySettlementMigration() {
  if (typeof localStorage !== 'undefined') localStorage.removeItem(MIGRATION_KEY);
}
