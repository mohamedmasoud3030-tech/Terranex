# ADR-013: Immutable distribution snapshots

## Status
Accepted — 2026-08-01

## Context
When a project distributes profits, each partner's share is calculated based on their
ownership percentage at a specific point in time. If ownership changes later (e.g., a
partner exits), historical distributions should NOT be recalculated. We need to freeze
(denominate) the allocation amounts at distribution time.

## Decision
Implement distributions with immutable snapshots:

1. **Distribution header**: `distributions` table stores the total amount, currency,
   FX rate, distribution date, and `ownership_as_of_date` (the date when ownership
   percentages are evaluated).

2. **Frozen allocations**: `distribution_allocations` stores each partner's share with
   `equity_pct_snapshot` (the percentage at distribution time) and `allocated_amount`
   (the frozen amount). These values are never recalculated.

3. **Rounding policy**: When allocating amounts, rounding errors are assigned to the
   partner with the largest share. This ensures `sum(allocations) = total_amount`
   exactly. The RPC `record_distribution_atomic` implements this logic.

4. **Ownership snapshot**: The RPC queries `project_partners` filtered by
   `effective_from <= ownership_as_of_date` and `(effective_to IS NULL OR effective_to >= ownership_as_of_date)`
   to get the ownership percentages at that point in time.

5. **Ledger integration and payment tracking**: `record_distribution_atomic` creates
   `distribution_entitlement` ledger entries for every frozen allocation in the same database
   transaction. Each allocation has a `status` (due/paid/reversed), `payment_date`, and
   `payment_document_id`. When paid, a corresponding `partner_ledger_entry` is created with
   `entry_type = 'distribution_payment'` and linked via `related_ledger_entry_id`.

6. **Status workflow**: Distributions follow `draft → approved → paid → reversed`.
   Allocations follow `due → paid → reversed`.

## Consequences
- **Positive**: Historical distributions are immutable and audit-proof. Ownership changes
  after distribution do not affect past allocations. Clear separation between calculated
  profit (from transactions), distributable amount (from profitability), and actual
  distributions (from ledger).

- **Negative**: Cannot retroactively adjust distributions if ownership percentages were
  wrong. Must create a correction distribution or reversal.

## References
- `supabase/migrations/20260801000100_ownership_domain_tables.sql`
- `supabase/migrations/20260801000400_ownership_domain_rpcs.sql`
- `src/core/types/domain.ts` — `Distribution`, `DistributionAllocation` types
- `docs/decisions/ADR-014-separation-settlements-distributions.md`
