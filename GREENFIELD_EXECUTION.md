# Greenfield Execution Status

**Updated:** 2026-08-12  
**Working branch:** `greenfield/foundation`  
**Strategy:** Product-first, Egypt-first, thin vertical slices

This file records execution state only. Detailed domain/accounting decisions belong in the numbered ADRs and the approved Greenfield product documents.

## Foundation

Status: **COMPLETE**.

- Legacy product frozen at `legacy/pre-greenfield-20260810`; it is not a source for Greenfield behavior.
- Eight Greenfield product documents are the conceptual baseline.
- Product-first Egypt launch: `docs/decisions/0001_PRODUCT_FIRST_BUILD.md`.
- Simple modular-monolith delivery: `docs/decisions/0002_SIMPLICITY_AND_VERTICAL_SLICES.md`.
- Customer interviews/design partner are not build prerequisites.

## Completed batches

### GF-002 / S0 — Executable Foundation and Project Shell

Status: **COMPLETE**. Merged through PR #84.

Proof: Arabic responsive application shell, organization/project creation, Supabase tenancy/RLS/audit baseline, deterministic npm install, PostgreSQL 16 replay, two-tenant isolation.

### GF-003 / S1 — Terms & Funding

Status: **COMPLETE — VERIFIED AND MERGED**. Integration PR #88.

Proof: parties/participants, immutable governing agreement version, commitments, capital calls/contributions, exact capital rollforward, payload-bound idempotency, OWNER material approval, RLS/cross-project integrity, real over-call/over-contribution races.

Canonical decision: `docs/decisions/0003_S1_TERMS_AND_FUNDING.md`.

### GF-004 / S2 — Cost & Cash

Status: **COMPLETE — VERIFIED AND MERGED**.

Proof: project cash accounts, controlled contribution-to-cash attribution, obligations/payment/reconciliation, balanced immutable subledger, exact bigint money transport, bank-statement fingerprinting, linked reversals, OWNER material approval, real payment/posting/reconciliation concurrency, forward upgrade.

Canonical decision: `docs/decisions/0004_S2_COST_AND_CASH.md`.

### GF-005 / S3 — Real Estate Sector Operation

Status: **COMPLETE — VERIFIED AND MERGED**.

Proof: Real Estate project profile, property/parcels, authoritative lifecycle/history, acquisition/control evidence, development phases/milestones/events, immutable budget versions, S2-backed property cost control, management valuation kept separate from accounting, hierarchy integrity, real lifecycle concurrency, forward upgrade.

Canonical decision: `docs/decisions/0005_S3_REAL_ESTATE_OPERATIONS.md`.

### GF-006 / S4 — Revenue & Realized Result

Status: **COMPLETE — VERIFIED AND MERGED**.

Proof: disposition/control-transfer lifecycle, balanced sale recognition and carrying-cost derecognition, partial/multiple collection, bank reconciliation reuse, realized-result read models, selling-cost separation, no implicit accounting from operational states, real recognition/collection races, forward upgrade.

Canonical decision: `docs/decisions/0006_S4_REVENUE_AND_REALIZED_RESULT.md`.

### GF-007 / S6 — Period Close and Controlled Correction

Status: **COMPLETE — VERIFIED AND MERGED**.

Merged through PR #98 on 2026-08-12. Merge commit: `d26a3bbbc9a8e29b61bb0a4ecfd2a21bf9e0a0c6`.

Delivered and verified:

1. Versioned accounting periods with one authoritative OPEN period per organization/project/currency scope and immutable CLOSED rows.
2. Database-enforced period lock on financial posting once period management is authoritative for the project.
3. Versioned close runs with ten server-side close controls, OWNER approval, and immutable content-hashed close snapshots.
4. Truthful `BANK_RECONCILIATION_COVERAGE`: unresolved lines are FAIL and can only move to `APPROVED_EXCEPTION` through an audited exception workflow.
5. Period-scoped sector cut-off and reproducible sector rollforward controls without forcing valid operational assets to artificial maturity.
6. Controlled reopen as a new superseding period version; no rewrite of the closed period.
7. Forward correction request/approval/execution using exact linked journal reversal; original S2/S4 economics and provenance stay immutable.
8. Correct close-exception relational integrity and composite-gate recomputation.
9. PostgreSQL-safe strict S6 SQL assertions; historical S2/S3/S4 concurrency and forward-upgrade fixtures remain compatible without weakening production controls.
10. Canonical PostgreSQL 16 Greenfield CI run #68: application PASS and database PASS, including S0–S4 regressions, S3/S4 forward upgrades, S6 SQL, S6 two-session concurrency, and S6 forward upgrade.
11. SonarQube Cloud Quality Gate PASS, 0 security hotspots, 1.7% duplication on new code.

Canonical decision: `docs/decisions/0007_S6_PERIOD_CLOSE_AND_CORRECTION.md`.

## Explicitly deferred

- S5 allocation, distribution approval/payment, partner capital statement and investor statement;
- agreement amendment/supersession and funding carry-forward beyond the implemented governing version;
- advanced waterfall economics: preferred return, hurdle tiers, GP catch-up, carry, clawback, tax/withholding and cross-project netting;
- statutory/general ledger, chart-of-accounts editor, external accounting adapters, bank APIs/open banking, VAT/tax/e-invoicing;
- fuzzy/split/many-to-many bank reconciliation and multi-currency/FX engine;
- private DMS/platform, generic workflow/approval engine, notifications/outbox/integrations;
- partial-property disposition and other sector-specific complexity not required by the current Real Estate vertical slice;
- leasing/property management and construction ERP/procurement/BOQ/change-order scope;
- PWA/offline sync;
- Agriculture and Livestock runtime modules;
- generic repositories, plugin/rules frameworks, CQRS/event sourcing, microservices and speculative shared layers.

## Next active batch

`GF-008 / S5 — Allocation & Distribution`.

S5 must consume the **approved immutable S6 close snapshot** as its financial input. It must not recompute a live S1–S4 result and must keep allocation, distribution liability, and cash payment as separate facts.

Expected user-visible path:

`Approved Close Snapshot → Allocation Run → OWNER Approval → Partner Capital Update → Distribution Approval/Payable → Distribution Payment → Investor Statement`

Advanced waterfalls remain deferred. S5 v1 implements only the approved simple allocation policies in the finance baseline.

## Decision rules

- One canonical implementation per concept; extend before creating another.
- A shared abstraction requires two real consumers.
- Every batch completes one user workflow across schema, domain, application, UI, permissions, tests, telemetry/audit, and documentation.
- Money, ownership, allocation, payable and payment semantics must be exact, server-authoritative, tenant-safe and auditable.
- Approved/posted facts are immutable; correction is forward-versioned or linked reversal, never destructive editing.
- Every implementation branch starts from the exact latest `origin/greenfield/foundation`, is zero commits behind before delivery, and contains no unrelated legacy churn.
- No production deployment or production-data change without explicit authorization.
