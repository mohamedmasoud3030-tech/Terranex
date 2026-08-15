# ADR 0026 — GF-025 / R4 Procurement Foundation (Suppliers, Requests, Orders)

- **Status:** Accepted
- **Date:** 2026-08-15
- **Scope:** GF-025 only — the shared Procurement Foundation (roadmap R4, first gate): suppliers, purchase requests, purchase orders.
- **Depends on:** ADR 0001 (product-first), ADR 0002 (vertical slices), ADR 0025 (roadmap alignment R0–R17), S0 tenancy/RLS/audit baseline, S2 owner-check helpers.

## Context

The R0–R17 roadmap identifies **R4 — Procurement & Shared Operations** as the first genuinely missing independent gate. GF-019 explicitly deferred procurement/receiving/stock as farm-ERP scope; this slice starts filling that gap with a **sector-independent** shared foundation so Real Estate, Agriculture, and Livestock never reinvent suppliers and requisition-to-order workflow.

## Decision

1. **Scope (GF-025):** organization-scoped `procurement_suppliers` (shared across projects) plus project-scoped `purchase_requests`, `purchase_request_lines`, `purchase_orders`, and `purchase_order_lines`.
2. **No financial boundary crossed:** this slice stores **no** price, amount, currency, tax, invoice, payment, commitment, obligation, valuation, or inventory quantity. Quantities are `numeric(20,6)` compatible-unit operational truth only. Pricing/commitment, supplier invoicing/payment, and receiving/inventory consumption are later bounded procurement slices (GF-026+) that will link to the shared Finance Core (cost obligations / bank cash) exactly like the existing sector slices. No journal batch, journal line, obligation, or payment is created here.
3. **Lifecycle:** `DRAFT → SUBMITTED → APPROVED` (plus `REJECTED` for requests; `REJECTED`/`CANCELLED` for orders). Submission requires an active member; approval requires the organization **OWNER** and a **maker/checker** split (`approved_by <> requested_by`), enforced on the persisted row and by the RPC.
4. **Idempotency + audit:** every command is idempotent (advisory lock + `request_hash` payload fingerprint, `idempotency key payload mismatch` on re-use with a different payload) and writes a matching `audit_events` row.
5. **Immutability:** order/request headers can never be deleted (only status transitions through guarded RPCs); all line rows are fully append-only.
6. **RLS:** default-deny, forced RLS on all five tables, `is_active_member(organization_id)` select policy, direct authenticated writes denied; only `security_invoker` read views are exposed for the operator UI.
7. **Application/UI layer (delivered in this slice):** an Arabic/RTL Procurement workspace at `/projects/[projectId]/procurement` (registered as a shared `procurement` section across all three sector navigations), with Supplier, Purchase Request, and Purchase Order forms (client-side dynamic line editor writing JSON), server actions mapping to the audited RPCs, typed read models over the `security_invoker` views, and a UI verification suite.
8. **Not in GF-025:** receiving, pricing/commitment, invoicing, payment, stock/inventory consumption, approval-task engine, and supplier lifecycle beyond ACTIVE/INACTIVE — these are the next bounded steps of R4.

## Verification

- A SQL verification suite (`supabase/tests/75_gf025_procurement_foundation.sql`) covers tenant safety, idempotency + payload mismatch, request/order lifecycle, OWNER-only + maker/checker approval, append-only/no-delete guards, authenticated direct-write denial, and the supplier-linked read view.
- **Database gate: PASSED locally on a real PostgreSQL 17 server.** `scripts/db-test.sh` ran end-to-end (`EXIT=0`): GF-025/GF-026 migrations replay and the full SQL + concurrency + forward-upgrade suites pass with no regression. PostgreSQL-compatible fixes applied during this pass: expression-based inline `UNIQUE (... lower(trim(...)))` constraints were converted to equivalent `CREATE UNIQUE INDEX` statements (PostgreSQL rejects expressions inside inline table constraints), and mid-signature `DEFAULT NULL` parameters were removed (PostgreSQL requires trailing defaults) since the client always passes all arguments.

## Consequences

- R4 shared Procurement & Shared Operations is started with a clean, sector-independent foundation.
- The Procurement application layer (Arabic/RTL workspace), pricing/invoice/payment (Finance Core linkage), and receiving are the immediate next bounded steps.
