# Multi-Project Ownership Domain — Implementation Plan

**Status:** Vertical Slice Complete in repository (DB + Types + RPCs + UI + Profitability + Reporting + Tests) — 2026-08-01
**ADRs:** ADR-011 (Effective-dated ownership), ADR-012 (Append-only ledger), ADR-013 (Immutable distributions), ADR-014 (Settlement vs distribution separation)

---

## 1. Discovery Findings

### Current State (Pre-Implementation)
- `project_partners` table exists with `equity_pct`, `effective_from`, `effective_to`
- No enforcement of sum ≤ 100% (client-side validation only)
- No temporal overlap prevention
- No audit trail for ownership changes
- No partner ledger
- No distribution tracking
- Profitability engine uses current ownership only (no historical queries)

### Problems Identified
1. **No server-side enforcement**: Clients can create invalid states (>100%, overlapping periods)
2. **No history**: Cannot answer "who owned what on date X?"
3. **No reversibility**: Deleting a partner loses all ownership history
4. **No profit distribution**: Cannot track what was distributed vs. what was earned
5. **No partner accounting**: No way to see all financial movements for a partner

---

## 2. Architecture Decision

### Effective-Dated Ownership with Atomic RPCs

**Core principle**: All ownership changes go through `change_ownership_atomic`, which:
1. Validates project ownership (auth.uid() = project.owner_id)
2. Takes an advisory lock on (owner_id, request_id) to prevent race conditions
3. Checks idempotency via `financial_audit_logs`
4. Validates change_type consistency (entry must go 0→>0, exit must go >0→0)
5. Calculates sum of other partners' active equity
6. Rejects if sum + new_pct > 100%
7. Closes previous `project_partners` record (sets effective_to)
8. Inserts new `project_partners` record
9. Inserts `equity_change_events` for audit
10. Logs to `financial_audit_logs`

### Append-Only Partner Ledger

**Core principle**: All partner financial movements are recorded in `partner_ledger_entries`:
- Immutable (no UPDATE or DELETE)
- Reversible via new entries with `reversal_of_id`
- Linked to distributions, equity events, and documents
- Balance = Σ(contributions + entitlements) - Σ(withdrawals + payments)

### Immutable Distribution Snapshots

**Core principle**: Distributions freeze ownership percentages at `ownership_as_of_date`:
- `distribution_allocations.equity_pct_snapshot` is frozen
- `allocated_amount` is frozen
- Rounding assigned to largest-share partner
- Sum of allocations = total amount (exact)

### Separation of Settlements vs Distributions

**Core principle**: Settlements reduce obligations; distributions allocate profits.
- `settlements` → `obligations` (debt repayment)
- `distributions` → `partner_ledger_entries` (profit allocation)
- No automatic linking — net position calculated from ledger

---

## 3. Implementation Phases

### Phase 1: Database Schema + RPCs ✅ COMPLETE

**Delivered:**
- 4 new tables: `equity_change_events`, `partner_ledger_entries`, `distributions`, `distribution_allocations`
- 4 new enum types: `terranex_equity_change_type`, `terranex_ledger_entry_type`, `terranex_distribution_status`, `terranex_distribution_allocation_status`
- RLS policies (enable + force) on all 4 tables
- Grants for authenticated role
- 3 atomic RPCs: `change_ownership_atomic`, `record_distribution_atomic`, `record_partner_ledger_entry_atomic`
- 1 query function: `get_ownership_as_of`
- Non-destructive data migration with diagnostic preflight
- 5 rollback scripts
- Database test suite (06_ownership_domain.sql) with 8 test scenarios

**Verified:**
- Typecheck passes ✅
- Lint passes ✅
- Tests pass (202/202) ✅
- Build succeeds ✅

**Files:**
- `supabase/migrations/20260801000100_ownership_domain_tables.sql`
- `supabase/migrations/20260801000200_ownership_domain_rls.sql`
- `supabase/migrations/20260801000300_ownership_domain_grants.sql`
- `supabase/migrations/20260801000400_ownership_domain_rpcs.sql`
- `supabase/migrations/20260801000500_ownership_data_migration.sql`
- `supabase/rollback/20260801000100_ownership_domain_tables.down.sql`
- `supabase/rollback/20260801000200_ownership_domain_rls.down.sql`
- `supabase/rollback/20260801000300_ownership_domain_grants.down.sql`
- `supabase/rollback/20260801000400_ownership_domain_rpcs.down.sql`
- `supabase/rollback/20260801000500_ownership_data_migration.down.sql`
- `supabase/tests/06_ownership_domain.sql`
- `scripts/db-test.sh` (updated to include 2B test)
- `supabase/migrations/20260801000700_ownership_distribution_entitlements_and_immutability.sql`
- `supabase/rollback/20260801000700_ownership_distribution_entitlements_and_immutability.down.sql`

### Phase 2: Domain Types + Validation ✅ COMPLETE

**Delivered:**
- 4 new types in `domain.ts`: `EquityChangeEvent`, `PartnerLedgerEntry`, `Distribution`, `DistributionAllocation`
- Zod validation schemas in `validation.ts`
- Storage layer in `src/features/ownership/storage.ts`
- Store registry integration in `src/features/storeRegistry.ts`

**Files:**
- `src/core/types/domain.ts` (updated)
- `src/core/lib/validation.ts` (updated)
- `src/features/ownership/storage.ts` (new)
- `src/features/ownership/index.ts` (new)
- `src/features/storeRegistry.ts` (updated)

### Phase 3: UI Components ✅ COMPLETE

**Delivered:**
- Project ownership section in the existing Portfolio/project-detail workspaces.
- Effective-date ownership-as-of selector with assigned/unassigned equity metrics and <100% warning.
- Ownership history timeline from `equity_change_events` plus migrated `project_partners` fallback records.
- Ownership change form using the existing `AdaptiveFormSurface`; it blocks duplicate submit through the shared pending state, keeps the form open on server rejection, and closes only after the atomic RPC succeeds.
- Partner workspace memberships, immutable partner ledger, ledger filters, position summary, distribution list, and manual ledger entry form.
- Finance Hub distribution workspace and distribution creation form with allocation preview.
- Existing Arabic-first RTL/mobile surface patterns are reused; no new top-level route was added.

### Phase 4: Integration with Profitability Engine ✅ COMPLETE

**Delivered:**
- `computeProjectProfitability` accepts `as_of_date`/period inputs and ownership/distribution/ledger datasets.
- Partner entitlement is calculated transaction-by-transaction using ownership effective on each transaction date.
- Distributed profit, undistributed profit, paid distributions, unpaid distributions, and partner ledger position are reported separately.
- Settlements remain obligation repayments and are not counted as profit distributions.
- Distribution amounts do not reduce operating expenses.

### Phase 5: Testing ✅ COMPLETE IN NODE SUITE; DB SCRIPT BLOCKED LOCALLY BY MISSING `psql`

**Delivered:**
- Ownership service payload, retry/idempotency, failure rehydration, distribution allocation, entitlement ledger, and profitability slicing tests in `tests/ownership-vertical-slice.test.cjs`.
- Existing UI contract tests continue to cover workspace routing, adaptive surfaces, focus, mobile-safe controls, and RTL-compatible component structure.
- `supabase/tests/06_ownership_domain.sql` now verifies distribution entitlement ledger posting and immutability triggers in addition to existing ownership/domain invariants.
- Local `scripts/db-test.sh` could not run in this sandbox because `psql` is not installed; the repository SQL suite has been updated for CI/real-Postgres execution.

---

## 4. Migration Strategy

### Non-Destructive Migration

The migration `20260801000500_ownership_data_migration.sql` creates initial `equity_change_events`
for existing `project_partners` records:

1. **Diagnostic preflight**: Checks for invalid data (duplicates, overlaps, >100% sum)
2. **Append-only insert**: Creates `entry` events for each existing `project_partners` row
3. **Idempotent**: Uses `NOT EXISTS` to avoid duplicates on re-run

### Rollback Strategy

Each migration has a corresponding rollback script:
- Tables are dropped (destructive)
- Enum types are dropped
- RPCs are dropped
- Data migration rollback deletes only the migrated rows (by reason field)

---

## 5. Testing Strategy

### Database Tests (`06_ownership_domain.sql`)

1. **Ownership sum ≤ 100%**: Insert 3 partners, try to exceed 100%, verify rejection
2. **Temporal overlap prevention**: Entry + exit, verify history preserved
3. **Cross-tenant access prevention**: Try to access another owner's project
4. **Ownership-as-of-date query**: Query at different dates, verify correct ownership
5. **Distribution allocations sum = total**: Create distribution, verify allocations match
6. **Append-only ledger**: Create entries, verify balance calculation
7. **Idempotency**: Call same RPC twice, verify only one record created
8. **Schema contract**: Verify all RPCs exist with correct search_path

### Future Tests

- Unit tests for storage layer methods
- Integration tests for RPC + storage interaction
- UI contract tests for new components

---

## 6. Documentation

### Created
- ADR-011: Effective-dated project ownership
- ADR-012: Append-only partner ledger
- ADR-013: Immutable distribution snapshots
- ADR-014: Separation of settlements from distributions
- This plan document

### Updated
- `docs/supabase/INVENTORY.md` — Added 4 ownership tables, 4 RPCs, and the entitlement/immutability hardening migration.
- `AGENTS.md` — Status reflects the completed ownership vertical slice and current Node test count.
- `IMPLEMENTATION_GUIDE.md` — Documents the RPC-only mutation boundary, temporal profitability rule, ledger reversal semantics, and settlement/distribution separation.
- `README.md` — Launch-status and feature summary updated without claiming production deployment.

---

## 7. Verification Checklist

- [x] Typecheck passes
- [x] Lint passes
- [x] Tests pass (226/226)
- [x] Build succeeds
- [x] Migrations are non-destructive
- [x] Rollback scripts exist (new local execution blocked by missing `psql`; previous DB suite coverage remains in CI path)
- [x] Database test SQL covers the required invariants; local execution requires `psql`
- [x] ADRs created
- [x] INVENTORY.md updated
- [x] UI components created
- [x] Profitability engine integrated
- [x] Unit tests for ownership model/service layer
- [x] Integration tests for RPC + store rehydration (Fake Supabase)
- [x] SQL tests extended for entitlement ledger and immutability
- [ ] Local real-Postgres script execution in this sandbox (blocked: `psql` unavailable)

---

## 8. Known Limitations

1. **No multi-currency distributions**: Distributions currently use project's base currency
2. **No recurring distributions**: Must create each distribution manually
3. **No approval workflow**: Distributions go directly to `draft` status
4. **No dedicated distribution PDF template**: CSV export is implemented through the Intelligence exporter; PDF remains the existing global profitability PDF.
5. **No notifications**: Partners are not notified when distributions are created

---

## 9. Future Enhancements

1. **Recurring distributions**: Schedule automatic distributions (monthly, quarterly)
2. **Approval workflow**: Multi-step approval for large distributions
3. **Email notifications**: Notify partners when distributions are available
4. **PDF export**: Generate distribution reports
5. **Multi-currency support**: Distributions in partner's preferred currency
6. **Tax calculations**: Withhold taxes from distributions
7. **Integration with accounting systems**: Export to QuickBooks, Xero, etc.

---

**Last updated:** 2026-08-01
**Author:** Terranex Agent
**Status:** Phase 1 + 2 Complete, Phase 3-5 Pending
