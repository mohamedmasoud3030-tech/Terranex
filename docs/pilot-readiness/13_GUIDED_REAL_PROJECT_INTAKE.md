# 13 — Guided Real-Project Intake

**Status:** technical readiness for receiving the first real Real Estate project.  
**Does not pass Phase 2 or Phase 3.**

## What this stage is

A single Arabic-first operator workspace that sequences the existing S0–S7 commands so the first real project can be entered without inventing a second import engine, a second ledger, or a second workflow state machine.

Route: `/intake` then `/projects/{id}/intake`.

Readiness is **derived** from canonical S0–S7 records plus a thin declaration layer. Nothing in the intake tables posts a journal line.

## What was reused

| Step | Existing surface |
| --- | --- |
| Organization / project | S0 `create_organization`, `create_investment_project` |
| Parties, investors, agreement, commitments, calls, contributions | S1 commands and `/terms`, `/funding` forms |
| Ownership / allocation weights summing to 100% | S5 `s5_configure_allocation_rules` |
| Cash accounts, bank statements | S2 commands and `/cash` forms |
| Accounting period | S6 `s6_create_accounting_period` (UI was missing; now wrapped) |
| Real-estate profile, assets, parcels, acquisition, budget | S3 commands and `/operations` forms |
| Opening import lifecycle | S7 `s7_*` commands and `/pilot` forms |
| Reconciliation / readiness numbers | S7 checkpoints and `s7_pilot_acceptance_report_read` |

## What was added (smallest missing UX)

- Guided Arabic checklist with completed / missing / conditional / blocked / failed states.
- Freeze-date recording (control pack §2).
- Signed control-total declaration before S7 staging (control pack §4). Agreement title and org/project evidence references (DS-01/02/04 identifiers only).
- Conditional section applicability (historical calls, contributions, acquisition, development, unpaid suppliers, pre-freeze sales, unpaid distributions, live bank statements).
- Modelling-gap register for balances that do not fit the six locked S7 mapping codes. Reporting a gap does **not** invent a mapping and does **not** post.
- DS-17 evidence-register identifiers and customer storage locations. No document upload.
- Production UI around `s6_create_accounting_period` so opening posting has an OPEN period.

## Opening rules that remain locked

- Mapping codes: only `OPENING_BANK_CASH`, `OPENING_DEVELOPMENT_WIP`, `OPENING_CUSTOMER_RECEIVABLE`, `OPENING_SUPPLIER_PAYABLE`, `OPENING_CONTRIBUTED_CAPITAL`, `OPENING_DISTRIBUTION_PAYABLE`.
- Lifecycle: `DRAFT → VALIDATED → READY_FOR_APPROVAL → APPROVED → POSTED`.
- Rejected rows never post.
- Acceptance: declared debit = computed debit, declared credit = computed credit, debits = credits, variance = 0 minor units.
- Maker ≠ checker. No auto-approval.
- One historical cash path: S1/S2 contribution attribution **or** S7 opening cash/capital, never both.

## Phase status

| Gate | Status |
| --- | --- |
| Ready to receive real project data through the guided path | **YES — technically** |
| Phase 2 | **NOT PASSED** |
| Phase 3 | **NOT PASSED** |
| Phase 4 | **NOT STARTED** |

Phase 2 still requires real customer data, a source-data freeze, signed control totals, a controlled opening import, approval/posting, and exact zero-variance reconciliation.
