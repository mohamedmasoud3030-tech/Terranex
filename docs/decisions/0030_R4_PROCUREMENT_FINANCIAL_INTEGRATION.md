# ADR 0030 — R4 Procurement Financial Integration

- **Status:** Accepted
- **Date:** 2026-08-15
- **Scope:** R4 financial procure-to-pay spine: commercial Purchase Order → commitment → supplier invoice → Finance Core payable → shared payment → shared bank reconciliation.
- **Depends on:** ADR 0027 (Procurement Foundation), ADR 0028 (Receiving), ADR 0004/S2 (Cost & Cash), ADR 0007/S6 (period close/correction), ADR 0025 (Project/Portfolio authority).

## Context

GF-025/GF-026 established one shared, sector-independent Procurement core but intentionally stopped at quantity-only Purchase Orders and Receiving. Finance Core already owns `cost_obligations`, immutable balanced postings, `project_payments`, project cash accounts, bank statement lines, reconciliation matches, period locks, audit, idempotency, concurrency controls, and reversal. R4 must connect commercial provenance to those facts without creating a Procurement ledger, payable table, payment engine, or bank-matching implementation.

## Decision

### Commercial Purchase Order

A new Purchase Order carries a financially linked active Supplier, Project currency, commercial/evidence reference, expected delivery date where known, and line quantity plus integer-minor-unit unit price. PostgreSQL derives line and order commercial totals. The database rejects any quantity × unit-price result that would require an unapproved rounding policy. Existing pre-R4 quantity-only rows remain historical operational facts; all new order commands require the commercial contract.

A Supplier remains the organization-scoped Procurement profile, but it now maps one-to-one to the existing organization Party used by Finance Core. Existing profiles can be linked once by an OWNER-gated, audited, idempotent command. This does not create a second counterparty registry.

### PO → commitment semantics

An APPROVED commercial PO is the authoritative **unposted purchase commitment**. It is exposed through `project_procurement_commitments_read`; it does not create journal lines, expense, payable, invoice, or cash movement. This avoids duplicating the PO amount in a mutable commitment ledger and preserves the distinctions:

`ORDERED ≠ RECEIVED ≠ INVOICED ≠ PAYABLE ≠ PAID ≠ RECONCILED`.

Receiving remains the existing append-only quantity fact and has no automatic accounting or inventory-valuation effect.

### Supplier invoice and matching

This slice accepts PO-backed supplier invoices. Each immutable invoice line identifies one authoritative receipt line, its invoiced quantity, and the supplier's unit price. The unit price must exactly equal the PO price; approved invoice quantity cannot exceed received quantity. There is no guessed percentage tolerance. Multiple receipts, partial invoices, multiple invoices per PO, and partial quantities are supported. Supplier invoice reference is unique per organization and Supplier. Submission and approval commands are request-fingerprinted and retry-safe with NULL-safe comparison.

Invoice approval is OWNER-only with maker/checker (`approved_by ≠ recorded_by`). A PO row lock serializes competing invoice approvals and rechecks the receipt ceiling, so two invoices cannot consume the same remaining receipt quantity.

### Payable, payment and reconciliation

Approving a matched supplier invoice creates and authorizes the existing Finance Core `cost_obligation`, preserving Project, Party, amount, currency, invoice date, cost treatment, invoice source, and maker/checker provenance. The normal Finance Core authorization creates the immutable balanced expense/WIP-to-supplier-payable posting and is subject to the existing period lock. The invoice stores structural links to that obligation and authorization batch; it does not store an independent payable balance.

Supplier payment now follows the canonical shared Finance boundary: an active member prepares an immutable `cost_payment_proposal`, and a different OWNER approves it and atomically creates the existing immutable `project_payment` plus balanced journal posting. The historical direct-post `pay_cost_obligation` signature is revoked from API roles and fails closed, so an authenticated caller cannot bypass payment maker/checker. The proposal is a shared Finance workflow fact, not a Procurement ledger or a second posted-payment fact.

Preparation validates the authorized active obligation, Project/currency/account coherence, open period, payable ceiling, and current available book cash. Approval revalidates all of them. Approval locks the cash-account row before the obligation row, recomputes active BANK_CASH balance under that lock, and therefore serializes different obligations competing for the same account. It rejects payment above current book cash because no overdraft or credit-facility policy exists in this model. Partial payment, immutable posting, reversal behavior, `payment_status_read`, bank statement imports, `reconcile_payment`, and `reconciliation_matches` remain owned by Finance Core. Procurement read models only derive unpaid/part-paid/paid and unreconciled/part-reconciled/reconciled states from those shared facts.

### Project, tenant, security and correction authority

Every invoice, invoice line, obligation link, receipt basis and payment path remains organization- and Project-coherent through composite foreign keys and Finance Core scope guards. A Project A PO cannot produce a Project B invoice/payable/payment. Portfolio membership is not stored in Procurement or Finance facts and moving the Project does not rewrite them.

New tables use forced default-deny RLS, active-member read policies and no browser DML. Material commands are `SECURITY DEFINER` with `search_path=pg_catalog,public`, explicit membership/OWNER checks, explicit grants, exact-money transport, same-transaction audit and canonical idempotency.

Supplier invoices and lines are append-only. Posted payable/payment facts are never edited or deleted; existing Finance Core reversal order remains mandatory (void reconciliation → reverse payment → reverse obligation). A reversal does not erase the source invoice or restore procurement quantity as though the invoice never existed.

## Explicit exclusions

- tax, VAT, withholding, discounts, FX and Egyptian e-invoice automation;
- non-PO invoices and configurable matching tolerance;
- inventory valuation, COGS or WMS;
- RFQ/tender, vendor portal or contract-management suite;
- Portfolio-level postings, cross-project netting or pooled cash;
- investor ownership, entitlement, operator economics or distributions;
- a second Procurement/Finance ledger, payable, payment, cash or reconciliation engine.

R4 remains open for contracts/attachments and shared inventory-value concepts. This decision delivers the bounded financial procure-to-pay spine only. BD-001 through BD-012 remain OPEN and are unaffected.
