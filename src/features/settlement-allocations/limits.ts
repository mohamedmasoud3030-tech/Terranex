import type { Obligation } from '../../core/types/domain';
import type { Settlement } from '../settlements/types';
import type { SettlementAllocation } from './types';

export function assertSettlementAllocationLimits(
  settlementId: string,
  obligationId: string,
  amountEgp: number,
  settlements: Settlement[],
  obligations: Obligation[],
  allocations: SettlementAllocation[],
  activeObligationTotal: number,
) {
  const settlement = settlements.find((item) => item.id === settlementId);
  if (!settlement || settlement.status !== 'active') throw new Error('التسوية المرتبطة بالتوزيع غير صالحة.');
  const obligation = obligations.find((item) => item.id === obligationId);
  if (!obligation) throw new Error('الالتزام المرتبط بالتوزيع غير موجود.');
  if (allocations.some((item) => item.settlement_id === settlementId && item.obligation_id === obligationId)) {
    throw new Error('يوجد توزيع مسجل بالفعل لنفس التسوية والالتزام.');
  }
  const settlementTotal = allocations.filter((item) => item.settlement_id === settlementId).reduce((sum, item) => sum + item.allocated_amount_egp, 0);
  if (settlementTotal + amountEgp > settlement.amount_egp) throw new Error('إجمالي التوزيعات أكبر من قيمة التسوية.');
  if (activeObligationTotal + amountEgp > obligation.amount_egp) throw new Error('قيمة التوزيع أكبر من الرصيد المتبقي للالتزام.');
}
