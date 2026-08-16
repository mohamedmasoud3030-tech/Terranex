# R4 — Procurement & Shared Operations Closeout Audit

**Status:** COMPLETE  
**Date:** 2026-08-16  
**Base SHA:** `4fe7364f980cd522593ca622ea782d5bc8765029`  
**PR #144 (Contracts & Evidence):** MERGED at base  

---

## 1. Scope of R4

R4 delivers Procurement & Shared Operations for Terranex:

- **GF-025 — Procurement Foundation:** suppliers, purchase requests, purchase orders with commercial terms, idempotent command flow.
- **GF-026 — Procurement Receiving:** goods receipt against purchase orders, quantity-only operational truth.
- **ADR 0030 — R4 Procurement Financial Integration:** supplier invoices with receipt matching, Finance Core payable posting (cost_obligation → authorization → journal), payment proposals with maker/checker/cash-capacity enforcement.
- **ADR 0031 — R4 Procurement Contracts & Evidence:** private versioned storage, immutable document metadata, typed links to PO/Receipt/Invoice, evidence approval gates.
- **Bounded shared inventory-value concepts** (the remaining R4 item, audited below).

---

## 2. Inventory-Value Concepts Audit

### 2.1 Existing Inventory/Quantity Tracking

| Area | Status | Mechanism |
|------|--------|-----------|
| **Agriculture harvest output** (GF-016) | COMPLETE | Append-only `harvest_inventory_movements` with `HARVEST_RECEIPT`, `TRANSFER`, `ADJUSTMENT_IN`, `ADJUSTMENT_OUT`, `SPOILAGE`, `SALE_ISSUE`. Derived balances per location. No valuation. |
| **Agriculture input lots** (GF-015) | COMPLETE (identity only) | Input lots are identity/traceability records only. Stock balance deliberately deferred per GF-015 boundary. |
| **Livestock quantity** (GF-020–GF-024) | COMPLETE | Event-sourced quantity ledger (`livestock_quantity_events`). `PURCHASE_IN`, `SALE_OUT`, births, mortality, splits, merges. Derived current quantity. |
| **Livestock purchases** (GF-024) | COMPLETE | Bounded external purchase intake: header + lines + `PURCHASE_IN` events. Optional agreed price (unposted commercial snapshot). |
| **Real Estate inventory** | NOT APPLICABLE | Real Estate tracks assets, not physical inventory. No inventory-value concepts needed. |

### 2.2 Missing Value/Cost Layers (Intentional Deferrals)

The following are **explicitly deferred** as business-policy-dependent and are NOT R4 gaps:

| Concept | Reason Deferred | Reference |
|---------|----------------|-----------|
| **COGS (Cost of Goods Sold)** | Requires valuation method policy (FIFO, weighted average, etc.) | GF-019: `cogs_status: 'NOT_GUESSED'` |
| **Harvest inventory valuation** | Requires company accounting policy | GF-019: `remaining_inventory_value_status: 'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'` |
| **Biological asset valuation (IAS 41)** | Requires company accounting policy; Terranex does not invent fair-value models | GF-024: `biological_asset_value_status: 'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'` |
| **Input stock balances** | Requires purchase/receiving workflow integration and stock valuation policy | GF-015/GF-016 explicit boundary |
| **WMS/Warehouse management** | Out of product scope for v1 | AGENTS.md |
| **Tax accounting** | Requires professional tax validation; Egypt-specific rules must be isolated | AGENTS.md |

### 2.3 Existing Cost Lineage (Not Inventory Value, But Operating Cost Traceability)

The Finance Core already provides complete cost traceability:

- **Procurement → Finance:** Supplier invoice approval creates `cost_obligation` → authorized → posted to journal as `PROJECT_EXPENSE`.
- **Agriculture cost attribution** (GF-019): `crop_cycle_cost_attributions` dimensions posted Finance journal lines to CropCycles.
- **Livestock cost attribution** (GF-024): `livestock_cohort_cost_attributions` dimensions posted Finance journal lines to Cohorts.
- **Crop cycle results** (GF-019): `crop_cycle_results_read` shows revenue, cost, cash, and operating result.
- **Livestock cohort results** (GF-024): `livestock_cohort_results_read` shows revenue, cost, cash, and operating result.

These are operating-expense attributions, not inventory valuations. They correctly flow through the shared Finance Core with no second ledger.

### 2.4 Verdict

**No additional shared inventory-value concepts need to be built for the currently authorized flows.**

The existing physical-quantity tracking (Agriculture harvest inventory, Livestock quantity events) is complete for operational purposes. All value/cost layers (COGS, biological assets, inventory valuation) are correctly identified as policy-dependent and displayed as `'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'` / `'NOT_GUESSED'` in read models.

---

## 3. R4 Functional Completeness Verification

| Capability | Status | Evidence |
|------------|--------|----------|
| Supplier identity & Party link | COMPLETE | `procurement_suppliers` with `party_id`, `link_supplier_party()` command, idempotent |
| Commercial Purchase Orders | COMPLETE | Exact money (minor_units), currency, commercial reference, immutable terms |
| PO Approval (maker/checker) | COMPLETE | `approve_purchase_order()` with SoD, evidence gate |
| Receiving | COMPLETE | `purchase_receipts`, `purchase_receipt_lines`, quantity-only, append-only |
| Supplier Invoices | COMPLETE | Receipt-matched, exact price match to PO, immutable |
| Invoice Approval + Payable Posting | COMPLETE | `approve_supplier_invoice()` creates `cost_obligation` → `authorize_cost_obligation` → shared Finance journal |
| Duplicate Invoice Protection | COMPLETE | Unique index on `(organization_id, supplier_id, lower(invoice_reference))` |
| Payment Proposals (maker/checker) | COMPLETE | `prepare_cost_payment()` → `approve_cost_payment()` with cash-capacity check |
| Payment Posting | COMPLETE | Creates `project_payment` + balanced journal (payable debit, bank cash credit) |
| Bank Reconciliation | COMPLETE | Existing shared Finance `reconciliation_matches` |
| Contracts & Evidence Storage | COMPLETE | Private `procurement-evidence` bucket, versioned metadata, typed links, SHA-256, approval gates |
| Evidence Integrity | COMPLETE | FK from version to `storage.objects`, append-only, RLS |
| Arabic/RTL UX | COMPLETE | `src/features/procurement/*` with Arabic labels |
| RLS / Default-Deny | COMPLETE | `is_active_member(organization_id)` on all R4 tables |
| Concurrency Protection | COMPLETE | `pg_advisory_xact_lock` on idempotency keys, `FOR UPDATE` row locks |
| Financial Invariants | COMPLETE | Exact money checks, Σ debit = Σ credit (via Finance Core), receipt ceiling, price matching |

---

## 4. Financial Invariants Proven (R4 Scope)

1. **Debit = Credit**: All posted batches through Finance Core journal enforce balanced posting.
2. **Tenant coherence**: Every R4 table has `organization_id` with FK to organizations; RLS enforces.
3. **Project coherence**: Composite FKs `(project_id, organization_id)` on all procurement tables.
4. **Unique supplier invoice identity**: `(organization_id, supplier_id, lower(invoice_reference))` unique index.
5. **Exact money**: All monetary values stored as `bigint` minor_units.
6. **Receipt ceiling**: Invoice quantity cannot exceed received quantity (enforced in `approve_supplier_invoice()`).
7. **Price matching**: Invoice unit price must exactly match PO unit price (composite FK).
8. **Payment/payable ceiling**: Payment proposal + posted payments cannot exceed obligation amount.
9. **Immutable posted facts**: Append-only triggers on supplier_invoices, invoice_lines, payment_proposals.
10. **Locked-period protection**: Payment approval checks open accounting period.
11. **Idempotent replay**: Advisory lock + request_hash on all commands.
12. **Valid lifecycle transitions**: State machine guards on PO, invoice, payment proposal.
13. **RLS/default-deny**: `FORCE ROW LEVEL SECURITY` + `revoke all` from anon/public.
14. **Currency/scale correctness**: Currency constraint `~ '^[A-Z]{3}$'`, exact minor units check.
15. **No concurrency overshoot**: `FOR UPDATE` locks on PO (invoice approval), obligation (payment), cash account.

---

## 5. R4 Closeout Conclusion

**R4 — Procurement & Shared Operations is COMPLETE.**

All authorized capabilities are implemented, tested, and integrated with the shared Finance Core:
- Procure-to-Pay with commercial terms, exact money, maker/checker
- Receiving with quantity-only operational truth
- Supplier invoices with receipt matching and Finance Core payable posting
- Payment proposals with cash-capacity enforcement
- Private versioned contracts/evidence with integrity gates
- Duplicate protection, immutability, idempotency, concurrency, RLS

The bounded shared inventory-value concepts were audited and determined to be:
- **Physical quantity tracking**: Complete (Agriculture harvest inventory, Livestock quantity events)
- **Value/cost layers**: Correctly deferred as business-policy-dependent
- **No additional build required** for the currently authorized flows

---

*Audit performed 2026-08-16 against `main@4fe7364f980cd522593ca622ea782d5bc8765029`*