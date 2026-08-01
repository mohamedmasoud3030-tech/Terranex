# ADR-012: Append-only partner ledger

## Status
Accepted — 2026-08-01

## Context
Partners contribute capital, withdraw funds, receive distributions, and make payments.
Tracking these movements requires an append-only ledger that:
- Cannot be modified after posting (immutability)
- Supports reversals (not deletions)
- Calculates running balances
- Links to supporting documents and related events

## Decision
Implement `partner_ledger_entries` as an append-only financial record:

1. **Immutable entries**: Once created, a ledger entry cannot be updated or deleted.
   Corrections are modeled as new entries with `entry_type = 'correction'` or `'reversal'`,
   referencing the original via `reversal_of_id`.

2. **Entry types**: `capital_contribution`, `withdrawal`, `distribution_entitlement`,
   `distribution_payment`, `correction`, `reversal`. Each type has clear semantics for
   balance calculations.

3. **Balance calculation**: Running balance = sum of active contributions/entitlements - sum of
   active withdrawals/payments. Reversal rows and originals referenced by reversal rows remain
   visible for audit but have zero active effect. `partnerLedgerEntriesStorage.calculateBalance()`
   and the ownership model helpers implement this logic.

4. **Linking**: Entries can reference:
   - `related_equity_event_id` — links to ownership changes
   - `related_distribution_id` — links to profit distributions
   - `supporting_document_id` — links to contracts, receipts, etc.

5. **Frozen amounts**: All amounts are stored in both native currency and EGP equivalent
   (using the FX rate at posting time). This matches the existing transaction pattern.

6. **Server-side RPC**: `record_partner_ledger_entry_atomic` ensures the entry is created
   atomically with audit logging and idempotency.

## Consequences
- **Positive**: Full audit trail of all partner financial movements. Reversible without
  losing history. Clear separation between different types of movements.

- **Negative**: More complex balance calculations (must exclude reversals). Clients must
  use the RPC instead of direct writes.

## References
- `supabase/migrations/20260801000100_ownership_domain_tables.sql`
- `src/core/types/domain.ts` — `PartnerLedgerEntry` type
- `src/features/ownership/storage.ts` — `partnerLedgerEntriesStorage`
