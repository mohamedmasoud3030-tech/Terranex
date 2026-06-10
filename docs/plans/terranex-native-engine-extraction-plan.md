# Terranex-Native Engine Extraction Plan

**Stage:** 0 — inspect and plan only  
**Baseline:** `main` at `c33313c946a249840767f2ba2b9d5bfd0a951a42`  
**Scope:** documentation only; no runtime, storage-schema, Supabase, or ERPNext dependency changes  
**Roadmap authority:** `docs/reference/Terranex-Product-Growth-Roadmap.md`  
**Architecture authority:** `docs/reference/Terranex-Architecture-English.md`

## 1. Purpose and boundaries

This plan maps the current Terranex implementation against the approved ERPNext-reading program and defines the smallest safe Terranex-native increments.

ERPNext is used only as a behavioral reference. Terranex remains an independent local-first React and TypeScript application. This plan does not copy ERPNext code, add Frappe, add Supabase, modify runtime files, or change stored shapes.

The target truth chain remains:

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

Operational effects extend the same chain rather than creating disconnected sector systems:

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

## 2. Inspection record

### Required repository sources reviewed

- `AGENTS.md`
- `IMPLEMENTATION_GUIDE.md`
- `docs/ai/README.md`
- `docs/ai/data-safety.md`
- `docs/ai/release-policy.md`
- `docs/decisions/README.md`
- `.ai/workflows/README.md`
- `docs/reference/Terranex-Product-Growth-Roadmap.md`
- `docs/reference/Terranex-Architecture-English.md`
- `docs/reference/Terranex-Product-Growth-Roadmap-Zoom-In.md`
- `docs/reference/Terranex-ERPNext-Engine-Inventory-Summary.md`
- `docs/prompts/codex-terranex-engine-extraction-stage-0.md`
- `reference/erpnext/README.md`
- `reference/erpnext/selected-paths.txt`
- `reference/erpnext/expected-sha256.txt`
- `tools/fetch-erpnext-reference.mjs`

### Runtime and test surfaces inspected

- `src/core/storage/localStorageStore.ts`
- `src/core/storage/migrations.ts`
- `src/core/storage/backup.ts`
- `src/core/storage/archiveBackup.ts`
- `src/core/storage/indexedDbFileStore.ts`
- `src/core/lib/profitability.ts`
- `src/core/lib/deletionGuards.ts`
- `src/features/documents/storage.ts`
- `src/features/transactions/storage.ts`
- `src/features/obligations/storage.ts`
- `src/features/settlements/types.ts`
- `src/features/settlements/storage.ts`
- `src/features/settlements/migration.ts`
- `src/features/settlements/posting.ts`
- `src/features/events/storage.ts`
- `tests/settlement-workflow.test.cjs`
- route inventory discovered under `src/routes/`

### Open pull request isolation

Open PR `#32` (`chore: remove obsolete timeline and test config`) is an unrelated cleanup slice. It must remain separate and must not be modified or merged as part of this extraction program.

### Environment constraint during Stage 0

The execution environment could inspect the immutable repository baseline through the GitHub connector but could not clone the public repository or run `node tools/fetch-erpnext-reference.mjs` because outbound DNS resolution to GitHub was unavailable. The pinned contract was still reviewed from:

- `reference/erpnext/selected-paths.txt`;
- `reference/erpnext/expected-sha256.txt`;
- `tools/fetch-erpnext-reference.mjs`;
- selected pinned ERPNext files relevant to settlement allocation.

A normal developer environment should run the fetcher before coding the related engine stage. `.reference-cache/` is ignored and must stay uncommitted.

## 3. Current repository inventory from actual code

### 3.1 Persistence and recovery

| Surface | Current role | Status |
|---|---|---|
| `src/core/storage/localStorageStore.ts` | Typed localStorage store factory with parse fallback, subscriptions, reset, and versioned-migration helper | Existing and reusable |
| `src/core/storage/migrations.ts` | Conservative legacy financial-record migration with audit preservation for unmappable records | Existing and sensitive |
| `src/core/storage/backup.ts` | Export, parse, restore, rollback, and clear for all `terranex.*` localStorage keys | Existing and reusable |
| `src/core/storage/indexedDbFileStore.ts` | IndexedDB binary storage for document files with metadata validation and optional SHA-256 | Existing and reusable |
| `src/core/storage/archiveBackup.ts` | ZIP package containing records and binaries, manifest validation, link validation, restore rollback, and clear rollback | Existing and reusable |

### 3.2 Financial and traceability kernels

| Surface | Current role | Status |
|---|---|---|
| `src/features/documents/storage.ts` | Project-required document metadata; validates local-file metadata and protects linked records | Existing |
| `src/features/transactions/storage.ts` | Validates project, partner, and supporting-document references; normalizes FX to EGP; binds and releases document links atomically | Existing |
| `src/features/obligations/storage.ts` | Receivable or payable records, remaining-balance status derivation, settlement-total synchronization, deletion protection | Existing |
| `src/features/settlements/types.ts` | Explicit posted cash-movement record with payment method, receipt, active or reversed status, and migration origin | Existing foundation |
| `src/features/settlements/storage.ts` | Settlement validation, persistence, active totals, rollback helpers, reversal history | Existing foundation |
| `src/features/settlements/posting.ts` | One-obligation settlement posting, receipt validation, over-settlement guard, atomic rollback, reversal synchronization | Existing foundation; not yet allocation-capable |
| `src/core/lib/profitability.ts` | Derived project, sector, and global profitability plus separate cash exposure from open obligations | Existing |
| `src/core/lib/deletionGuards.ts` | Cross-store protection for linked projects, partners, assets, documents, transactions, settlements, events, and stock adjustments | Existing |

### 3.3 Operational kernels

| Surface | Current role | Status |
|---|---|---|
| `src/features/events/storage.ts` | Basic operational-event and stock-adjustment persistence by asset and project | Skeleton only |
| assets, projects, partners stores and hooks | Core masters and project relationships | Existing baseline |
| sector routes | Real-estate, agriculture, and livestock entry surfaces | Existing baseline; deep workflows deferred |

### 3.4 Active route inventory

The current route set includes:

```text
/
/dashboard
/projects
/projects/:id
/assets
/partners
/partners/:id
/documents
/transactions
/finance
/finance/profitability
/finance/obligations
/settings
/real-estate
/agriculture
/livestock
/404
```

### 3.5 Existing business-rule tests observed

The current test suite includes targeted coverage for:

- transaction reference integrity and cross-project rejection;
- FX normalization;
- document binding and release behavior;
- IndexedDB file handling and archive backup behavior;
- profitability and cash-exposure separation;
- settlement posting, partial settlement, full settlement, reversal, receipt validation, legacy-balance migration, and deletion protection.

## 4. Existing capability matrix

| Capability | Current state | Evidence-based conclusion | Action |
|---|---|---|---|
| Local-first persistence | Implemented | Typed localStorage stores and conservative migrations are active | Preserve |
| Document proof metadata | Implemented | Documents require project linkage and validate file metadata | Preserve |
| IndexedDB document binaries | Implemented | Local binary store validates file records and stores Blob payloads | Preserve |
| ZIP backup and restore | Implemented | Archive includes records and binaries, validates links, and rolls back failed restore | Preserve |
| Transaction traceability | Implemented | New transactions validate references and bind supporting documents | Preserve |
| Profitability calculation | Implemented | Profit derives from transactions; cash exposure derives separately from obligations | Preserve |
| Explicit obligations | Implemented | Receivables and payables exist as first-class records | Preserve and deepen |
| Explicit settlements | Implemented foundation | Cash movement is stored independently, reversals preserve history | Extend |
| Multi-obligation allocation | Missing | Current settlement contract contains one `obligation_id` only | Build next |
| Aging and party statements | Missing | Roadmap-required reports are not yet provided as query contracts | Build after allocation |
| Cash or bank account control | Missing | Payment method exists but no deliberate account master is present | Add after allocation |
| Internal posting contract | Missing | Financial stores exist but no stable projection contract for later ledger views | Add after Phase 2 stabilization |
| Report query layer | Missing | Current profitability calculations are reusable but reporting infrastructure is not yet a standalone contract layer | Build later |
| Inventory ledger and valuation | Missing | Stock adjustment storage exists, but no item, location, quantity-ledger, valuation, batch, expiry, or reorder engine | Build later |
| Procurement | Missing | No procure-to-pay chain yet | Build later |
| Sales and collections | Missing | No order-to-collection chain yet | Build later |
| Asset lifecycle | Partial | Asset records exist; movement, maintenance, repair, disposal controls, and valuation history need deepening | Build later |
| Project tasks, budgets, approvals | Partial | Core project records exist; milestones, tasks, budgets, approvals, and locks are missing | Build later |
| Contract scheduler | Missing | Recurrence, renewal, and reminders are not yet implemented | Build later |
| Maintenance and quality | Missing | Operational skeleton exists without inspection and corrective-action workflow | Build later |
| Operational-event bridge | Skeleton | Events and stock adjustments exist but are not yet a governed financial and stock bridge | Build later |
| Staged imports | Missing | No preview, row validation, or repair workflow yet | Build later |
| Supabase platform | Intentionally deferred | Roadmap explicitly postpones backend migration until local workflows stabilize | Do not add now |

## 5. Missing engine matrix and Terranex-native landing boundaries

| Order | Engine portfolio item | Current gap | Terranex-native landing boundary | First relevant ERPNext reading |
|---:|---|---|---|---|
| 1 | Document proof and local file packages | No known open Stage 1 gap after code review | Keep `documents`, IndexedDB, archive, and deletion surfaces stable; fix only proven regressions | Attachment behavior only when a defect appears |
| 2 | Obligations, settlements, allocations, aging | One payment cannot allocate across multiple obligations; no aging or party statement query layer | Add explicit settlement-allocation records and derive balances from active allocations | `payment_entry_reference`, `payment_reconciliation`, receivables report |
| 3 | Shared masters and configuration | Payment methods are typed constants; no deliberate masters for cash or bank accounts, units, locations, categories, or configurable currencies | Add small typed masters behind local stores; avoid full ERP configuration surface | accounting period, bank account, item, budget |
| 4 | Internal posting and ledger projection | No stable internal projection seam for ledger-style reporting | Add a read-model projection contract after allocation rules stabilize; do not expose a full ERP accounting UI | general ledger, journal entry, accounts controller |
| 5 | Reports, exports, and bilingual print | Profitability functions exist but no report query contracts or print infrastructure | Add report contracts independent from pages, then exports and templates | receivables report and selected reports |
| 6 | Inventory, stock ledger, and valuation | Stock adjustments are only raw records | Add item, unit, location, quantity movement, valuation decision, batch, expiry, reorder | item, stock entry, stock reconciliation, stock ledger, valuation, batch, reorder |
| 7 | Procurement | No request or order to payable workflow | Add purchase order -> receipt -> invoice -> obligation -> settlement chain | purchase order, purchase receipt, purchase invoice, landed cost |
| 8 | Sales and collections | No contract or order to receivable workflow | Add sales contract or order -> delivery -> invoice -> obligation -> settlement chain | sales order, delivery note, sales invoice, payment schedule |
| 9 | Asset lifecycle | Existing assets lack governed lifecycle transitions | Add movement, valuation history, maintenance, repair, disposal and traceability | asset, movement, value adjustment, maintenance, repair |
| 10 | Projects, tasks, budgets, approvals | Existing projects lack planning and control kernels | Add tasks, milestones, responsibility, budgets, variance, approvals, period locks | project, task, budget, accounting period |
| 11 | Contracts, recurring schedules, renewals | Missing | Add minimal recurring schedule and renewal seam only when contract workflows land | payment schedule, subscription |
| 12 | Maintenance, inspection, quality | Missing | Add generic inspection and corrective-action contract reusable across sectors | maintenance schedule, quality inspection |
| 13 | Bank and cash reconciliation | Missing | Reserve account IDs in masters; implement reconciliation after posting contracts stabilize | bank account, bank transaction, payment reconciliation |
| 14 | Generic operational-event bridge | Raw event store is not yet governed | Add typed effects and controlled posting from sector event to stock or finance | work-order patterns only plus Terranex sector model |
| 15 | Staged imports and integrity repair | Missing | Add preview and validation staging after core contracts settle | Validation patterns only |

## 6. Recommended next implementation increment

### Branch

```text
feat/settlement-allocation-foundation-stage-2a
```

### Goal

Introduce an explicit local-first `SettlementAllocation` foundation without changing the current UI into a broad reconciliation workspace.

A `Settlement` remains the posted cash movement. A new `SettlementAllocation` record links a settlement to an obligation and stores the allocated amount. This separation is required before one cash movement can settle multiple obligations.

### Recommended narrow contract

```ts
interface SettlementAllocation {
  id: string;
  settlement_id: string;
  obligation_id: string;
  allocated_amount_egp: number;
  created_at: string;
}
```

The first PR should deliberately remain small:

1. add `src/features/settlement-allocations/types.ts`;
2. add `src/features/settlement-allocations/storage.ts` using localStorage key `terranex.settlementAllocations.v1`;
3. add an idempotent migration that creates one allocation for every existing settlement with an `obligation_id`;
4. keep the legacy `Settlement.obligation_id` field temporarily for backward compatibility and audit readability;
5. derive obligation active totals from active settlements joined to allocation records;
6. preserve current one-obligation posting behavior by creating one allocation during posting;
7. preserve reversal history and ensure reversed settlements contribute zero active allocation total;
8. extend backup and restore only through the existing `terranex.*` key mechanism; no archive special case is needed unless binary behavior changes;
9. add focused business-rule tests;
10. do not add a multi-obligation UI in this first PR.

### Acceptance criteria

- Existing settlement records migrate exactly once to one allocation each.
- Running the migration repeatedly produces no duplicates.
- Existing one-obligation settlement behavior remains unchanged from the user's perspective.
- Obligation totals are derived from active allocated amounts, not from a mutable running balance alone.
- Reversing a settlement keeps the settlement and its allocations for audit but removes their effect from the active total.
- A settlement allocation cannot exceed the target obligation's remaining balance.
- Allocation references must resolve to real settlements and real obligations.
- Existing receipt-document guards remain effective.
- Existing ZIP backup automatically includes the new `terranex.settlementAllocations.v1` key.
- Migration preserves legacy records rather than deleting them.
- `npm run typecheck`, `npm run lint`, `npm run test`, and `npm run build` pass before merge.

## 7. Ordered PR sequence

Each entry is one isolated branch and one narrow pull request. Do not combine adjacent stages unless the first diff proves they cannot be safely separated.

### Stage 1 review closeout

| PR | Branch suggestion | Increment | Notes |
|---:|---|---|---|
| 1 | `chore/review-document-proof-stage-1` | Review-only checkpoint if a regression is reported | Current code already contains IndexedDB binaries and ZIP restore validation. Do not reopen Stage 1 without a proven defect. |

### Stage 2 — obligations, settlements, allocation, aging, and cash controls

| PR | Branch suggestion | Increment | Main landing points |
|---:|---|---|---|
| 2A | `feat/settlement-allocation-foundation-stage-2a` | Allocation records, idempotent backfill, derived totals, focused tests | new `settlement-allocations` feature; settlements storage and posting; obligations sync; deletion guards; test compile config |
| 2B | `feat/multi-obligation-settlement-posting-stage-2b` | Atomic workflow to allocate one settlement across multiple obligations of a compatible party and direction | settlements posting; allocation validation; rollback tests |
| 2C | `feat/settlement-allocation-ui-stage-2c` | Small UI for selecting open obligations and entering allocations; no broad reconciliation dashboard | obligations or settlement UI only |
| 2D | `feat/obligation-aging-query-stage-2d` | Aging buckets and party statement query contracts independent from pages | new finance query module and tests |
| 2E | `feat/cash-bank-account-master-stage-2e` | Local cash and bank account master and settlement account selection | shared masters store; settlement type and form; migration if stored shape changes |

### Stage 3 — shared masters and internal posting contract

| PR | Branch suggestion | Increment |
|---:|---|---|
| 3A | `feat/shared-masters-stage-3a` | Typed local masters for currencies, units, locations, categories, and payment methods |
| 3B | `feat/internal-posting-contract-stage-3b` | Stable Terranex-native posting and projection contract without a full general-ledger UI |
| 3C | `feat/period-locks-stage-3c` | Conservative close and reopen controls for historical periods |

### Stage 4 — reports and print infrastructure

| PR | Branch suggestion | Increment |
|---:|---|---|
| 4A | `feat/report-query-contracts-stage-4a` | Shared report filters and query contracts |
| 4B | `feat/financial-reports-stage-4b` | Executive, project P&L, receivables, payables, aging, ledger, asset-register, and party-statement read models |
| 4C | `feat/report-export-stage-4c` | CSV and Excel export |
| 4D | `feat/bilingual-print-stage-4d` | Print preview and Arabic, English, and bilingual templates |

### Stage 5 — inventory and procurement foundation

| PR | Branch suggestion | Increment |
|---:|---|---|
| 5A | `feat/item-unit-location-masters-stage-5a` | Item, unit, and location masters |
| 5B | `feat/stock-quantity-ledger-stage-5b` | Governed stock movements and quantity ledger |
| 5C | `feat/stock-valuation-stage-5c` | Selected valuation method after explicit product decision |
| 5D | `feat/batch-expiry-reorder-stage-5d` | Batch, expiry, and reorder controls |
| 5E | `feat/procure-to-pay-stage-5e` | Purchase order -> receipt -> invoice -> payable -> settlement |

### Stage 6 — assets, projects, contracts, maintenance, and budgets

| PR | Branch suggestion | Increment |
|---:|---|---|
| 6A | `feat/asset-lifecycle-stage-6a` | Movement, valuation history, repair, disposal controls |
| 6B | `feat/project-task-milestone-stage-6b` | Tasks, milestones, responsibilities, progress |
| 6C | `feat/budget-approval-stage-6c` | Budget, approval, and variance controls |
| 6D | `feat/contract-scheduler-stage-6d` | Minimal recurring schedule, renewals, reminders |
| 6E | `feat/maintenance-inspection-stage-6e` | Maintenance, inspection, non-conformance, corrective actions |

### Stage 7 — operational-event bridge

| PR | Branch suggestion | Increment |
|---:|---|---|
| 7A | `feat/operational-effect-contract-stage-7a` | Typed event effects and traceability rules |
| 7B | `feat/operational-stock-bridge-stage-7b` | Controlled event -> stock movement bridge |
| 7C | `feat/operational-finance-bridge-stage-7c` | Controlled event -> transaction or obligation bridge |

### Stage 8 — sector-specific composition

| PR | Branch suggestion | Increment |
|---:|---|---|
| 8A | `feat/real-estate-workflow-stage-8a` | Property registry, valuation, development, contractor, rental and sales composition |
| 8B | `feat/agriculture-workflow-stage-8b` | Farm, plot, season, crop, yield, inputs, sales and seasonal profitability composition |
| 8C | `feat/livestock-workflow-stage-8c` | Herd, health, vaccination, feed, birth, death, purchase, sale and profitability composition |

### Stage 9 — reconciliation, imports, and integrity tooling

| PR | Branch suggestion | Increment |
|---:|---|---|
| 9A | `feat/bank-reconciliation-stage-9a` | Cash and bank transaction reconciliation |
| 9B | `feat/staged-import-stage-9b` | Preview, row validation, explicit error reporting, safe commit |
| 9C | `feat/integrity-repair-stage-9c` | Integrity checks and repair workflows that preserve history |

### Final migration stage

| PR | Branch suggestion | Increment |
|---:|---|---|
| F1 | `feat/supabase-migration-contract-final` | Design and implement Supabase migration only after local workflows, migrations, reporting, documents, and recovery are stable |

## 8. ERPNext reading map by proposed stage

Read only the relevant pinned files before each stage. Do not load the entire ERPNext tree into context.

| Terranex stage | Approved ERPNext reading paths |
|---|---|
| Settlement allocation | `erpnext/accounts/doctype/payment_entry/payment_entry.json`, `payment_entry.py`, `payment_entry_reference/payment_entry_reference.json`, `payment_reconciliation/payment_reconciliation.json`, `payment_reconciliation.py`, `accounts/report/accounts_receivable/accounts_receivable.py` |
| Shared masters and period locks | `accounting_period/*`, `bank_account/*`, `budget/*`, `stock/doctype/item/*` |
| Posting projection | `accounts/general_ledger.py`, `accounts/doctype/journal_entry/*`, `controllers/accounts_controller.py` |
| Inventory | `controllers/stock_controller.py`, `stock/stock_ledger.py`, `stock/valuation.py`, `stock/doctype/item/*`, `stock_entry/*`, `stock_reconciliation/*`, `batch/*`, `item_reorder/*`, `landed_cost_voucher/*` |
| Procurement | `buying/doctype/purchase_order/*`, `stock/doctype/purchase_receipt/*`, `accounts/doctype/purchase_invoice/*` |
| Sales and collections | `selling/doctype/sales_order/*`, `stock/doctype/delivery_note/*`, `accounts/doctype/sales_invoice/*`, `accounts/doctype/payment_schedule/*` |
| Asset lifecycle | `assets/doctype/asset/*`, `asset_movement/*`, `asset_value_adjustment/*`, `asset_maintenance/*`, `asset_repair/*` |
| Projects and tasks | `projects/doctype/project/*`, `projects/doctype/task/*`, `accounts/doctype/budget/*` |
| Contracts | `accounts/doctype/payment_schedule/*`, `accounts/doctype/subscription/*` |
| Maintenance and quality | `maintenance/doctype/maintenance_schedule/*`, `stock/doctype/quality_inspection/*` |
| Operational-event bridge | `manufacturing/doctype/work_order/*` patterns only; do not port manufacturing logic |

## 9. Storage and migration impact notes

### General rules

- Keep all structured records behind localStorage abstractions until the final Supabase migration stage.
- Store document binaries in IndexedDB only.
- Keep migrations deterministic, conservative, recoverable, and idempotent.
- Preserve unmappable records for review; do not fabricate links.
- Reuse the existing ZIP backup behavior for new `terranex.*` keys unless binary storage changes.
- Review deletion guards whenever a new cross-record link is added.

### Immediate Stage 2A migration

The first implementation PR should add a dedicated migration marker such as:

```text
terranex.settlementAllocations.legacy-settlement-migration.v1
```

The migration should:

1. read existing settlements and obligations safely;
2. stop without overwrite when an expected collection is malformed;
3. add one allocation per legacy settlement only when the settlement and obligation references are valid;
4. preserve malformed or unmappable records in an audit collection rather than silently discarding them;
5. write idempotently;
6. mark completion only after successful writes;
7. keep legacy `Settlement.obligation_id` during the compatibility window.

## 10. Business-rule test matrix

| Engine slice | Required tests |
|---|---|
| Settlement-allocation migration | One allocation per legacy settlement; repeat run produces no duplicates; malformed collections cause no overwrite; missing obligation reference is preserved for review |
| Allocation validation | Missing settlement rejected; missing obligation rejected; zero or negative allocation rejected; non-finite allocation rejected; allocation beyond remaining balance rejected |
| Allocation-derived totals | One settlement to one obligation keeps current behavior; multiple settlements to one obligation sum correctly; reversed settlement contributes zero; partial and settled statuses derive correctly |
| Multi-obligation posting | One payment allocates across multiple compatible obligations atomically; rollback removes all newly written records when any allocation fails |
| Receipt protection | Receipt remains linked to the settlement cash movement; linked receipt cannot be deleted while settlement history exists |
| Deletion guards | Obligation with allocation history cannot be deleted silently; allocation records survive reversal for audit |
| Backup and restore | New allocation key exports and restores through existing `terranex.*` backup behavior; restored totals equal pre-export totals |
| Aging | Due-date bucket boundaries; settled and written-off exclusion; party statement ordering and totals |
| Posting contract | Projection output deterministic; reversal produces offset behavior without destructive edits |
| Inventory | Quantity cannot become invalid silently; valuation method deterministic; batch and expiry rules enforced |
| Procurement and sales | Each workflow produces traceable documents, transactions, obligations, settlements, and reversals |
| Operational event bridge | An event creates only declared stock or finance effects and preserves source links |

## 11. Product decisions requiring review before related coding

These decisions should be resolved deliberately and recorded as ADRs when their stage is selected.

| Decision | Why it matters | Needed before |
|---|---|---|
| Confirm base and display currency policy, including `OMR` support | Architecture examples use OMR while current financial calculations normalize to EGP | Shared masters or any currency correction PR |
| Manual allocation only versus optional FIFO auto-allocation | ERPNext supports explicit selection and FIFO fallback; Terranex should start with the smallest auditable rule | Stage 2B |
| Whether one settlement may allocate across projects when party and direction match | Cross-project allocation may be useful but changes audit and UI expectations | Stage 2B |
| How to treat overpayments and advances | Current workflow correctly rejects over-settlement; advances need a separate explicit model | After Stage 2B |
| Whether every settlement must select a cash or bank account | Needed for reconciliation and cash reporting | Stage 2E |
| Inventory valuation method: FIFO or weighted average | Must be deterministic before stock valuation implementation | Stage 5C |
| Whether landed cost is required in the first procurement release | Affects purchase receipt valuation and transport handling | Stage 5E |
| Jurisdiction and tax requirements | Avoid premature regional behavior | After core workflows stabilize |

## 12. Explicit deferrals and exclusions

### Deferred until later approved stages

- Supabase, authentication, multi-user roles, and remote storage;
- full ledger UI;
- bank reconciliation;
- stock valuation and procurement;
- asset maintenance and project-budget depth;
- sector-specific composition;
- staged imports and integrity repair;
- tax and jurisdiction implementation.

### Excluded unless a concrete Terranex use case appears

- ERPNext manufacturing BOM and shop-floor implementation;
- Frappe framework dependencies;
- ERPNext runtime imports;
- CRM breadth;
- support-suite breadth;
- regional modules without explicit requirements;
- EDI, telephony, shopping cart, portal, POS, loyalty, and promotions.

## 13. Stage 0 completion checklist

- [x] Latest `main` inspected at an immutable commit SHA.
- [x] Roadmap and architecture sources reviewed.
- [x] Current storage, migration, document, transaction, obligation, settlement, profitability, event, route, and test surfaces mapped.
- [x] Open PR `#32` identified and excluded from this stage.
- [x] Selected ERPNext settlement-allocation behavior reviewed from the pinned reference set.
- [x] One narrow recommended implementation branch selected.
- [x] No runtime file changed.
- [x] No storage schema changed.
- [x] No generated bundle or ERPNext source file added.
- [x] No Supabase dependency added.
- [x] `.reference-cache/` remains ignored and uncommitted.

Stop here. Do not begin Stage 2A until this plan is reviewed.
