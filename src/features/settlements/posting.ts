import { roundEgp, toEgp } from '../../core/lib/format';
import { newId } from '../../core/lib/id';
import { isFiniteNumber } from '../../core/lib/validation';
import type { Document, Obligation } from '../../core/types/domain';
import { linkFinancialMovement } from '../banking/storage';
import { documentsStore } from '../documents/storage';
import {
  generateRequestId,
  invokeFinanceRpc,
  P1B_ATOMIC_RPC_NAMES,
} from '../finance/financeWriteBoundary';
import { obligationsStore } from '../obligations/storage';
import { recordSettlementAllocation } from '../settlement-allocations/posting';
import { settlementAllocationsStore } from '../settlement-allocations/storage';
import { settlementsStore, validateSettlementInput, type SettlementInput } from './storage';
import type { Settlement } from './types';

export interface RecordSettlementAtomicPayload {
  p_request_id: string;
  p_settlement: Record<string, unknown>;
  p_allocations: Array<Record<string, unknown>>;
}

export interface ReverseSettlementAtomicPayload {
  p_request_id: string;
  p_settlement_id: string;
  p_reason: string;
}

export interface RecordSettlementAtomicResult {
  settlement_id: string;
  allocation_ids: string[];
  obligation_ids: string[];
}

export interface ReverseSettlementAtomicResult {
  settlement_id: string;
  reversed_obligation_ids: string[];
  reason: string;
  reversed_at: string;
}

export function buildRecordSettlementAtomicPayload(
  settlementId: string,
  input: RecordSettlementWithAllocationsInput,
  allocationIds: string[],
  requestId = generateRequestId(P1B_ATOMIC_RPC_NAMES[3], settlementId),
): RecordSettlementAtomicPayload {
  const amountEgp = toEgp(input.amount, input.fx_rate);
  return {
    p_request_id: requestId,
    p_settlement: {
      id: settlementId,
      obligation_id: input.allocations[0]?.obligation_id,
      bank_account_id: input.bank_account_id ?? null,
      amount: input.amount,
      currency: input.currency,
      fx_rate: input.fx_rate,
      amount_egp: amountEgp,
      payment_method: input.payment_method,
      reference_number: input.reference_number,
      receipt_document_id: input.receipt_document_id,
      settlement_date: input.settlement_date,
      notes: input.notes,
    },
    p_allocations: input.allocations.map((plan, index) => ({
      id: allocationIds[index],
      obligation_id: plan.obligation_id,
      allocated_amount_egp: plan.allocated_amount_egp,
    })),
  };
}

export function buildReverseSettlementAtomicPayload(
  settlementId: string,
  reason: string,
  requestId = generateRequestId(P1B_ATOMIC_RPC_NAMES[4], settlementId, reason),
): ReverseSettlementAtomicPayload {
  return {
    p_request_id: requestId,
    p_settlement_id: settlementId,
    p_reason: reason,
  };
}

const MONEY_EPSILON = 0.000001;

export type RecordSettlementInput = Omit<SettlementInput, 'obligation_id' | 'origin'>;

export interface SettlementAllocationPlan {
  obligation_id: string;
  allocated_amount_egp: number;
}

export interface RecordSettlementWithAllocationsInput extends RecordSettlementInput {
  allocations: SettlementAllocationPlan[];
}

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

function getActiveTotal(obligationId: string) {
  return settlementAllocationsStore.getActiveTotalByObligation(obligationId, settlementsStore.getAll());
}

function normalizeAllocationPlans(plans: SettlementAllocationPlan[]): SettlementAllocationPlan[] {
  if (!Array.isArray(plans) || plans.length === 0) throw new Error('يجب تحديد توزيع واحد على الأقل للتسوية.');

  const seen = new Set<string>();
  return plans.map((plan) => {
    const obligationId = plan.obligation_id.trim();
    if (!obligationId) throw new Error('يجب ربط كل توزيع بالتزام.');
    if (!isFiniteNumber(plan.allocated_amount_egp) || plan.allocated_amount_egp <= 0) {
      throw new Error('قيمة توزيع التسوية يجب أن تكون رقماً صالحاً أكبر من صفر.');
    }
    if (seen.has(obligationId)) throw new Error('لا يمكن تكرار الالتزام داخل توزيع التسوية نفسه.');
    seen.add(obligationId);
    return { obligation_id: obligationId, allocated_amount_egp: roundEgp(plan.allocated_amount_egp) };
  });
}

function assertCompatibleObligations(obligations: Obligation[]) {
  const first = obligations[0];
  for (const obligation of obligations.slice(1)) {
    if (obligation.partner_id !== first.partner_id) throw new Error('لا يمكن توزيع تسوية واحدة على التزامات تخص أطرافاً مختلفة.');
    if (obligation.direction !== first.direction) throw new Error('لا يمكن خلط التزامات القبض والدفع في تسوية واحدة.');
    if (obligation.project_id !== first.project_id) throw new Error('لا يمكن توزيع تسوية واحدة على التزامات من مشاريع مختلفة.');
  }
}

function assertAllocationCapacity(plans: SettlementAllocationPlan[], obligations: Obligation[]) {
  for (const plan of plans) {
    const obligation = obligations.find((item) => item.id === plan.obligation_id);
    if (!obligation) throw new Error('تعذر العثور على الالتزام المرتبط بالتوزيع.');
    const remaining = Math.max(0, obligation.amount_egp - getActiveTotal(obligation.id));
    if (plan.allocated_amount_egp - remaining > MONEY_EPSILON) {
      throw new Error('قيمة التوزيع أكبر من الرصيد المتبقي للالتزام.');
    }
  }
}

function prepareSettlement(input: RecordSettlementWithAllocationsInput) {
  const plans = normalizeAllocationPlans(input.allocations);
  const { allocations: _allocations, ...settlementInput } = input;
  const normalizedSettlement = validateSettlementInput({ ...settlementInput, obligation_id: plans[0].obligation_id });
  const allocationTotal = plans.reduce((sum, plan) => sum + plan.allocated_amount_egp, 0);
  if (Math.abs(allocationTotal - normalizedSettlement.amount_egp) > MONEY_EPSILON) {
    throw new Error('يجب أن يساوي إجمالي التوزيعات قيمة التسوية بالكامل.');
  }

  const obligations = plans.map((plan) => requireObligation(plan.obligation_id));
  for (const obligation of obligations) {
    requireSettleable(obligation);
    validateReceipt(obligation, normalizedSettlement.receipt_document_id);
  }
  assertCompatibleObligations(obligations);
  assertAllocationCapacity(plans, obligations);

  return { plans, normalizedSettlement, obligations };
}


/** Posts settlement, allocations and obligation balances in one server transaction. */
export async function recordSettlementWithAllocationsAtomic(
  input: RecordSettlementWithAllocationsInput,
): Promise<Settlement> {
  const { plans, normalizedSettlement, obligations: settledObligations } = prepareSettlement(input);
  const settlementId = newId();
  const allocationIds = plans.map(() => newId());
  const payloadInput: RecordSettlementWithAllocationsInput = {
    ...normalizedSettlement,
    allocations: plans,
  };
  const payload = buildRecordSettlementAtomicPayload(settlementId, payloadInput, allocationIds);
  const result = await invokeFinanceRpc<RecordSettlementAtomicResult>(
    P1B_ATOMIC_RPC_NAMES[3],
    payload,
  );
  const settlement = settlementsStore.getById(result.settlement_id);
  if (!settlement) {
    throw new Error('نجحت التسوية على الخادم لكن تعذر تحميلها بعد المزامنة.');
  }

  // Mirror the payment into the bank ledger if a bank/cash account was chosen.
  // Direction: receivable settlement -> we receive cash (deposit);
  // payable settlement -> we pay cash (withdrawal).
  if (normalizedSettlement.bank_account_id) {
    const firstObligation = settledObligations[0];
    try {
      await linkFinancialMovement({
        reference_type: 'settlement',
        reference_id: settlement.id,
        bank_account_id: normalizedSettlement.bank_account_id,
        direction: firstObligation?.direction === 'receivable' ? 'deposit' : 'withdrawal',
        amount: settlement.amount,
        currency: settlement.currency,
        fx_rate_to_base: settlement.fx_rate,
        transaction_date: settlement.settlement_date,
        memo: settlement.notes ?? null,
        partner_id: firstObligation?.partner_id ?? null,
        document_id: settlement.receipt_document_id ?? null,
      }, payload.p_request_id + '_bank');
    } catch {
      // Non-fatal — operator can reconcile later.
    }
  }

  return settlement;
}

export async function recordSettlementAtomic(
  obligationId: string,
  input: RecordSettlementInput,
): Promise<Settlement> {
  const normalized = validateSettlementInput({ ...input, obligation_id: obligationId });
  return recordSettlementWithAllocationsAtomic({
    ...input,
    allocations: [{ obligation_id: normalized.obligation_id, allocated_amount_egp: normalized.amount_egp }],
  });
}

/** Reverses a settlement and all affected obligation balances atomically. */
export async function reverseSettlementAtomic(settlementId: string, reason: string): Promise<Settlement> {
  const existing = settlementsStore.getById(settlementId);
  if (!existing) throw new Error('تعذر العثور على التسوية المطلوبة.');
  const normalizedReason = reason.trim();
  if (!normalizedReason) throw new Error('سبب عكس التسوية مطلوب.');

  const result = await invokeFinanceRpc<ReverseSettlementAtomicResult>(
    P1B_ATOMIC_RPC_NAMES[4],
    buildReverseSettlementAtomicPayload(settlementId, normalizedReason),
  );
  const settlement = settlementsStore.getById(result.settlement_id);
  if (!settlement) {
    throw new Error('نجح عكس التسوية على الخادم لكن تعذر تحميلها بعد المزامنة.');
  }
  return settlement;
}

// Legacy synchronous implementations are retained for isolated model tests.
function synchronizeObligations(obligationIds: string[], previous: Obligation[]) {
  const synchronized: string[] = [];
  try {
    for (const obligationId of obligationIds) {
      obligationsStore.syncSettlementTotal(obligationId, getActiveTotal(obligationId));
      synchronized.push(obligationId);
    }
  } catch (error) {
    for (const obligationId of synchronized) {
      const original = previous.find((item) => item.id === obligationId);
      if (original) obligationsStore.restoreForRollback(original);
    }
    throw error;
  }
}

export function recordSettlement(obligationId: string, input: RecordSettlementInput): Settlement {
  const normalized = validateSettlementInput({ ...input, obligation_id: obligationId });
  return recordSettlementWithAllocations({
    ...input,
    allocations: [{ obligation_id: normalized.obligation_id, allocated_amount_egp: normalized.amount_egp }],
  });
}

export function recordSettlementWithAllocations(input: RecordSettlementWithAllocationsInput): Settlement {
  const { plans, normalizedSettlement, obligations } = prepareSettlement(input);
  const previous = obligations.map((obligation) => ({ ...obligation }));
  const settlement = settlementsStore.create(normalizedSettlement);
  const allocationIds: string[] = [];
  try {
    for (const plan of plans) {
      const allocation = recordSettlementAllocation(
        { settlement_id: settlement.id, obligation_id: plan.obligation_id, allocated_amount_egp: plan.allocated_amount_egp },
        settlementsStore.getAll(),
        obligationsStore.getAll(),
      );
      allocationIds.push(allocation.id);
    }
    synchronizeObligations(plans.map((plan) => plan.obligation_id), previous);
    return settlement;
  } catch (error) {
    settlementAllocationsStore.removeManyForRollback(allocationIds);
    settlementsStore.removeForRollback(settlement.id);
    throw error;
  }
}

export function reverseSettlement(settlementId: string, reason: string): Settlement {
  const existing = settlementsStore.getById(settlementId);
  if (!existing) throw new Error('تعذر العثور على التسوية المطلوبة.');

  const allocationObligationIds = settlementAllocationsStore.getBySettlement(settlementId).map((item) => item.obligation_id);
  const affectedObligationIds = [...new Set(allocationObligationIds.length > 0 ? allocationObligationIds : [existing.obligation_id])];
  const previous = affectedObligationIds.map(requireObligation).map((obligation) => ({ ...obligation }));
  const settlement = settlementsStore.reverse(settlementId, reason);
  try {
    synchronizeObligations(affectedObligationIds, previous);
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
