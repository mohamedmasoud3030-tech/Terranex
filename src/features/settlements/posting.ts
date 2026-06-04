import { documentsStore } from '../documents/storage';
import { obligationsStore } from '../obligations/storage';
import { settlementsStore, validateSettlementInput, type SettlementInput } from './storage';
import type { Document, Obligation } from '../../core/types/domain';
import type { Settlement } from './types';

export type RecordSettlementInput = Omit<SettlementInput, 'obligation_id' | 'origin'>;

function requireObligation(id: string) {
  const obligation = obligationsStore.getById(id);
  if (!obligation) throw new Error('تعذر العثور على الالتزام المرتبط بالتسوية.');
  return obligation;
}

function validateReceipt(obligation: Obligation, documentId?: string) {
  if (!documentId) return;
  const document = documentsStore.getAll().find((item) => item.id === documentId);
  if (!document) throw new Error('تعذر العثور على إيصال التسوية.');
  if (document.type !== 'receipt') throw new Error('المستند المرفق بالتسوية يجب أن يكون إيصالاً.');
  if (obligation.project_id && document.project_id !== obligation.project_id) throw new Error('إيصال التسوية لا ينتمي إلى مشروع الالتزام.');
  if (document.partner_id && document.partner_id !== obligation.partner_id) throw new Error('إيصال التسوية لا ينتمي إلى طرف الالتزام.');
}

function requireSettleable(obligation: Obligation) {
  if (obligation.status === 'written_off') throw new Error('لا يمكن تسوية التزام مشطوب.');
  if (obligation.status === 'disputed') throw new Error('لا يمكن تسوية التزام متنازع عليه قبل حل النزاع.');
}

function synchronize(obligationId: string) {
  const activeTotal = settlementsStore.getActiveTotalByObligation(obligationId);
  obligationsStore.syncSettlementTotal(obligationId, activeTotal);
  return activeTotal;
}

export function recordSettlement(obligationId: string, input: RecordSettlementInput): Settlement {
  const obligation = requireObligation(obligationId);
  requireSettleable(obligation);
  validateReceipt(obligation, input.receipt_document_id);
  const normalized = validateSettlementInput({ ...input, obligation_id: obligationId });
  const activeTotal = settlementsStore.getActiveTotalByObligation(obligationId);
  const remaining = Math.max(0, obligation.amount_egp - activeTotal);
  if (normalized.amount_egp > remaining) throw new Error('قيمة التسوية أكبر من الرصيد المتبقي.');
  const settlement = settlementsStore.create(normalized);
  try {
    obligationsStore.syncSettlementTotal(obligationId, activeTotal + settlement.amount_egp);
  } catch (error) {
    settlementsStore.removeForRollback(settlement.id);
    throw error;
  }
  return settlement;
}

export function reverseSettlement(settlementId: string, reason: string): Settlement {
  const existing = settlementsStore.getById(settlementId);
  if (!existing) throw new Error('تعذر العثور على التسوية المطلوبة.');
  const settlement = settlementsStore.reverse(settlementId, reason);
  try {
    synchronize(existing.obligation_id);
  } catch (error) {
    settlementsStore.restoreForRollback(existing);
    throw error;
  }
  return settlement;
}

export function getSettlementReceipt(settlement: Settlement): Document | undefined {
  if (!settlement.receipt_document_id) return undefined;
  return documentsStore.getAll().find((item) => item.id === settlement.receipt_document_id);
}
