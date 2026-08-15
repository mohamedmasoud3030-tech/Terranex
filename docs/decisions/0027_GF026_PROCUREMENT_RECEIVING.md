# ADR 0027 — GF-026 / R4 Procurement Receiving (Receipt against APPROVED Purchase Order)

- **Status:** Accepted
- **Date:** 2026-08-15
- **Scope:** GF-026 only — the physical receiving step of R4 Procurement & Shared Operations.
- **Depends on:** ADR 0025 (roadmap alignment R0–R17), ADR 0026 (GF-025 procurement foundation), GF-025 migration/RPCs.

## Context

GF-025 delivered suppliers + purchase requests/orders (quantity-only). The next coherent bounded step in R4 is **receiving**: recording the physical receipt of quantities against an already-approved purchase order. This keeps the "record what happened" operational truth separate from any later pricing/valuation and stays quantity-only, consistent with the Agriculture/Livestock handling of physical inventory (no fabricated value, no availability balance).

## Decision

1. **Scope (GF-026):** `purchase_receipts` (header) + `purchase_receipt_lines` (per order line), project-scoped, tied to a Purchase Order.
2. **Control gate:** receiving is allowed only when the Purchase Order is `APPROVED` (enforced in the RPC and by a `BEFORE INSERT` trigger). Draft/rejected orders cannot receive.
3. **Over-receipt guard:** the cumulative received quantity per order line can never exceed the ordered quantity — enforced in the RPC and by a `BEFORE INSERT` trigger (sum of all receipt lines for that order line, including the current insert).
4. **Server-derived unit:** the receipt line unit is taken from the order line; the browser never asserts it (mirrors the harvest-quantity-unit pattern).
5. **No financial/inventory boundary crossed:** no price, amount, currency, tax, invoice, payment, commitment, obligation, valuation; no journal batch/line; no inventory balance table, stock valuation, or availability validation. Receipts are physical quantity records only.
6. **Idempotency + audit:** the `create_purchase_receipt` RPC is idempotent (advisory lock + `request_hash` payload fingerprint) and writes one `audit_events` row.
7. **Append-only:** receipts and their lines can never be updated or deleted.
8. **RLS:** default-deny, forced RLS, `is_active_member(organization_id)` select policy, direct authenticated writes denied; only `security_invoker` read views exposed (receipts, receipt lines, per-order-line receiving status with derived ordered/received/remaining).
9. **UI:** the Arabic/RTL Procurement workspace adds a receiving section and a per-approved-order `ReceiptForm` (fixed line rows with received-quantity inputs writing JSON), plus derived ordered/received/remaining columns on the order-lines table.
10. **Not in GF-026:** pricing/commitment, supplier invoicing/payment (Finance Core linkage), inventory balance/valuation/availability, and receiving of non-purchase-order quantities.

## Verification

- SQL verification suite `supabase/tests/76_gf026_procurement_receiving.sql`: APPROVED-only gate, over-receipt rejection (including across receipts), server-derived unit, idempotency + payload mismatch, append-only, and two-tenant isolation.
- Application verification: extended `tests/procurement-foundation.test.tsx` (receiving schema + `ReceiptForm` render). Typecheck, lint, and build pass locally.
- The local database gate remains **unresolved** in the agent sandbox (neither `psql` nor Docker available) and must be run by the canonical GitHub Actions PostgreSQL 16 CI job before the PR is called ready.

## Consequences

- R4 now covers Suppliers → Purchase Requests → Purchase Orders → Receiving end-to-end (quantity-only operational truth).
- The next bounded step of R4 is the Finance Core linkage (pricing/commitment and supplier invoicing/payment), which will attach exact money to the approved/received procurement facts.
