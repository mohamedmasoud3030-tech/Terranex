# Terranex — Roadmap R0–R17 (Build Everything Independent First)

**Status:** Canonical delivery roadmap  
**Effective:** 2026-08-16  
**Controlling strategy:** *Complete every feature whose correctness does not depend on unresolved legal/economic policy. Defer only the smallest rule-dependent portion.*  
**Canonical reference:** referenced by `AGENTS.md`, `GREENFIELD_EXECUTION.md`, `docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md`, `docs/OPEN_BUSINESS_DECISIONS.md`.

## 1. The governing principle

The previous plan placed the hard stop at R5, which risked asking the company owner for business-policy answers while the product was still incomplete. This roadmap moves the hard stop to **R13**. We build everything that is independent of the owner's investor/legal/economic answers to the end (R1–R13), and only then ask the owner for a small, well-scoped **policy pack** (R14). After the policy is fixed we finish the small rule-dependent tail (R15–R17).

Deferral rule: even a feature that is 90% independent and 10% rule-dependent is built **now** up to its independent 90%. Only the rule-dependent portion waits. Never invent a default, a fake percentage, an `OTHER` enum, a generic rules engine, or a guessed entitlement rule to avoid the stop. Never display an investor profit/entitlement number computed from an unapproved basis.

## 2. R0 — Canonical Realignment (merged)

`Portfolio ≠ Project ≠ Asset ≠ Legal Vehicle ≠ Operating Cycle`. The AI is forbidden from inventing Investor Economics. This is governance-only and merged at the R0 commit.

## 3. R1–R13 independent build — state against this repository

The independent build is largely already delivered by the existing technical history. This mapping reconciles the historical slice labels (S0–S7, GF-###, ADR 00xx) to the new R-phases. A delivered slice may implement part of one phase; phase status below is based on repository behavior and permanent gates, not slice names.

| R | Independent capability | Repository state |
|---|---|---|
| R1 | Production Foundation: org, memberships, party registry, roles/capabilities, RLS, audit, maker/checker, documents/evidence, idempotency, exact money, periods, notifications foundation, Arabic/RTL | **Substantially present.** S0–S2/S6/S7 and the shared core provide organization/project identity, membership isolation, exact money, audit, close/correction and evidence foundations. Project-generic document management remains part of the R2/R12 closeout rather than a reason to invent a second document subsystem. |
| R2 | Portfolio + Project + Asset core, many independent Projects in one Portfolio | **PARTIAL, canonical interpretation corrected.** Portfolio identity/lifecycle/current-parent/history/workspace are delivered. Sector assets remain authoritative Project-bounded roots; `docs/greenfield/03_DOMAIN_MODEL.md` does not define a universal shared Asset aggregate, and ADR 0032/R8 supplies the cross-sector read projection. Therefore a new mutable Asset super-table is **not** an R2 requirement. PR #148 adds the canonical Project `RiskItem` / immutable `DecisionRecord` capability and current-Portfolio read projections. Remaining bounded R2 work is project-generic Documents/evidence linkage and management UI closeout, subject to CI. Budgets and financial roll-ups are already delivered by F3–F10. |
| R3 | Complete financial control: budget, forecast, commitment, obligation, accrual, expense, revenue, receivable, payable, payment, receipt, cash, bank, reconciliation, subledger, reversal/repost, period close, portfolio roll-up | **Independent core delivered.** S2–S6 plus F3–F10 provide budget versions, commitment/obligation control, FAC, approval/exception control, exact double-entry postings, bank reconciliation, reversal/repost, close and historical Portfolio roll-up. Deferred only where an OPEN business decision controls investor/legal economics. |
| R4 | Procurement & Shared Operations: suppliers, purchase requests/orders, receiving, invoices, payments, contracts, attachments, approvals, inventory concepts, counterparties | **COMPLETE for currently authorized flows.** GF-025/GF-026 + ADR 0030/0031 deliver procure-to-pay, receiving, supplier invoice/payable/payment/bank chain, contracts/evidence, approvals, exact partial ceilings, idempotency and tenant isolation. `docs/R4_CLOSEOUT_AUDIT.md` is the authoritative closeout and finds no additional shared inventory-value concept required. Agriculture/livestock quantity inventories stay sector-owned; COGS/harvest/biological valuation and WMS are not fabricated without policy. |
| R5 | Real Estate (complete independent scope) | **Independent operating path delivered; rental closeout in PR #148.** S0–S7 and GF-010/GF-011 cover acquisition/hold/valuation/disposal. PR #148 adds basic held-property rental recognition → receivable → partial collection → bank reconciliation through Finance Core, without expanding into a property-management suite. GitHub app and database replay/two-tenant gates are green for the rental slice. |
| R6 | Livestock (complete independent scope) | **Technically implemented.** GF-020–GF-024. Remaining proof is cross-project/shared-finance integration inside R13, not a new livestock ledger. |
| R7 | Agriculture (complete independent scope) | **Technically implemented.** GF-013–GF-019. Remaining proof is cross-project/shared-finance integration inside R13, not a new agriculture ledger. |
| R8 | Cross-sector asset & performance layer | **Delivered as a read projection** (ADR 0032). `cross_sector_asset_register_read` unions the sector-owned asset roots and `sector_performance_read` gives per-sector Project financial position, surfaced at `/assets`. No base Asset table or write command exists. Absent facts use typed status reasons, never fabricated zeros. |
| R9 | Management UX (Home, Portfolios, Projects, Assets, RE, Ag, Livestock, Money, Procurement, Documents, Approvals, Reports, Settings; Arabic/RTL + mobile/tablet/desktop) | **PARTIAL.** Sector workspaces, Portfolio workspace, Procurement and `/assets` are present. Remaining independent work is the consolidated executive Home, governance/documents surfaces, owner reports/settings and responsive closeout. |
| R10 | Investor Transparency (read-models only, no invented rights): identity, secure login, party documents, updates, photos/evidence, activity, published reports, notices, statements framework, as-of date, valuation basis, data freshness — with entitlement-dependent fields inert | **Not delivered as a dedicated slice.** Only safe read-only/publication scaffolding may be built before R14; entitlement, allocation, distribution and investor-profit fields remain inert unless their governing policy is approved. |
| R11 | Reporting & Control | **Substantially present.** Project/sector/Portfolio read models, FAC, financial position, close and integrity controls are present. Remaining work is consolidated owner-facing drill-down, exception/risk visibility and reconciliation UX. |
| R12 | Production Hardening: backups/restore, migration replay, RLS/security, concurrency, idempotency, invariants, audit, indexes, error handling, observability, export, opening import, document storage, production config, seed/demo templates, DR | **PARTIAL.** Migration replay, two-tenant RLS, SECDEF ACL scanning, concurrency/idempotency gates, opening import and backup/restore runbooks exist. Remaining items must be closed from repository evidence before R13; no production-readiness claim may rely on local-only verification. |
| R13 | Full Company Simulation: RE + Ag + Livestock portfolios, full money/asset/valuation/sale/loss/close cycle, every unit of money traceable | **Not yet delivered as one integrated scenario.** This is the hard-stop proof: multiple independent Projects (including multiple Livestock Projects), hostile second tenant, full procurement/finance/sector lifecycle, exact Project→Portfolio→Organization reconciliation, historical attribution, concurrency/idempotency/security and close/reopen evidence. |

## 4. Hard stop at R13

After R13 is delivered, do not start portfolio/investor-economics expansion that depends on an OPEN item in `docs/OPEN_BUSINESS_DECISIONS.md` until the owner resolves it. This does not block independent sector work, security/data-integrity fixes, or other bounded product work.

## 5. R14 — Target Company Investment Policy Pack (asked of the owner)

Only after R13, ask the owner the questions only they/their contracts can answer (details in `docs/greenfield/08` and `docs/OPEN_BUSINESS_DECISIONS.md`). Several require reading the real contract and legal/accounting documents, not just oral replies. Resolving the matching `BD-00x` IDs is the definition of done for R14.

## 6. R15–R17 — small rule-dependent tail

- **R15 — Agreements & Participation:** reflect the real contract; capital commitments, contributions, economic participation, profit/loss allocation, operator economics, reserves, reinvestment.
- **R16 — Distribution & Investor Statements:** distribution payable, approval, payment, investor ledger, statements.
- **R17 — Final Company UAT:** enter real data and reconcile against the company's own accounts.

## 7. Execution discipline

- Work in bounded vertical slices and keep every completion claim tied to permanent repository tests and GitHub CI.
- Preserve already-correct behavior; do not rebuild a domain merely because a roadmap noun exists.
- Portfolio roll-ups are projections over Project truth; sector asset roots stay authoritative.
- Do not create shared inventory valuation, universal Asset activity, pooled economics, cross-project netting, entitlement or distribution rules by implication.
- The hard stop at R13 is not a reason to delay R9/R10-safe/R11/R12/R13 independent work.
- Never present synthetic fixtures as customer/UAT/production/commercial evidence.
