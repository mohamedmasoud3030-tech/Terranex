# TERRANEX
## Product Growth Roadmap and Functional Expansion Blueprint

**Product:** Terranex — Investment Operating System  
**Scope:** Real Estate • Agriculture • Livestock  
**Repository execution mirror:** June 2026  

## 1. Purpose

This roadmap is the primary product execution reference for Terranex. Use it to select the next implementation stage, understand workflow gaps, and prevent isolated screens or premature infrastructure work.

Terranex should become an internal Investment Operations OS for mixed real assets. It is not an ERPNext fork, a property-only application, or a collection of disconnected CRUD pages.

## 2. Source hierarchy

1. `docs/reference/Terranex-Product-Growth-Roadmap.md` — primary product execution roadmap.
2. `docs/reference/Terranex-Architecture-English.md` — architecture source of truth.
3. `docs/reference/Terranex-Product-Growth-Roadmap-Zoom-In.md` — engine extraction program zoom-in.
4. Current repository code on latest `main` — source of truth for what already exists.
5. `docs/reference/Terranex-ERPNext-Engine-Inventory-Summary.md` — reference-engine inventory and extraction boundaries.
6. ERPNext cache prepared by `node tools/fetch-erpnext-reference.mjs` — behavioral reading reference only.

## 3. Zoom-in protocol

Before implementing any module:

1. inspect current repository implementation first;
2. read the relevant roadmap and architecture sections;
3. inspect adjacent stores, hooks, domain types, migrations, routes, and tests;
4. identify one coherent increment only;
5. create an isolated branch from latest `main`;
6. add or update business-rule tests;
7. run the complete quality gate;
8. review the final diff carefully;
9. merge only after validation passes.

Do not implement the whole roadmap in one branch.

## 4. Strategic product model

Terranex differentiates itself through unified traceability:

```text
Project
  -> Asset
  -> Partner / Counterparty
  -> Document
  -> Transaction
  -> Obligation
  -> Settlement
  -> Profitability
  -> Report
```

The product must answer quickly:

1. How much profit did each project generate?
2. Which sector performs best?
3. Who owes the company money?
4. Whom does the company owe?
5. Which documents prove each figure?
6. What is the current value of each asset?
7. What operational event created each financial effect?
8. What should management act on today?

## 5. Infrastructure decision

### Supabase is intentionally deferred until the final migration stage

The current objective is to mature product workflows while keeping Terranex local-first.

Until the backend phase:

- keep structured records behind local storage abstractions;
- store uploaded file binaries in IndexedDB rather than Base64 in `localStorage`;
- preserve export and restore capability;
- add local audit events where feasible;
- keep migrations versioned, conservative, recoverable, and idempotent;
- avoid decisions that make later Supabase migration harder.

Do not add Supabase while the product model is still changing.

## 6. Core product principles

### Project as primary container

Every financial and operational record belongs to a project unless a documented exception exists.

### Traceability before convenience

Every financial figure should trace to:

- a project;
- a transaction;
- a party or counterparty;
- a supporting document;
- an obligation when payment is outstanding;
- a settlement record when payment occurs.

### Profitability remains separate from cash exposure

```text
Profit = Income - Expense
Cash Exposure = Open Receivables - Open Payables
```

Receivables and payables must not distort accounting profit.

### Preserve historical data

Do not delete or fabricate data during migrations. Preserve records that cannot be mapped safely, flag them for review, and avoid inventing missing values.

### Protect linked entities

Linked entities cannot be deleted silently. Resolve relationships or use controlled cancellation and reversal workflows.

### Build workflows, not isolated screens

A page is incomplete if it displays records without supporting the operational chain.

Example:

```text
Invoice uploaded
  -> expense transaction created
  -> payable obligation created
  -> partial settlement recorded
  -> receipt linked
  -> remaining balance recalculated
  -> profitability updated
  -> report reflects the change
```

## 7. Delivery roadmap before Supabase

### Phase 1 — Traceability completion and local file uploads

Goal: complete local-first document workflows and make every new financial record traceable.

Work items:

1. strengthen transaction reference validation;
2. validate linked projects, parties, and documents;
3. reject invalid cross-project linkage;
4. require project linkage for new documents;
5. add local file upload through IndexedDB;
6. add MIME and size validation;
7. add preview, download, archive, and safe delete;
8. include binaries in ZIP backup export;
9. validate archive restore before overwriting local data;
10. add regression tests.

### Phase 2 — Obligations, settlements, and cash workflow

Goal: complete receivable and payable lifecycle.

Work items:

1. trace obligations to source records;
2. keep settlement as a separate entity;
3. support settlement allocation across multiple obligations;
4. support partial settlements and remaining balances;
5. attach receipts and payment vouchers;
6. add payment method and cash or bank account;
7. add controlled reversals;
8. add dispute and write-off reasons;
9. add aging groups and party statements;
10. add tests.

### Phase 3 — Reports and print templates

Goal: add management reporting and official printable outputs.

Work items:

1. report query contracts independent from UI pages;
2. shared filters by dates, sector, project, party, asset, status, category, and currency;
3. executive report, project P&L, sector comparison, ledger, receivables, payables, aging, asset register, and party statement;
4. CSV, Excel, PDF, and print preview;
5. company identity and numbering;
6. Arabic, English, and bilingual templates;
7. tests.

### Phase 4 — English localization and settings expansion

Goal: make Terranex configurable and bilingual.

Work items:

1. translation keys for pages, forms, validation messages, reports, and print templates;
2. Arabic RTL and English LTR validation;
3. company profile;
4. numbering settings;
5. currencies, payment methods, categories, units, and alerts;
6. tests.

### Phase 5 — Real-estate deepening

Add property registry, valuation history, development stages, contractor workflow, documents, basic rental and sales workflows, and profitability reports.

### Phase 6 — Agriculture deepening

Add farms, plots, seasons, crops, yield, operation logs, inputs, inventory basics, sales, and seasonal profitability.

### Phase 7 — Livestock deepening

Add herd registry, species, breeds, livestock events, births, deaths, health records, vaccination schedules, feed inventory, feeding cost calculations, and profitability by herd and head.

### Phase 8 — Daily operations improvements

Add global search, notifications, tasks, saved report filters, staged imports, bulk actions, recurring transactions, local audit events, integrity checks, and dashboard charts.

### Phase 9 — Supabase migration and multi-user platform

Begin only after document handling, ZIP backup, obligation lifecycle, reports, print templates, localization, settings, sector workflows, and local migrations are stable.

## 8. Engine extraction program

The ERPNext extraction program is subordinate to this roadmap. It must rebuild only the useful behavior as Terranex-native modules.

Use:

- `docs/reference/Terranex-Product-Growth-Roadmap-Zoom-In.md`;
- `docs/reference/Terranex-ERPNext-Engine-Inventory-Summary.md`;
- `reference/erpnext/README.md`;
- `node tools/fetch-erpnext-reference.mjs`.

The immediate implementation priority remains Phase 1 document binaries and traceability. Do not jump directly into ledger, stock, or procurement implementation before Stage 0 planning and Phase 1 review.

## 9. Implementation rules

1. One coherent increment per pull request.
2. No unnecessary files, generated bundles, duplicate helpers, or unrelated refactors.
3. Keep existing data recoverable.
4. Test business rules, not only UI rendering.
5. Run the full quality gate:

```bash
npm ci
npm run typecheck
npm run lint
npm run test
npm run build
```

6. Preserve `main` as the stable baseline.
7. Zoom in before coding.
8. Do not add Supabase before the final migration stage.
9. Do not import ERPNext or Frappe into runtime code.

## 10. Immediate next action

Run Codex Stage 0 planning first using:

```text
docs/prompts/codex-terranex-engine-extraction-stage-0.md
```

Codex must stop after producing the focused implementation plan. The first implementation branch is selected only after that plan is reviewed.
