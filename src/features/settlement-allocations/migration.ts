import { isFiniteNumber } from '../../core/lib/validation';
import { safeJsonParse } from '../../core/storage/localStorageStore';
import type { Obligation } from '../../core/types/domain';
import type { Settlement } from '../settlements/types';
import type { SettlementAllocation } from './types';

export const SETTLEMENT_ALLOCATIONS_KEY = 'terranex.settlementAllocations.v1';
export const SETTLEMENT_ALLOCATIONS_AUDIT_KEY = 'terranex.settlementAllocations.audit.v1';
const SETTLEMENTS_KEY = 'terranex.settlements.v1';
const OBLIGATIONS_KEY = 'terranex.obligations.v1';
const MIGRATION_KEY = 'terranex.settlementAllocations.legacy-settlement-migration.v1';

function readArray(key: string) {
  const value = safeJsonParse(localStorage.getItem(key), key);
  return value === null ? [] : Array.isArray(value) ? value : null;
}

function writeJson(key: string, value: unknown) {
  localStorage.setItem(key, JSON.stringify(value));
}

function makeAuditEntry(record: unknown, reason: string) {
  return { migration_id: MIGRATION_KEY, preserved_reason_ar: reason, record };
}

function appendUniqueAudit(existing: unknown[], additions: unknown[]) {
  const seen = new Set(existing.map((item) => JSON.stringify(item)));
  const next = [...existing];
  for (const item of additions) {
    const serialized = JSON.stringify(item);
    if (seen.has(serialized)) continue;
    seen.add(serialized);
    next.push(item);
  }
  return next;
}

function isBackfillableSettlement(value: unknown): value is Settlement {
  return Boolean(value) && typeof value === 'object' &&
    typeof (value as Settlement).id === 'string' &&
    typeof (value as Settlement).obligation_id === 'string' &&
    isFiniteNumber((value as Settlement).amount_egp) &&
    (value as Settlement).amount_egp > 0;
}

export function migrateLegacySettlementAllocations() {
  if (typeof localStorage === 'undefined' || localStorage.getItem(MIGRATION_KEY)) return;
  try {
    const settlements = readArray(SETTLEMENTS_KEY);
    const obligations = readArray(OBLIGATIONS_KEY) as Obligation[] | null;
    const allocations = readArray(SETTLEMENT_ALLOCATIONS_KEY) as SettlementAllocation[] | null;
    const audit = readArray(SETTLEMENT_ALLOCATIONS_AUDIT_KEY);
    if (!settlements || !obligations || !allocations || !audit) return;

    const obligationIds = new Set(obligations.filter((item) => typeof item?.id === 'string').map((item) => item.id));
    const next = [...allocations];
    const auditAdditions: unknown[] = [];

    for (const rawSettlement of settlements) {
      if (!isBackfillableSettlement(rawSettlement)) {
        auditAdditions.push(makeAuditEntry(rawSettlement, 'تعذر إنشاء توزيع آمن لسجل تسوية غير صالح. تم الاحتفاظ به للمراجعة دون اختلاق روابط.'));
        continue;
      }
      if (!obligationIds.has(rawSettlement.obligation_id)) {
        auditAdditions.push(makeAuditEntry(rawSettlement, 'تعذر إنشاء توزيع آمن لأن الالتزام المرتبط بالتسوية غير موجود. تم الاحتفاظ بالسجل للمراجعة.'));
        continue;
      }
      const id = `alloc-legacy-${rawSettlement.id}`;
      if (next.some((item) => item.id === id || (item.settlement_id === rawSettlement.id && item.obligation_id === rawSettlement.obligation_id))) continue;
      next.push({
        id,
        settlement_id: rawSettlement.id,
        obligation_id: rawSettlement.obligation_id,
        allocated_amount_egp: rawSettlement.amount_egp,
        created_at: rawSettlement.created_at || new Date().toISOString(),
      });
    }

    if (next.length !== allocations.length) writeJson(SETTLEMENT_ALLOCATIONS_KEY, next);
    if (auditAdditions.length > 0) writeJson(SETTLEMENT_ALLOCATIONS_AUDIT_KEY, appendUniqueAudit(audit, auditAdditions));
    localStorage.setItem(MIGRATION_KEY, new Date().toISOString());
  } catch {
    console.error('تعذر ترحيل توزيعات التسويات السابقة. تم الإبقاء على البيانات دون تعديل.');
  }
}

export function resetLegacySettlementAllocationMigration() {
  if (typeof localStorage !== 'undefined') localStorage.removeItem(MIGRATION_KEY);
}
