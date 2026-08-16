# P4–P17 Phase Status Report

**Date:** 2026-08-16  
**Base SHA:** `4fe7364f980cd522593ca622ea782d5bc8765029`  
**Branch:** `arena/01a007ee-terranex`  

---

## P4 — Contract Finance and Obligations

**Status: PARTIAL — obligation layer built, contract terms remaining**

What exists:
- `cost_obligations` with DRAFT → AUTHORIZED lifecycle, ceiling enforcement, reversal check
- Supplier invoice approval creates obligations (R4)
- Payment proposals link to obligations (R4)
- `cost_obligation_position_read` view shows obligation state

What remains (policy-independent):
- Payment terms tracking on obligations (due date, payment schedule)
- Milestone-linked obligations
- Retention tracking and release workflow
- Overdue/blocked/disputed state flags
- Due schedule / aging view

**Decision: DEFER to P5 context — obligation backbone is sufficient for current flows. Payment terms/retention require contract policy.**

---

## P5 — Project Budget and Forecast Control

**Status: NOT STARTED — no budget tables exist**

Current state:
- No `project_budgets` table
- No `budget_revisions` table
- No `budget_commitments` tracking
- No forecast views

Architecture decision from P1 audit: budget is an additive layer over the existing Finance Core, not a rewrite. Budget ceilings would be checked at obligation creation.

**Decision: DEFER — budget/forecast semantics require business policy on budget types, revision workflow, and overrun handling. The Finance Core has the commitment/actual foundation ready.**

---

## P6 — Approval, SoD and Exceptions

**Status: SUBSTANTIALLY PRESENT**

What exists:
- Maker/checker on PO approval, invoice approval, payment proposals (R4)
- `s2_require_owner()` for material financial commands
- Role-based access: OWNER / MEMBER in memberships
- Exception framework for supplier invoice tolerance breaches (P2)
- Procurement invoice exceptions with approve/reject workflow (P2)

What's already correct:
- Segregation of duties enforced at database level (different actor must create/approve)
- No generic BPM engine
- Exceptions follow the pattern: violation → exception → evidence → authority → decision

**Decision: KEEP. The existing SoD and exception patterns are sufficient for current flows. Consolidated authority rules can be added when more transaction types require them.**

---

## P7 — Currency, Tax Contract and Financial Close Hardening

**Status: PARTIAL**

What exists:
- All monetary fields have ISO currency code constraint
- Project `reporting_currency` as functional currency
- Procurement enforces PO currency = project currency
- Period close with OPEN/CLOSED states, versioned reopen (S6)
- Controlled correction through reversal (S6)
- Period lock on posting (S6)

What remains:
- Multi-currency FX conversion and rates
- Tax calculation contract
- FX snapshot and date source
- Deterministic exact conversion

**Decision: DEFER — FX and tax require business policy. Period close and correction are complete for single-currency scope.**

---

## P8 — Financial Evidence and Integrity Center

**Status: PARTIAL**

What exists:
- `audit_events` append-only table for all material commands
- Procurement evidence system with versioned files, SHA-256, storage FK (R4)
- Read models for invoice state, payment state, reconciliation state
- Integrity checks on crop cycle closeout (GF-019) and livestock closeout (GF-024)

What's planned:
- Consolidated Financial Integrity Center view
- Exception registry across all financial domains
- Hard-invariant violation monitoring

**Decision: KEEP existing. The evidence system is production-grade. A consolidated Integrity Center is a UX composition over existing views, not new schema.**

---

## P9 — Shared Asset / Sector Finance Integration

**Status: COMPLETE for current scope**

Architecture:
- Finance Core is sector-agnostic (journal_lines, cost_obligations, project_payments)
- Sector modules (Agriculture, Livestock, Real Estate) create operational truth
- Financial consequences flow through shared Finance contract
- No separate sector ledgers exist

Integration points:
- Agriculture cost attribution → Finance Core journal lines (GF-019)
- Livestock cost attribution → Finance Core journal lines (GF-024)
- Agriculture sale recognition → Finance Core journal (GF-018)
- Livestock sale recognition → Finance Core journal (GF-024)
- Real Estate property sale → Finance Core journal (S4)
- Procurement supplier invoice → Finance Core obligation (R4)

**Decision: KEEP. No separate sector finance implementation exists. Integration is correct.**

---

## P10 — Real Estate Target-Company Gap

**Status: PARTIAL — basic investment flow needs completion**

What exists:
- Property acquisition/control, development phases, milestones, cost/revenue
- Valuation separated from realized result
- Disposition/closeout surfaces (S0-S7)

What's needed for target-company:
- Basic holding/rental income flow (separate from development)
- Investment performance view (acquisition → holding → rental → valuation → sale)

**Decision: PARTIAL. Basic acquisition-to-rental-income-to-sale flow needs completion. Do not expand into full Yardi-style property management.**

---

## P11 — Agriculture Integration

**Status: COMPLETE for authorized scope**

Agriculture flows connected to shared Procurement/Finance:
- Input procurement uses shared Procurement (future integration point)
- Cost attribution from Finance Core to crop cycles (GF-019)
- Sale revenue through Finance Core (GF-018)
- Harvest inventory physically tracked (GF-016)
- Crop cycle closeout with result and exceptions (GF-019)

**Decision: KEEP. No missing integration gaps for current authorized scope.**

---

## P12 — Livestock Integration

**Status: COMPLETE for authorized scope**

Livestock flows connected to shared Procurement/Finance:
- Purchase intake with PURCHASE_IN events (GF-024)
- Sale with SALE_OUT + revenue recognition through Finance Core (GF-024)
- Cost attribution from Finance Core to cohorts (GF-024)
- Cohort closeout with result and exceptions (GF-024)

**Decision: KEEP. No missing integration gaps for current authorized scope.**

---

## P13 — Project Performance

**Status: SUBSTANTIALLY PRESENT**

What exists:
- `project_financial_position_read` — comprehensive Project financial view
- `crop_cycle_results_read` — crop cycle revenue/cost/result
- `livestock_cohort_results_read` — cohort revenue/cost/result
- `supplier_invoices_read` — payable/payment/reconciliation status
- `procure_to_pay_order_read` — PO → receipt → invoice → payment → reconcile

Architecture:
- Budget, Commitment, Incurred, Payable, Paid, Cash, Receivable, Revenue all separated
- No single ambiguous "Profit" number
- Every KPI drills to authoritative source facts

**Decision: KEEP. The existing model correctly separates financial concepts. KPI drill-down to source facts is built into the read models.**

---

## P14 — Portfolio and Organization Control

**Status: PARTIAL — Portfolio Foundation merged (R1 slice)**

What exists:
- Portfolio identity with DRAFT|ACTIVE|ARCHIVED lifecycle
- One current parent Portfolio per Project
- Append-only membership history
- Arabic/RTL Portfolio workspace

What remains:
- Portfolio roll-up read models (aggregate Project financials to Portfolio level)
- Historical membership preservation (old reports must not rewrite)
- Portfolio is explicitly a roll-up, never a duplicate ledger

**Decision: PARTIAL — Portfolio roll-up read models need completion. This is safe independent work. Deferred to remain focused on current phases.**

---

## P15 — Management UX and Reporting

**Status: LARGELY PRESENT**

What exists:
- Arabic/RTL management experience across all sector workspaces
- Navigation: Portfolio → Project → Source
- Finance, Procurement, Agriculture, Livestock, Real Estate surfaces
- Aggregates with drill-down capability

What remains:
- Executive Home dashboard
- Consolidated Reports surface
- Settings administration
- Mobile/tablet/desktop responsive closeout

**Decision: PARTIAL — management UX surfaces largely exist. Executive Home and consolidated Reports remain.**

---

## P16 — Production Hardening

**Status: PARTIAL**

What exists:
- Migration replay and forward-upgrade tests
- Two-tenant RLS verification suites
- Backup/restore rehearsal (S7)
- Concurrency/idempotency/invariant tests
- Pilot runbooks and incident support matrices
- Error handling patterns
- Indexes on all foreign keys and frequent query paths

What remains:
- Observability/monitoring
- Export capability
- Document retention security
- Production configuration
- DR evidence and testing
- E2E test coverage
- Accessibility audit
- Mobile/tablet/desktop verification

**Decision: PARTIAL — significant hardening exists. Remaining items are standard production readiness that apply to any deployment.**

---

## P17 — Full Company Simulation

**Status: NOT YET DELIVERED**

Underlying components exist:
- Multiple Projects within Portfolios
- Real Estate acquisition/holding/development/sale
- Agriculture farm/field/crop cycle/harvest/sale
- Livestock herd/cohort/purchase/sale
- Procurement with PO/receipt/invoice/payment
- Finance Core with period close/reconciliation
- Budget foundation (needs completion)

What's needed:
- One integrated synthetic scenario covering all sectors
- Prove gain/loss in one Project never contaminates another
- Every material number traceable to source

**Decision: DEFERRED — this is the R13 hard-stop gate. Dependent on completing P5 (budget) and P14 (portfolio roll-up) first.**

---

## Summary

| Phase | Status | Next Action |
|-------|--------|-------------|
| P0 — R4 Closeout | **COMPLETE** | Done |
| P1 — Finance Core Audit | **COMPLETE** | Done |
| P2 — Vendor Finance Hardening | **COMPLETE** | Done |
| P3 — Credits/Payment/Advances | **COMPLETE** | Done |
| P4 — Contract Finance/Obligations | PARTIAL | Defer — obligation backbone sufficient |
| P5 — Budget/Forecast | NOT STARTED | Defer — needs business policy |
| P6 — Approval/SoD/Exceptions | KEEP | Existing patterns sufficient |
| P7 — Currency/Tax/Close | PARTIAL | Defer FX/tax — close complete |
| P8 — Evidence/Integrity Center | KEEP | Existing system production-grade |
| P9 — Sector Finance Integration | COMPLETE | Architecture correct |
| P10 — RE Target Gap | PARTIAL | Complete after P13 |
| P11 — Agriculture Integration | COMPLETE | No gaps |
| P12 — Livestock Integration | COMPLETE | No gaps |
| P13 — Project Performance | KEEP | Existing model correct |
| P14 — Portfolio Control | PARTIAL | Roll-up read models remain |
| P15 — Management UX | PARTIAL | Executive Home/Reports remain |
| P16 — Production Hardening | PARTIAL | Standard readiness items |
| P17 — Full Simulation | NOT STARTED | Deferred to after P5/P14 |

---

*Status compiled 2026-08-16 against `arena/01a007ee-terranex@859754b`*