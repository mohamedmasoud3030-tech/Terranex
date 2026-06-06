# Terranex Data Safety Policy

Terranex is an investment operating system. Financial and operational records must remain traceable, reviewable, and recoverable.

## Core safety rules

- Every financial transaction must remain attributable to its source, project, counterparty, and supporting document when available.
- Profitability is derived from recorded transactions and obligations. Do not store editable summary totals as an alternative source of truth.
- Receivables and payables remain explicit obligations. Do not hide unresolved balances inside narrative notes.
- Linked records with financial or operational history must not be deleted silently.
- Corrections preserve history through explicit reversal, cancellation, replacement, or migration behavior.
- Recoverable legacy records may be migrated only when mappings are safe. Unmappable records remain preserved for audit without invented links.

## Local persistence rules

- Treat `src/core/storage/localStorageStore.ts` and `src/core/storage/migrations.ts` as sensitive boundaries.
- Keep migrations versioned, deterministic, and backward-aware.
- Do not seed demo records into production runtime.
- Do not overwrite local state without validating imported or migrated data.

## ERPNext reference boundary

ERPNext is a behavioral reading reference only. Do not copy ERPNext runtime code into Terranex, add Frappe dependencies, or commit local reference caches.

## Review requirement

Any PR touching transactions, obligations, profitability, deletion guards, migrations, imports, exports, documents, or audit behavior must state the data impact and include targeted verification.