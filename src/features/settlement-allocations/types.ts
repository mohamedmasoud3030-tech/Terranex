/** Immutable allocation of a posted settlement to one obligation. */
export interface SettlementAllocation {
  id: string;
  settlement_id: string;
  obligation_id: string;
  allocated_amount_egp: number;
  created_at: string;
}
