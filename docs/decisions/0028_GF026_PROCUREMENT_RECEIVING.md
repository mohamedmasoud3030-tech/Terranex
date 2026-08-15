# ADR 0028 — GF-026 / R4 Procurement Receiving (Receipt against APPROVED Purchase Order)

- **Status:** Accepted
- **Date:** 2026-08-15
- **Scope:** GF-026 only — the physical receiving step of R4 Procurement & Shared Operations.
- **Depends on:** ADR 0026 (roadmap alignment R0–R17), ADR 0027 (GF-025 procurement foundation), GF-025 migration/RPCs.
- **Reconciled lineage note:** authored on the pre-R1 parallel branch as `0027_GF026_PROCUREMENT_RECEIVING.md` and `20260815040000_gf026_procurement_receiving.sql`. Renumbered to ADR `0028` and migration `20260815032000_gf026_procurement_receiving.sql` in the no-loss reconciliation so the merged R1 migration keeps its canonical `20260815030000` slot. Content and verification evidence are preserved; numbering/references are reconciled. Two reconciliation fixes are included in this slice: (1) `GRANT SELECT` on the receiving security_invoker read views to `authenticated` was added (same defect class as GF-025); (2) the over-receipt pre-check now locks each order line `FOR UPDATE`, closing the concurrent-receipt window described in decision 4.

## Context

GF-025 delivered suppliers + purchase requests/orders (quantity-only). The next coherent bounded step in R4 is **receiving**: recording the physical receipt of quantities against an already-approved purchase order. This keeps the "record what happened" operational truth separate from any later pricing/valuation and stays quantity-only, consistent with the Agriculture/Livestock handling of physical inventory (no fabricated value, no availability balance).

## Decision

1. **Scope (GF-026):** `purchase_receipts` (header) + `purchase_receipt_lines` (per order line), project-scoped, tied to a Purchase Order.
2. **Control gate:** receiving is allowed only when the Purchase Order is `APPROVED` (enforced in the RPC and by a `BEFORE INSERT` trigger). Draft/rejected orders cannot receive.
3. **Over-receipt guard:** the cumulative received quantity per order line can never exceed the ordered quantity — enforced in the RPC and by a `BEFORE INSERT` trigger (sum of all receipt lines for that order line, including the current insert).
4. **Concurrency hardening (reconciliation addition):** the RPC pre-check reads each order line `FOR UPDATE`, serializing concurrent receipts per order line. With the row lock, a concurrent second receipt waits for the first to commit and then observes its committed quantities, so the over-receipt invariant also holds under concurrent receipt creation (the trigger alone is snapshot-based and cannot see an uncommitted competing receipt). The RPC signature and parallel-array transport are unchanged; only the lock scope was added.
5. **Server-derived unit:** the receipt line unit is taken from the order line; the browser never asserts it (mirrors the harvest-quantity-unit pattern).
6. **No financial/inventory boundary crossed:** no price, amount, currency, tax, invoice, payment, commitment, obligation, valuation; no journal batch/line; no inventory balance table, stock valuation, or availability validation. Receipts are physical quantity records only.
7. **Idempotency + audit:** the `create_purchase_receipt` RPC is idempotent (advisory lock + `request_hash` payload fingerprint) and writes one `audit_events` row.
8. **Append-only:** receipts and their lines can never be updated or deleted.
9. **RLS:** default-deny, forced RLS, `is_active_member(organization_id)` select policy, direct authenticated writes denied; only `security_invoker` read views exposed (receipts, receipt lines, per-order-line receiving status with derived ordered/received/remaining).
10. **UI:** the Arabic/RTL Procurement workspace adds a receiving section and a per-approved-order `ReceiptForm` (fixed line rows with received-quantity inputs writing JSON), plus derived ordered/received/remaining columns on the order-lines table.
11. **Not in GF-026:** pricing/commitment, supplier invoicing/payment (Finance Core linkage), inventory balance/valuation/availability, and receiving of non-purchase-order quantities.

## Verification

- SQL verification suite `supabase/tests/79_gf026_procurement_receiving.sql`: APPROVED-only gate, over-receipt rejection (including across receipts), server-derived unit, idempotency + payload mismatch, append-only, and two-tenant isolation.
- **Command input shape:** `create_purchase_receipt` takes **parallel arrays** (`p_purchase_order_line_ids uuid[]`, `p_quantities numeric[]`) rather than a single JSON payload. This mirrors the GF-018 parallel-array pattern and avoids the PostgreSQL `psql` quoting hazard of embedding a UUID inside a JSON literal through `format('%L')`/stdin variable substitution, which silently corrupts the generated SQL. The client (`ReceiptForm` → `createPurchaseReceipt` action) still collects lines and sends the two parallel arrays.
- Application verification: extended `tests/procurement-foundation.test.tsx` (receiving schema + `ReceiptForm` render). Typecheck, lint, build, and all app tests pass locally.
- **Database gate: PASSED locally on a real PostgreSQL 17 server.** `scripts/db-test.sh` was run end-to-end (`EXIT=0`): all ordered migrations (including the renumbered GF-025/GF-026) replay, the full SQL verification suite passes, and every concurrency and forward-upgrade shell suite (S1–S7 and GF-016 through GF-024) still passes, proving no regression from the Procurement slices.
- Two pre-existing suites were updated only because GF-025 legitimately adds `purchase_orders`: `44_gf015_input_application.sql` and `47_gf016_harvest_inventory.sql` asserted that `purchase_orders` must not exist (correct when written, before any procurement slice). `purchase_orders` is removed from those "must not exist" lists with an explanatory note; all other still-undeferred tables remain asserted. The architectural intent — a sector slice must not scaffold its own procurement core — is preserved: the shared Procurement slice exists exactly once, and a reconciliation coexistence suite asserts that no sector-specific duplicate procurement tables exist.

## Consequences

- R4 now covers Suppliers → Purchase Requests → Purchase Orders → Receiving end-to-end (quantity-only operational truth).
- The next bounded step of R4 is the Finance Core linkage (pricing/commitment and supplier invoicing/payment), which will attach exact money to the approved/received procurement facts.
