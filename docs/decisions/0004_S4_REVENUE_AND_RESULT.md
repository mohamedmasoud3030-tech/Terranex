# GF-006 / S4 — Revenue & Realized Result

**Status:** IMPLEMENTED  
**Slice:** GF-006 / S4  
**Base:** `67e8f12` (S0+S1 merged baseline; S2+S3 built as prerequisites)

## Delivered

1. **Cost & Cash (S2 prerequisite):** Balanced double-entry project subledger with
   journal batches/lines, obligations, payments, bank statements, and reconciliation.
   All postings are database-enforced balanced (debits = credits per batch).

2. **Real Estate Sector (S3 prerequisite):** Property assets with lifecycle,
   parcels, capitalizable cost items forming the authoritative carrying amount,
   and management valuations separated from realized financial facts.

3. **Disposition lifecycle:** DRAFT → APPROVED → CONTROL_TRANSFERRED → SETTLED,
   with explicit separation between agreement, approval, control transfer, and
   cash collection.

4. **Revenue recognition:** Atomic, idempotent command that creates:
   - Dr receivable / Cr property sale revenue (on control transfer)
   - Dr cost of sale / Cr development WIP (carrying cost derecognition)
   - Carrying cost derived from authoritative posted facts, not user input
   - Fails clearly when carrying cost cannot be computed

5. **Collection lifecycle:** Independent from revenue, supporting full and partial
   collection with ceiling enforcement (Dr cash / Cr receivable), concurrency
   safety via receivable row locking.

6. **Realized result report:** Authoritative read model derived from posted
   journal lines showing recognized revenue, derecognized carrying cost,
   selling costs, realized result, collected cash, outstanding receivable.
   Management valuation shown separately — never mixed with realized profit.

7. **Project lifecycle integration:** EXITING state entered on sale recognition.

## Decisions

- **Whole-property disposition only in S4.** Partial-property disposition is
  deferred because cost allocation to partial scopes would require allocation
  rules not available in MVP. This is recorded as an explicit MVP decision.

- **Carrying amount from authoritative facts.** The carrying cost derecognized
  at sale comes from `property_carrying_amount` (acquisition + capitalizable
  costs), not from a number entered in the sale screen. If the data is missing,
  the command fails explicitly rather than using an estimate.

- **Revenue ≠ cash.** Revenue is recognized at control transfer via receivable,
  not when cash arrives. Collection is a separate cash posting that reduces the
  receivable but does not affect revenue.

- **Valuation ≠ realized result.** Management valuations are stored separately
  and shown in their own section. The realized result report never includes
  valuation movements.

- **No IFRS engine.** Posting rules follow the finance contract for an MVP
  real estate disposal. IAS 2/16/40 classification, IFRS 15 recognition, and
  tax treatments are deferred to qualified accountant review.

## Deferred

- Partial-property disposition with cost allocation
- Sale reversal/correction lifecycle
- Period close and locked-period posting
- Allocation to investors (S5)
- Distribution approval and payment (S5)
- External GL export
- Tax withholding calculation
- IFRS/GAAP classification engine
- Payment gateway / bank API
- FX engine for multi-currency sales
