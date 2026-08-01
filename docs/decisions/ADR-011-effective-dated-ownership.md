# ADR-011: Effective-dated project ownership

## Status
Accepted — 2026-08-01

## Context
Project ownership changes over time: partners enter, exit, increase, or decrease their stakes.
A single `equity_pct` on `project_partners` cannot capture this history. We need to track
who owned what percentage, when, and why — while preventing invalid states (overlap, >100% sum).

## Decision
Implement effective-dated ownership with the following invariants:

1. **Append-only history**: `equity_change_events` records every ownership change. No UPDATE
   or DELETE of historical events — corrections are modeled as new events referencing the original.

2. **Temporal validity**: `project_partners` rows have `effective_from` and `effective_to`.
   An active record (effective_to IS NULL) represents current ownership. When ownership changes,
   the old record is closed (effective_to set) and a new one is opened.

3. **Sum ≤ 100% enforced server-side**: The RPC `change_ownership_atomic` validates that the
   sum of active equity percentages for a project never exceeds 100%. This is enforced within
   a transaction with advisory locking to prevent race conditions.

4. **No temporal overlap**: For a given project+partner, effective periods cannot overlap.
   This is validated by the RPC before inserting new records.

5. **Ownership-as-of-date query**: The function `get_ownership_as_of(project_id, date)` returns
   all active ownership records at a given point in time. This is used for distribution
   calculations and historical reporting.

6. **Type-safe change types**: `entry`, `increase`, `decrease`, `exit`, `correction` — each
   has constraints enforced by CHECK constraints (e.g., `entry` must go from 0% to >0%).

## Consequences
- **Positive**: Full audit trail of ownership changes. Historical queries are accurate.
  Server-side enforcement prevents invalid states even if clients are buggy.

- **Negative**: Slightly more complex schema and RPC logic. Clients must use the RPC
  `change_ownership_atomic` instead of direct table writes.

- **Migration**: Existing `project_partners` rows are preserved. Initial `equity_change_events`
  are created via a non-destructive data migration with diagnostic preflight checks.

## References
- `supabase/migrations/20260801000100_ownership_domain_tables.sql`
- `supabase/migrations/20260801000400_ownership_domain_rpcs.sql`
- `src/core/types/domain.ts` — `EquityChangeEvent` type
- `docs/plans/multi-project-ownership-domain.md`
