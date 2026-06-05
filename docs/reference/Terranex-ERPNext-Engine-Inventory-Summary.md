# Terranex — ERPNext Engine Extraction Inventory Summary

## Decision

Use ERPNext only as a behavioral reference. Rebuild useful rules as Terranex-native TypeScript modules. Do not copy ERPNext Python into `src/`, do not add Frappe, and do not turn Terranex into an ERPNext fork.

Prepare the local reading cache with:

```bash
node tools/fetch-erpnext-reference.mjs
```

The fetcher downloads only the curated files listed in `reference/erpnext/selected-paths.txt`, pins them to one upstream commit, validates SHA-256 hashes, and stores them under ignored `.reference-cache/erpnext/`.

## Engine portfolio

| Order | Terranex-native engine | ERPNext reference areas | Decision |
|---:|---|---|---|
| 1 | Document proof and local file packages | attachment behavior as reference only | Build first with IndexedDB and ZIP backup |
| 2 | Obligations, settlements, allocations, aging | payment entry, payment reconciliation, receivables report | Extend existing settlement foundation |
| 3 | Shared masters and configuration | accounting period, bank account, item, budget | Build deliberate Terranex-sized masters |
| 4 | Internal posting and ledger projection | general ledger, journal entry, accounts controller | Rebuild natively; no full ERP UI yet |
| 5 | Reports, exports, and bilingual print | ERPNext reports as behavior checklists | Build after financial contracts stabilize |
| 6 | Inventory, stock ledger, and valuation | stock ledger, valuation, item, stock entry, reconciliation | Rebuild selected subset only |
| 7 | Procurement | purchase order, purchase receipt, purchase invoice | Rebuild procure-to-pay flow |
| 8 | Sales and collections | sales order, delivery note, sales invoice, payment schedule | Rebuild order-to-collection flow |
| 9 | Asset lifecycle | asset, movement, value adjustment, maintenance, repair | Deepen existing assets module |
| 10 | Projects, tasks, budgets, approvals | project, task, budget, accounting period | Deepen existing project workflows |
| 11 | Contracts, recurring schedules, renewals | payment schedule, subscription | Read selectively and rebuild minimal contract scheduler |
| 12 | Maintenance, inspection, quality | maintenance schedule, quality inspection | Rebuild selected subset |
| 13 | Bank and cash reconciliation | bank account, bank transaction, payment reconciliation | Reserve architecture seam and implement later |
| 14 | Generic operational-event bridge | work-order patterns plus Terranex sector model | Build Terranex-native bridge |
| 15 | Staged imports and integrity repair | validation patterns only | Add after core workflows stabilize |

## Cross-sector truth model

```text
Project
  -> Asset
  -> Party / Partner
  -> Document
  -> Transaction
  -> Obligation
  -> Settlement
  -> Profitability
  -> Report
```

Operational events extend this chain:

```text
Operational Event
  -> Project
  -> Asset
  -> Location
  -> Quantity and unit
  -> Responsible party
  -> Supporting document
  -> Stock effect when applicable
  -> Financial effect when applicable
```

## Important discovered requirements

The ERPNext review exposed requirements that should be reserved even when not implemented immediately:

1. Settlement allocation: one payment can settle multiple obligations and one obligation can receive multiple payments.
2. Controlled reversal: posted financial changes must be reversed, not silently edited.
3. Period locks: historical reporting needs close and reopen control.
4. Inventory valuation decision: FIFO or weighted average must be explicit.
5. Batch, expiry, and reorder controls for agricultural inputs, feed, and medication.
6. Landed-cost allocation for transport, handling, and storage.
7. Bank and cash reconciliation.
8. Quality inspection and non-conformance.
9. Staged imports with preview and per-row validation.
10. Tax and jurisdiction extension seams without premature regional implementation.

## Selective or excluded areas

| ERPNext area | Treatment |
|---|---|
| Manufacturing | Read work-order patterns only; do not port full BOM or shop-floor logic now |
| Subcontracting | Defer; model contractors through projects, contracts, procurement, and approvals |
| CRM | Read selectively for notes and contract patterns |
| Support | Read selectively for service-request patterns |
| Regional modules | Defer until jurisdiction requirements are explicit |
| EDI, telephony, shopping cart, portal, POS, loyalty, promotions | Exclude unless a concrete Terranex use case appears |

## Required extraction sequence

1. Stage 0: inspect latest `main` and create a Terranex-native implementation plan only.
2. Stage 1: document binaries in IndexedDB, safe linkage, preview, download, delete, ZIP backup, restore validation.
3. Stage 2: settlement allocation, reversals, aging, statements, and cash controls.
4. Stage 3: shared masters and internal posting contract.
5. Stage 4: reports, exports, and bilingual print infrastructure.
6. Stage 5: inventory and procurement foundation.
7. Stage 6: asset, project, contract, maintenance, and budget depth.
8. Stage 7: operational-event bridge.
9. Stage 8: real estate, agriculture, and livestock workflow composition.
10. Stage 9: reconciliation, staged imports, quality, and integrity tooling.
11. Final stage: Supabase migration only after local workflows stabilize.

## Acceptance criteria for every rebuilt engine

A rebuilt engine is acceptable only when:

1. it has a narrow Terranex domain contract;
2. it has no Frappe or ERPNext runtime dependency;
3. it preserves local-first behavior;
4. it does not add Supabase before the final migration stage;
5. any stored-data changes use conservative idempotent migrations;
6. business-rule tests are added;
7. linked records cannot be silently deleted;
8. reversals preserve history;
9. document traceability is maintained;
10. lint, typecheck, tests, build, and final diff review pass;
11. the PR contains no unrelated refactors or duplicate helpers.

## Immediate next action

Codex must complete Stage 0 planning first. It must not start runtime implementation until the plan is reviewed and the first narrow branch is selected.
