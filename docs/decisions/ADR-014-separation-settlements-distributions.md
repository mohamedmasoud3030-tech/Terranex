# ADR-014: Separation of obligation settlements from profit distributions

## Status
Accepted — 2026-08-01

## Context
The system has two distinct types of financial movements:
1. **Obligation settlements**: Paying down receivables or payables (debts)
2. **Profit distributions**: Distributing profits to equity partners

These are semantically different:
- Settlements reduce obligations (liabilities)
- Distributions allocate profits (income)

Mixing them in the same table would conflate these concepts and make reporting confusing.

## Decision
Keep settlements and distributions as separate domains:

1. **Settlements** (`settlements`, `settlement_allocations`):
   - Reduce `obligations.amount_settled_egp`
   - Linked to `obligations` (receivables/payables)
   - Track debt repayment, not profit allocation
   - Used for cash flow and obligation aging

2. **Distributions** (`distributions`, `distribution_allocations`):
   - Allocate profit to equity partners based on ownership percentages
   - Linked to `partner_ledger_entries` when paid
   - Track profit allocation, not debt repayment
   - Used for partner statements and profit reporting

3. **Partner ledger** (`partner_ledger_entries`):
   - Records both distribution entitlements (`distribution_entitlement`)
   - And distribution payments (`distribution_payment`)
   - Provides a unified view of all partner financial movements

4. **No automatic linking**: A distribution does not automatically create a settlement.
   If a partner owes money (payable) and also receives a distribution, these are separate
   transactions. The partner's net position is calculated from the ledger.

## Consequences
- **Positive**: Clear semantic separation. Obligations track debts, distributions track
  profit allocation. Reporting is straightforward. No confusion about what a "settlement"
  means.

- **Negative**: Partners with both obligations and distributions need to calculate their
  net position from the ledger (obligations + ledger entries). This is more complex than
  a single table, but semantically correct.

## References
- `supabase/migrations/20260725000200_core_tables.sql` — settlements tables
- `supabase/migrations/20260801000100_ownership_domain_tables.sql` — distributions tables
- `docs/decisions/ADR-013-immutable-distribution-snapshots.md`
