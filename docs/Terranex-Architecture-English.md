# Terranex — Architecture Documentation

## Ownership & Partner Ledger Domain Closure

### Ownership Documentation Discovery Findings

This section documents the transition of the Terranex architecture from a basic project-tracking system to a robust, multi-project investment operating system with historical ownership and partner accounting.

1.  **Pre-Ownership Architecture**:
    *   Ownership was modeled as a simple static field or a basic join table without historical tracking.
    *   No ledger existed for partner financial movements.
    *   Distributions were not tracked or were treated as simple expense transactions.
    *   Profitability calculations applied current ownership percentages to all historical data, leading to inaccurate retrospective reporting.

2.  **Confirmed Gaps (Now Solved)**:
    *   **Lack of Audit Trail**: Ownership changes were not recorded as events. *Solved by `equity_change_events`.*
    *   **Invalid State Prevention**: No server-side enforcement of 100% equity sum. *Solved by `change_ownership_atomic` RPC.*
    *   **No Partner Accounting**: No central place to view partner contributions and withdrawals. *Solved by `partner_ledger_entries`.*
    *   **Historical Inaccuracy**: Profit was incorrectly attributed to partners who joined after the profit was realized. *Solved by temporal slicing in the Profitability Engine.*

3.  **Final Implementation Highlights**:
    *   **Effective-Dated Ownership**: Ownership belongs to a specific Project + Partner relationship and is valid for a specific period.
    *   **Atomic Mutation Boundary**: All financial and ownership changes are controlled by server-side RPCs that enforce invariants and ensure idempotency.
    *   **Immutable Snapshots**: Distributions freeze ownership state to prevent historical rewrites.
    *   **Separation of Concerns**: Settlements (debt repayment) are explicitly separated from Distributions (profit sharing).

4.  **Source of Truth**:
    *   **Schema**: `supabase/migrations/20260801000100_ownership_domain_tables.sql` through `20260801000700_ownership_distribution_entitlements_and_immutability.sql`.
    *   **Types**: `src/core/types/domain.ts`.
    *   **Logic**: `src/core/lib/profitability.ts` and Supabase RPCs.

---

## Ownership & Partner Ledger Domain

### Entities

#### Partner
A `Partner` represents an external entity (individual or company) interacting with Terranex.
*   **Hybrid Model**: A partner can be an **Equity Partner** (holding shares in one or more projects) and/or a **Counterparty** (supplier, client, or service provider).
*   **Key Fields**: `id`, `name_ar`, `name_en`, `category` (`equity_partner` | `counterparty`), `counterparty_role`.

#### Project Partner (Effective-Dated Ownership)
Defines the ownership stake of a partner in a specific project during a specific time period.
*   **Equity Percentage**: `equity_pct` (0–100).
*   **Temporal Validity**: `effective_from` and `effective_to` define when this stake was active.
*   **Invariants**: The sum of active `equity_pct` for a project cannot exceed 100%. History is preserved; rows are never overwritten.

#### Equity Change Event
An immutable audit record of a change in ownership.
*   **Change Types**: `entry`, `increase`, `decrease`, `exit`, `correction`.
*   **Fields**: `previous_pct`, `new_pct`, `effective_date`, `change_type`, `consideration_amount`, `consideration_currency`, `frozen_amount_egp`.

#### Partner Ledger Entry
An append-only record of all financial movements for a partner within a project.
*   **Immutability**: Entries cannot be edited or deleted. Corrections must use a reversal entry (`reversal_of_id`).
*   **Entry Types**: `capital_contribution`, `withdrawal`, `distribution_entitlement`, `distribution_payment`, `correction`, `reversal`.
*   **Financial Effect**: Balance is calculated as the sum of all non-reversed entries.
*   **Fields**: `amount`, `currency`, `fx_rate`, `amount_egp`, `posting_date`, `reversal_of_id`.

#### Distribution
A record of a profit distribution cycle for a project.
*   **Ownership Snapshot**: At the time of creation, the distribution freezes the ownership percentages as of the `ownership_as_of_date`.
*   **Fields**: `distribution_date`, `ownership_as_of_date`, `total_amount`, `currency`, `fx_rate`, `total_amount_egp`, `status`.

#### Distribution Allocation
The specific share of a distribution allocated to an individual partner.
*   **Frozen State**: The `equity_pct_snapshot` and `allocated_amount` are saved at the moment of distribution and are never recalculated, even if ownership changes later.
*   **Rounding**: Any rounding differences in the total distribution are allocated to the partner with the largest share to ensure the sum of allocations exactly matches the total distribution amount.

---

## Entity Map

The following map illustrates the relationships between core Terranex entities:

```text
Sector
  → Project
      → Asset
      → Transaction
      → Obligation
          → Settlement
      → Project Partner (Effective-Dated Ownership)
          → Equity Change Event
      → Distribution
          → Distribution Allocation
              → Partner
              → Partner Ledger Entry

Partner
  → Project Memberships (Project Partner)
  → Partner Ledger Entries
  → Distribution Allocations
  → Documents / Evidence

Profitability Engine
  ← Transactions (Income/Expense)
  ← Effective-Dated Ownership (Temporal Slicing)
  ← Distributions (Reporting Only)
  ← Partner Ledger Entries (Position Tracking)
```

**Key Architectural Constraints**:
1.  **Ownership Scope**: Ownership is defined per Project + Partner, not globally.
2.  **Financial Separation**: Settlements reduce `Obligations` (debt); Distributions allocate profit from the project to the `Partner Ledger`.
3.  **Temporal Integrity**: Profitability is calculated by applying the ownership active on the specific date of each transaction.

---

## Profitability Architecture

The Terranex Profitability Engine (`src/core/lib/profitability.ts`) implements temporal rules to ensure financial accuracy:

1.  **Temporal Slicing**: Partner entitlement is calculated transaction-by-transaction. The engine identifies the active partners and their percentages on the `transaction_date` and allocates that specific transaction's value accordingly.
2.  **No Retroactive Re-attribution**: Changes to current ownership do not affect the attribution of historical transactions.
3.  **Distribution Distinction**: Distributed profit is treated as a separate financial event from realized operational profit. Distributions do not appear as project expenses.
4.  **Ledger Independence**: Partner ledger balances are tracked separately from operational profit entitlement, allowing for clear reporting of what is "earned" vs. what is "paid".
5.  **Audit Visibility**: Reversed records (ledger entries or distributions) remain visible in the audit trail but have zero effect on financial totals.

---

## Server Enforcement and RPC Boundary

Terranex enforces a strict **Server-Authoritative Mutation Boundary**. Direct writes to financial or ownership tables from the client are prohibited. All mutations must go through authorized PostgreSQL RPCs:

*   **`change_ownership_atomic`**: Validates project ownership, enforces the 100% equity limit, handles temporal closing of previous records, and logs the change.
*   **`record_distribution_atomic`**: Calculates allocations based on a historical ownership snapshot and ensures rounding integrity.
*   **`record_partner_ledger_entry_atomic`**: Enforces the append-only nature of the ledger and validates reversal targets.
*   **`get_ownership_as_of`**: Provides a security-definer interface to query ownership state at any point in time.

**Safety Features**:
*   **Request Idempotency**: All RPCs require a `p_request_id` to prevent duplicate execution.
*   **Advisory Locking**: Prevents race conditions during concurrent ownership updates.
*   **RLS Isolation**: Row-Level Security ensures that even through RPCs, users can only modify data they own.

---

## ADR Synchronization

The following Architectural Decision Records define the ownership domain:

*   **ADR-011 — Effective-Dated Project Ownership**: Ownership is historical and temporal. Overwriting percentages is prohibited.
*   **ADR-012 — Append-Only Partner Ledger**: Financial movements are immutable events. Corrections require reversals.
*   **ADR-013 — Immutable Distribution Snapshots**: Distributions freeze percentages to prevent historical profit re-calculation.
*   **ADR-014 — Settlement and Distribution Separation**: Debt repayment and profit sharing are distinct workflows.

### Out of Scope (Future Domains)
The following capabilities are **intentionally excluded** from the current Terranex implementation:
*   Preferred Returns, Waterfalls, and Carried Interest.
*   Formal Capital Calls and Drawdowns.
*   SPV / Fund structures.
*   KYC/AML and Investor Accreditation workflows.
*   IRR, MOIC, TVPI, and NAV calculations.

---

## Currency Model

Terranex uses a **Dual-Amount Storage Model**:

1.  **Base Currency (EGP)**: All reporting, consolidation, and cross-project analysis use the Egyptian Pound (`amount_egp`).
2.  **Transaction Currency**: The original amount and currency are preserved for audit and local project tracking.
3.  **Frozen Exchange Rates**: The `fx_rate` is captured and stored at the time of the transaction (or distribution). Historical totals are **never recalculated** based on current exchange rates, preventing "phantom" P&L swings.

---

## Roadmap Status

The Multi-Project Ownership Domain is **Completed** as of August 2026.
*   **DB/RPC Foundation**: Fully implemented and tested.
*   **UI/UX**: Ownership history and Partner Ledger workspaces are integrated.
*   **Profitability**: Temporal engine is active.
*   **Reporting**: Intelligence reports now reflect partner entitlements and ledger positions.

For detailed implementation status, see `docs/plans/multi-project-ownership-domain.md`.
