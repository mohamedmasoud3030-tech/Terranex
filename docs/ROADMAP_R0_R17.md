# Terranex — Roadmap R0–R17 (Build Everything Independent First)

**Status:** Canonical delivery roadmap
**Effective:** 2026-08-15
**Controlling strategy:** *Complete every feature whose correctness does not depend on unresolved legal/economic policy. Defer only the smallest rule-dependent portion.*
**Canonical reference:** referenced by `AGENTS.md`, `GREENFIELD_EXECUTION.md`, `docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md`, `docs/OPEN_BUSINESS_DECISIONS.md`.

## 1. The governing principle

The previous plan placed the hard stop at R5, which risked asking the company owner for business-policy answers while the product was still incomplete. This roadmap moves the hard stop to **R13**. We build everything that is independent of the owner's investor/legal/economic answers to the end (R1–R13), and only then ask the owner for a small, well-scoped **policy pack** (R14). After the policy is fixed we finish the small rule-dependent tail (R15–R17).

Deferral rule: even a feature that is 90% independent and 10% rule-dependent is built **now** up to its independent 90%. Only the rule-dependent portion waits. Never invent a default, a fake percentage, an `OTHER` enum, a generic rules engine, or a guessed entitlement rule to avoid the stop. Never display an investor profit/entitlement number computed from an unapproved basis.

## 2. R0 — Canonical Realignment (merged)

`Portfolio ≠ Project ≠ Asset ≠ Legal Vehicle ≠ Operating Cycle`. The AI is forbidden from inventing Investor Economics. This is governance-only and merged at the R0 commit.

## 3. R1–R13 independent build — state against this repository

The independent build is largely already delivered by the existing technical history. This mapping reconciles the historical slice labels (S0–S7, GF-###, ADR 00xx) to the new R-phases. **Slice-label note:** delivered slices carry their own names (for example the merged "R1 — Portfolio Foundation" slice, PR #139 / ADR 0025, and "R4 Procurement Foundation/Receiving"), while the table rows below name roadmap phases and gates; a delivered slice may implement part of one phase (R1 Portfolio Foundation delivers the Portfolio-identity/Project-membership portion of phase R2 and the Portfolio workspace portion of R9). The phase numbers are the delivery order; the slice labels are the delivered increments.

| R | Independent capability | Repository state |
|---|---|---|
| R1 | Production Foundation: org, memberships, party registry, roles/capabilities, RLS, audit, maker/checker, documents/evidence, idempotency, exact money, periods, notifications foundation, Arabic/RTL | **Present.** S0–S2/S6/S7, `src/features/{organizations,projects,auth,close,pilot}`, shared money/idempotency. |
| R2 | Portfolio + Project + Asset core, many independent Projects in one Portfolio | **PARTIAL.** Portfolio identity/lifecycle, one current parent Portfolio per Project, append-only membership history and the Arabic Portfolio workspace are delivered. ADR 0032/R8 adds a read-only cross-sector asset register over sector-owned roots, but that reporting projection does **not** by itself close the separate canonical question of whether a narrow shared Asset identity/Project↔Asset association is still required. Remaining R2 work must be decided from the full canonical authorities, and still includes any required Asset identity/association plus Portfolio Documents/Decisions/Risks/Budget relationships. No universal sector asset activity table is authorized. |
| R3 | Complete financial control: budget, forecast, commitment, obligation, accrual, expense, revenue, receivable, payable, payment, receipt, cash, bank, reconciliation, subledger, reversal/repost, period close, portfolio roll-up | **Substantially present** in shared Finance Core S2–S6. Budget/forecast/commitment and Portfolio roll-up are the remaining R3 items. Deferred only: who of the investors is entitled to how much of the result. |
| R4 | Procurement & Shared Operations: suppliers, purchase requests/orders, receiving, invoices, payments, contracts, attachments, approvals, inventory concepts, counterparties | **Procure-to-pay and Contracts/Evidence delivered.** GF-025/GF-026 provide the operational core; ADR 0030 adds the commercial/financial chain through shared Finance; ADR 0031 adds private versioned PO/contract/receipt/invoice files, typed Project/tenant links, checksum/audit/immutability, signed reads and evidence approval gates. Remaining R4 item: the separately bounded shared inventory-value concepts, then closeout audit. |
| R5 | Real Estate (complete) | **Technically implemented.** S0–S7, GF-010/GF-011. |
| R6 | Livestock (complete) | **Technically implemented.** GF-020–GF-024. |
| R7 | Agriculture (complete) | **Technically implemented.** GF-013–GF-019. |
| R8 | Cross-sector asset & performance layer | **Delivered as a read projection** (ADR 0032). `cross_sector_asset_register_read` unions the four sector-owned asset roots and `sector_performance_read` gives per-sector cash/revenue/cost/realized result, surfaced at `/assets`. Per `docs/greenfield/03_DOMAIN_MODEL.md:175` this is explicitly **not** a universal asset table or FK target: no base table, no write command, sector roots keep ownership. Absent facts are reported as typed `*_status` reasons, never as zeros. |
| R9 | Management UX (Home, Portfolios, Projects, Assets, RE, Ag, Livestock, Money, Procurement, Documents, Approvals, Reports, Settings; Arabic/RTL + mobile/tablet/desktop) | **Largely present** across sector workspaces. Portfolio and Procurement workspaces are delivered (R1 slice + R4 procurement foundation), and the top-level Assets surface is delivered at `/assets` (ADR 0032); remaining: consolidated executive home/reports/settings surfaces. |
| R10 | Investor Transparency (read-models only, no invented rights): identity, secure login, party documents, updates, photos/evidence, activity, published reports, notices, statements framework, as-of date, valuation basis, data freshness — with entitlement-dependent fields inert | **Not started as a dedicated slice.** Design/read-model build is independent and safe; no entitlement numbers until R15. |
| R11 | Reporting & Control | **Substantially present** via read models/rollforwards; consolidated owner reporting is a remaining item. |
| R12 | Production Hardening: backups/restore, migration replay, RLS/security, concurrency, idempotency, invariants, audit, indexes, error handling, observability, export, opening import, document storage, production config, seed/demo templates, DR | **Partially present** (S7 backup/restore rehearsal, migration replay, two-tenant RLS). Remaining hardening to complete. |
| R13 | Full Company Simulation: RE + Ag + Livestock portfolios, full money/asset/valuation/sale/loss/close cycle, every pound traceable | **Not delivered as one scenario.** This is the R13 gate and the hard-stop proof. |

## 4. Hard stop at R13

After R13 is delivered, do not start portfolio/investor-economics expansion that depends on an OPEN item in `docs/OPEN_BUSINESS_DECISIONS.md` until the owner resolves it. This does not block independent sector work, security/data-integrity fixes, or other bounded product work.

## 5. R14 — Target Company Investment Policy Pack (asked of the owner)

Only after R13, ask the owner the 13 questions only they/their contracts can answer (details in `docs/greenfield/08`, section 16). Several require reading the real contract and legal/accounting documents, not just oral replies. Resolving the matching `BD-00x` IDs in `docs/OPEN_BUSINESS_DECISIONS.md` is the definition of done for R14.

## 6. R15–R17 — small rule-dependent tail

- **R15 — Agreements & Participation:** reflect the real contract; capital commitments, contributions, economic participation, profit/loss allocation, operator economics, reserves, reinvestment.
- **R16 — Distribution & Investor Statements:** distribution payable, approval, payment, investor ledger, statements.
- **R17 — Final Company UAT:** enter real data and reconcile against the company's own accounts.

## 7. Execution discipline

- One bounded vertical slice at a time; each from a fresh branch off current `origin/main`, zero commits behind, full changed-layer verification.
- The hard stop at R13 is not a reason to delay R4/R10/R12/R13 — those are independent and are exactly what "Build Everything Independent First" means.
- Never present synthetic fixtures as customer/UAT/production/commercial evidence.
