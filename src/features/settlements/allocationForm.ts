import type { Obligation } from '../../core/types/domain';

const MONEY_EPSILON = 0.000001;

export function getObligationRemainingEgp(obligation: Obligation): number {
  return Math.max(0, obligation.amount_egp - obligation.amount_settled_egp);
}

export function getCompatibleSettleableObligations(anchor: Obligation | undefined, obligations: Obligation[]): Obligation[] {
  if (!anchor) return [];

  return obligations.filter((obligation) =>
    (obligation.status === 'open' || obligation.status === 'partial') &&
    obligation.partner_id === anchor.partner_id &&
    obligation.direction === anchor.direction &&
    obligation.project_id === anchor.project_id &&
    getObligationRemainingEgp(obligation) > MONEY_EPSILON,
  );
}

export interface SettlementAllocationFormPlan {
  obligation_id: string;
  allocated_amount_egp: number;
}

export function buildSettlementAllocationFormPlans(
  candidates: Obligation[],
  rawAmounts: Record<string, string>,
): SettlementAllocationFormPlan[] {
  const plans: SettlementAllocationFormPlan[] = [];

  for (const obligation of candidates) {
    const rawAmount = rawAmounts[obligation.id]?.trim();
    if (!rawAmount) continue;

    const amount = Number(rawAmount);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new Error('أدخل قيمة توزيع صحيحة أكبر من صفر.');
    }

    const remaining = getObligationRemainingEgp(obligation);
    if (amount - remaining > MONEY_EPSILON) {
      throw new Error('قيمة التوزيع أكبر من الرصيد المتبقي لأحد الالتزامات.');
    }

    plans.push({ obligation_id: obligation.id, allocated_amount_egp: amount });
  }

  if (plans.length === 0) throw new Error('أدخل قيمة توزيع واحدة على الأقل.');
  return plans;
}

export function getSettlementAllocationPlanTotal(plans: SettlementAllocationFormPlan[]): number {
  return plans.reduce((sum, plan) => sum + plan.allocated_amount_egp, 0);
}
