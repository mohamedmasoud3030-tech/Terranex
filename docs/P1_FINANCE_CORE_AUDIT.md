# P1 — Canonical Finance Core Audit

**Date:** 2026-08-16  
**Base SHA:** `4fe7364f980cd522593ca622ea782d5bc8765029`  

---

## Audit Scope

End-to-end review of the Terranex Finance Core as delivered through migrations S0–S7, GF-013–GF-024, and R4 (PR #144).

---

## 1. Double-Entry Posting

**Verdict: KEEP — Correct and database-enforced**

- `journal_batches` table with `source_type`, `source_id`, `transaction_date`, `reversal_of_batch_id`
- `journal_lines` table with `debit_minor_units` / `credit_minor_units` per line
- Statement-level AFTER INSERT trigger `s2_guard_batch_balanced()` enforces Σ debit = Σ credit per batch
- Each line constraint: `(debit_minor_units > 0 and credit_minor_units = 0) or (credit_minor_units > 0 and debit_minor_units = 0)`
- No editable balances — all truth is in the journal

## 2. Posting Batches

**Verdict: KEEP — Complete and immutable**

- Every posting requires a batch with source lineage
- One-active-source invariant: `s2_guard_one_active_source_posting()` prevents duplicate source postings
- Batches are immutable after creation (BEFORE UPDATE/DELETE trigger)
- Idempotent via `(organization_id, idempotency_key)` unique + `request_hash`

## 3. Exact Money

**Verdict: KEEP — Correct and consistent**

- All monetary values stored as `bigint` minor_units (pennies/piastres)
- Check constraints: `debit_minor_units >= 0`, `credit_minor_units >= 0`
- Domain commands parse major → minor units at the application layer via `parseMajorUnitsToMinor()`
- No floating point money anywhere

## 4. Currency Scale

**Verdict: KEEP — Complete for current scope**

- All monetary tables have `currency text check (currency ~ '^[A-Z]{3}$')`
- Project `reporting_currency` defines the project's functional currency
- Procurement enforces PO currency = project currency
- Payment enforces payment currency = cash account currency = obligation currency
- Multi-currency FX conversion is deferred to P7 (policy-dependent)

## 5. Immutable Posted Facts

**Verdict: KEEP — Strongly enforced**

- `s2_guard_journal_immutable()` prevents UPDATE/DELETE on all journal batches and lines
- Append-only triggers on project_payments, cost_obligations (after AUTHORIZED), reconciliation_matches
- Sector tables (harvest, livestock, agriculture sales) also append-only
- State-machine transitions (DRAFT→APPROVED, PROPOSED→APPROVED→POSTED) controlled by guards

## 6. Reversals/Replacements

**Verdict: KEEP — Complete and controlled**

- `reverse_journal_batch()` creates a linked reversal batch
- `reversal_of_batch_id` FK on journal_batches provides the reversal lineage
- Sector-specific reversal guards prevent reversing attributed cost sources before cost-attribution offsets
- Unique index `journal_batches_one_reversal` ensures one reversal per original batch
- S6 correction-request workflow for controlled reopen-and-repost

## 7. Project Attribution

**Verdict: KEEP — Enforced at database level**

- `project_id` on every financial table (journal_lines, cost_obligations, project_payments, etc.)
- Composite FKs: `(project_id, organization_id)` references `investment_projects(id, organization_id)`
- Payment scope guard validates obligation + cash_account + payment all share the same project
- Journal line scope guard validates line's project matches batch's project

## 8. Organization Coherence

**Verdict: KEEP — Enforced at database level with RLS**

- `organization_id` on every tenant-owned table
- Composite FKs ensure cross-tenant references are impossible
- RLS: `is_active_member(organization_id)` on all tables
- `FORCE ROW LEVEL SECURITY` on all tenant tables

## 9. Source Lineage

**Verdict: KEEP — Complete traceability**

- `journal_batches.source_type` + `source_id` traces every posting to its originating command
- Source types: `COST_OBLIGATION`, `PAYMENT`, `CONTRIBUTION_CASH_ATTRIBUTION`, `REVERSAL`, `PROPERTY_SALE_RECOGNITION`, `AGRICULTURE_SALE_RECOGNITION`, `LIVESTOCK_SALE_RECOGNITION`, etc.
- `cost_obligations.source_supplier_invoice_id` links obligations back to procurement
- Sector cost attributions reference specific journal line IDs

## 10. Idempotency

**Verdict: KEEP — Consistent pattern throughout**

- All domain commands accept `p_idempotency_key text`
- `pg_advisory_xact_lock` on organization + idempotency key for concurrency-safe replay
- Replay lookup before validation: returns existing result if key matches
- `request_hash` (SHA-256 of input parameters) prevents key reuse with different payload
- Unique index `(organization_id, idempotency_key)` on all command targets

## 11. Concurrency

**Verdict: KEEP — Well-protected**

- `pg_advisory_xact_lock` on idempotency keys serializes retries
- `FOR UPDATE` row locks on:
  - Cash accounts (payment proposal preparation and approval)
  - Obligations (payment, authorization)
  - Purchase orders (invoice approval, PO approval)
  - Harvest lots (inventory movements)
  - Livestock cohorts (purchase, sale)
- Deterministic lock order: cash account → obligation
- Non-deterministic lock acquisition for cohort purchases: `order by c.id for update`

## 12. Period Close

**Verdict: KEEP — Complete and controlled**

- `accounting_periods` with OPEN/CLOSED status per (org, project, currency)
- One open period per scope enforced by partial unique index
- Non-overlap guard: `s6_guard_period_no_overlap()`
- Immutable closed periods: `s6_guard_period_immutable_history()`
- Posting in open period validated by triggers `s6_validate_posting_in_open_period()` and `s6_validate_line_in_open_period()`
- Close runs with gates and exceptions; approved runs are immutable
- Controlled reopen via versioned supersede (new period version)

## 13. Bank Reconciliation

**Verdict: KEEP — Complete and correct**

- `bank_statement_imports` / `bank_statement_lines`: immutable external facts
- Statement line fingerprint (SHA-256) prevents duplicate import
- `reconciliation_matches`: one-to-one payment-to-statement matching
- Active match uniqueness: `reconciliation_active_line` (statement line) and `reconciliation_active_payment` (payment)
- Void-only state transition: economics immutable, void requires reason + idempotency key
- `void_idempotency_key` for idempotent void retry

## 14. Payment Integration

**Verdict: KEEP — Complete (extended by R4)**

- `project_payments`: immutable posted payment records
- Payment scope guard validates obligation, cash account, and project coherence
- R4 added `cost_payment_proposals` with maker/checker workflow
- Direct `pay_cost_obligation()` disabled; all payments go through proposal approval
- Payment journal: payable debit + bank cash credit = balanced posting

## 15. Obligation Integration

**Verdict: KEEP — Complete (extended by R4)**

- `cost_obligations` with DRAFT → AUTHORIZED workflow
- `authorize_cost_obligation()` creates the balanced journal batch
- R4 added `source_supplier_invoice_id` linkage from procurement
- Obligations carry `cost_treatment` (EXPENSE / CAPITALIZABLE_WIP)
- Payment against obligation enforces ceiling: Σ payments ≤ obligation amount
- Reversal check: cannot pay an obligation whose authorization has been reversed

---

## Classification Summary

| Area | Classification | Notes |
|------|---------------|-------|
| Double-entry | KEEP | Database-enforced balanced posting |
| Posting batches | KEEP | Immutable, source-linked, idempotent |
| Exact money | KEEP | Bigint minor_units everywhere |
| Currency scale | KEEP | ISO code constraint; FX deferred to P7 |
| Immutable posted facts | KEEP | Append-only + state-machine transitions |
| Reversals/replacements | KEEP | Linked reversal chain, S6 correction workflow |
| Project attribution | KEEP | Composite FKs + scope guards |
| Organization coherence | KEEP | RLS + FORCE RLS + composite FKs |
| Source lineage | KEEP | `source_type` + `source_id` on all batches |
| Idempotency | KEEP | Advisory lock + request_hash pattern throughout |
| Concurrency | KEEP | Advisory locks + FOR UPDATE with deterministic order |
| Period close | KEEP | Versioned periods, close runs, controlled reopen |
| Bank reconciliation | KEEP | One-to-one matching, void-only state transition |
| Payment integration | KEEP | R4 proposals complete; direct posting disabled |
| Obligation integration | KEEP | DRAFT→AUTHORIZED with ceiling and reversal check |

**No HARDEN, BUILD, MIGRATE, or DEFER items identified.** The Finance Core is production-grade for its authorized scope. The remaining financial capabilities (budget/forecast, credits/payment allocation, contract obligations, SoD consolidation, FX, tax, financial integrity center) are covered by P2–P8 and do not require rewriting the core.

---

*Audit performed 2026-08-16 against `main@4fe7364f980cd522593ca622ea782d5bc8765029`*