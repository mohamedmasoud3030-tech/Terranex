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

The independent build is complete through R13 on the PR #149 CI-proved head. This mapping reconciles the historical slice labels (S0–S7, GF-###, ADR 00xx) to the new R-phases. A delivered slice may implement part of one phase; phase status below is based on repository behavior and permanent gates, not slice names. Deployed/customer acceptance remains a separate real-world evidence boundary.

| R | Independent capability | Repository state |
|---|---|---|
| R1 | Production Foundation: org, memberships, party registry, roles/capabilities, RLS, audit, maker/checker, documents/evidence, idempotency, exact money, periods, notifications foundation, Arabic/RTL | **COMPLETE.** S0–S2/S6/S7 and the shared core provide organization/project identity, membership isolation, exact money, audit, close/correction, evidence and Arabic/RTL foundations; repository-wide replay and security gates protect the contract. |
| R2 | Portfolio + Project + Asset core, many independent Projects in one Portfolio | **COMPLETE for canonical independent scope.** Portfolio identity/lifecycle/current-parent/history/workspace are delivered. Sector assets remain authoritative Project-bounded roots; ADR 0032/R8 supplies the read projection, not a mutable Asset super-table. Project `RiskItem`, risk resolution and immutable `DecisionRecord` now have canonical RPC-backed Arabic UI, evidence references and current-Portfolio read projection. Existing typed evidence/document contracts remain authoritative rather than being duplicated. |
| R3 | Complete financial control: budget, forecast, commitment, obligation, accrual, expense, revenue, receivable, payable, payment, receipt, cash, bank, reconciliation, subledger, reversal/repost, period close, portfolio roll-up | **Independent core delivered.** S2–S6 plus F3–F10 provide budget versions, commitment/obligation control, FAC, approval/exception control, exact double-entry postings, bank reconciliation, reversal/repost, close and historical Portfolio roll-up. Deferred only where an OPEN business decision controls investor/legal economics. |
| R4 | Procurement & Shared Operations: suppliers, purchase requests/orders, receiving, invoices, payments, contracts, attachments, approvals, inventory concepts, counterparties | **COMPLETE for currently authorized flows.** GF-025/GF-026 + ADR 0030/0031 deliver procure-to-pay, receiving, supplier invoice/payable/payment/bank chain, contracts/evidence, approvals, exact partial ceilings, idempotency and tenant isolation. `docs/R4_CLOSEOUT_AUDIT.md` is the authoritative closeout and finds no additional shared inventory-value concept required. Agriculture/livestock quantity inventories stay sector-owned; COGS/harvest/biological valuation and WMS are not fabricated without policy. |
| R5 | Real Estate (complete independent scope) | **COMPLETE.** S0–S7 and GF-010/GF-011 cover acquisition/hold/valuation/disposal. Rental recognition → receivable → partial collection → bank reconciliation now has exact-money database and Arabic operator UI proof, without property-management-suite expansion. |
| R6 | Livestock (complete independent scope) | **COMPLETE.** GF-020–GF-024 plus R13 same-Portfolio multi-project operational/governance/financial isolation proof. |
| R7 | Agriculture (complete independent scope) | **COMPLETE.** GF-013–GF-019 plus R13 integrated Portfolio attribution and historical reassignment proof. |
| R8 | Cross-sector asset & performance layer | **Delivered as a read projection** (ADR 0032). `cross_sector_asset_register_read` unions the sector-owned asset roots and `sector_performance_read` gives per-sector Project financial position, surfaced at `/assets`. No base Asset table or write command exists. Absent facts use typed status reasons, never fabricated zeros. |
| R9 | Management UX (Home, Portfolios, Projects, Assets, RE, Ag, Livestock, Money, Procurement, Documents, Approvals, Reports, Settings; Arabic/RTL + mobile/tablet/desktop) | **COMPLETE for independent scope.** Executive Home, Portfolio/project drill-down, assets, governance and sector/finance workspaces are Arabic/RTL, tenant-safe and FX-honest. |
| R10 | Investor Transparency (read-models only, no invented rights): identity, secure login, party documents, updates, photos/evidence, activity, published reports, notices, statements framework, as-of date, valuation basis, data freshness — with entitlement-dependent fields inert | **COMPLETE for safe scope / POLICY BLOCKED beyond it.** Identity, provenance and recorded funding facts remain available with explicit non-entitlement wording. Permanent characterization tests prevent allocation/distribution/ownership economics from reappearing before R14. |
| R11 | Reporting & Control | **COMPLETE.** Project/sector/Portfolio/Organization read models, FAC, financial position, close, integrity, exceptions, governance and exact reconciliation are present and R13-proved. |
| R12 | Production Hardening: backups/restore, migration replay, RLS/security, concurrency, idempotency, invariants, audit, indexes, error handling, observability, export, opening import, document storage, production config, seed/demo templates, DR | **COMPLETE for independent technical scope.** Migration replay, authenticated two-tenant RLS, repository-wide SECDEF ACL scan, concurrency/idempotency/invariant gates, opening import, backup/restore rehearsal, deployment/config and private document controls pass. Live deployment/customer/restore acceptance remains **REAL-WORLD EVIDENCE BLOCKED**, not synthesized. |
| R13 | Full Company Simulation: RE + Ag + Livestock portfolios, full money/asset/valuation/sale/loss/close cycle, every unit of money traceable | **COMPLETE.** Final gate `95_r13_full_company_scenario.sql` composes gates 01–94 into المجموعة العربية المتحدة, including a hostile tenant, two Livestock Projects in one Portfolio, historical reassignment, non-zero posted rental facts, and exact Project→Portfolio→Organization differences of zero. See `docs/R13_FULL_COMPANY_EXECUTION_REPORT.md`. |

## 4. Hard stop at R13

After R13 is delivered, do not start portfolio/investor-economics expansion that depends on an OPEN item in `docs/OPEN_BUSINESS_DECISIONS.md` until the owner resolves it. This does not block independent sector work, security/data-integrity fixes, or other bounded product work.

## 5. R14 — Target Company Investment Policy Pack (asked of the owner)

Only after R13, ask the owner the questions only they/their contracts can answer (details in `docs/greenfield/08` and `docs/OPEN_BUSINESS_DECISIONS.md`). Several require reading the real contract and legal/accounting documents, not just oral replies. Resolving the matching `BD-00x` IDs is the definition of done for R14.

**R14 progress (2026-08-16):** the owner-facing Arabic questionnaire is issued as `docs/R14_TARGET_COMPANY_DECISION_PACK_AR.md` and the technical mapping/dormant-code audit as `docs/R14_POLICY_IMPACT_MATRIX.md`. BD-001…BD-012 all remain OPEN until the authorized owner's answers are recorded.

**Post-R14 policy-safety hotfix — MERGED / CLOSED (2026-08-16):** the mandatory policy-safety hotfix required by the R14 impact matrix (§4.2/§4.3) was merged via PR #151. It de-surfaces the intake ownership/allocation configuration leak and removes the readiness dependency without resolving any BD item or inferring owner-specific policy; the dormant S5 machinery remains dormant. R14 documentation work and its mandatory safety closeout are complete. The exact next gate is **PRE-OWNER INDEPENDENT EVIDENCE AUDIT** (independent evidence and owner-decision validation, not implementation); R15 has not started and remains blocked for policy-dependent scope.

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
