# Terranex — Product Roadmap Zoom-In for Engine Extraction

## Purpose

This document narrows the Terranex roadmap to one program of work: study selected ERPNext engine behavior and rebuild the useful parts as Terranex-native TypeScript modules.

ERPNext is a reference specification only. Terranex must not import ERPNext Python code, add Frappe, or become an ERPNext fork.

## Source hierarchy

1. `docs/reference/Terranex-Architecture-English.md` — architecture source of truth.
2. This zoom-in roadmap — execution ordering for the extraction program.
3. Current repository code on latest `main` — source of truth for what already exists.
4. `reference/erpnext/selected-paths.txt` — curated ERPNext reading list.
5. `reference/erpnext/expected-sha256.txt` — integrity contract for the original uploaded reference set.

## Non-negotiable boundaries

- Keep Terranex local-first until the final migration stage.
- Do not add Supabase now.
- Do not copy ERPNext folders into `src/`.
- Do not add Frappe dependencies.
- Do not perform broad refactors.
- Implement one narrow stage per branch and pull request.
- Preserve recoverable historical data.
- Use explicit migrations when an existing stored shape changes.
- Run lint, typecheck, tests, build, and final diff review before merge.

## Product truth model

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

Financial truth and operational truth must remain traceable to source documents and project context.

## Engine portfolio to rebuild natively

### Foundation kernels

1. Shared masters and configuration.
2. Unified parties and counterparties.
3. Document proof and local file packages.
4. Audit, cancellation, reversal, and integrity checks.
5. Reporting, export, print, and bilingual templates.

### Financial kernels

6. Internal posting contract and ledger projection.
7. Obligations, settlements, allocation, and aging.
8. Bank and cash reconciliation.
9. Budgets, approvals, variance, and period locks.

### Operational kernels

10. Inventory, quantity ledger, valuation, batch, expiry, and reorder.
11. Procurement: request or order -> receipt -> invoice -> obligation -> settlement.
12. Sales and collections: order or contract -> delivery -> invoice -> obligation -> settlement.
13. Asset lifecycle: acquisition, movement, valuation, maintenance, repair, disposal.
14. Projects, milestones, tasks, responsibilities, and progress.
15. Contracts, recurring schedules, renewals, and reminders.
16. Maintenance, inspection, quality, and corrective actions.
17. Generic operational-event bridge for real estate, agriculture, and livestock.
18. Staged data import with preview, row validation, and explicit error reporting.
19. Tax and jurisdiction extension seams without premature regional implementation.

## Required extraction order

### Stage 0 — Inspect and plan only

Inspect latest `main`, map existing stores and features, compare them with the engine portfolio, and propose landing boundaries. Do not edit runtime code.

### Stage 1 — Document proof and IndexedDB binaries

Complete local document binaries, metadata linkage, preview, download, archive, safe delete, and ZIP backup restore validation.

### Stage 2 — Settlement allocation and cash controls

Extend the existing settlement foundation to support allocation across multiple obligations, reversals, aging, and statements.

### Stage 3 — Shared masters and internal posting contract

Add deliberate Terranex-sized masters and a stable internal posting model without exposing a full ERP accounting UI.

### Stage 4 — Reports and print infrastructure

Add report query contracts, filters, snapshots where needed, exports, and official bilingual templates.

### Stage 5 — Inventory and procurement foundation

Add item master, units, locations, stock movement, valuation decision, reorder controls, purchase order, receipt, invoice, and payable linkage.

### Stage 6 — Assets, projects, contracts, maintenance, and budgets

Deepen existing modules using the same traceability rules.

### Stage 7 — Operational event bridge

Connect sector operations to stock and financial effects without duplicating three unrelated systems.

### Stage 8 — Sector-specific deepening

Compose real estate, agriculture, and livestock workflows from the shared kernels.

### Stage 9 — Bank reconciliation, staged imports, and quality controls

Add reconciliation, import staging, non-conformance, repair, and stronger integrity tooling.

### Final stage — Supabase migration

Introduce Supabase only after local workflows, migrations, reporting, and document handling are stable.

## First Codex task

The first Codex task is Stage 0 only: inspect latest `main`, read the architecture and reference map, produce a focused implementation plan, and recommend the first narrow branch. Do not implement runtime features during Stage 0.
