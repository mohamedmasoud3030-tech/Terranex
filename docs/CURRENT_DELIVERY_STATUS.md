# Terranex — Current Delivery Status

**Status snapshot:** 2026-08-15  
**Canonical runtime base at snapshot:** `main@decd927525433d6e92662f0070ed10ee54b97278`  
**Roadmap authority:** `docs/ROADMAP_R0_R17.md`  
**Target-company evidence:** `docs/TARGET_COMPANY_REFERENCE.md`  
**Strategy:** Build Everything Independent First

This document is an execution/status snapshot. It does not replace the eight Greenfield contracts, the canonical roadmap, the open-business-decision register, or accepted ADRs.

## 1. Merge/branch closeout completed in this cycle

- PR #139 — R1 Portfolio Foundation: **MERGED** first as the canonical Portfolio runtime foundation.
- PR #140 — parallel Procurement branch: **CLOSED as superseded after all valid work was salvaged**.
- PR #137 — stale R0 follow-up: **CLOSED as superseded after its useful Product Charter correction was salvaged**.
- PR #141 — no-loss reconciliation + Procurement foundation/Receiving + correctness hardening: **MERGED**.
- All open Pull Requests in the repository at this snapshot: **none**.

PR #141 also carries the final correctness fixes reviewed before merge:

- replay-safe submit/approve idempotency;
- source Purchase Request same-organization/same-project/APPROVED coherence;
- command-boundary delivery-date validation instead of a volatile table CHECK;
- complete PO request fingerprint including expected delivery date;
- header/line project-coherence composite foreign keys;
- receipt/order-line structural coherence;
- receipt concurrency serialization and response-loss replay ordering;
- authenticated read-view grants and real RLS verification;
- final receipt-header `(purchase_order_id, project_id, organization_id)` coherence;
- NULL-safe request-hash replay comparisons using `IS DISTINCT FROM`;
- regression proof for malformed/null replay payloads.

## 2. R0–R17 delivery map

| Phase | Current status | What is already delivered | What remains before the phase can be considered complete for the current roadmap |
|---|---|---|---|
| R0 — Canonical Realignment | **COMPLETE / MERGED** | Portfolio ≠ Project ≠ Asset ≠ Legal Vehicle ≠ Operating Cycle; anti-hallucination governance; R0–R17 roadmap; open-decision register. | No runtime work. Maintain consistency only. |
| R1 — Production Foundation | **SUBSTANTIALLY COMPLETE** | Organization/membership/auth, RLS, audit, maker-checker patterns, exact money, periods/close/reversal foundations, Arabic/RTL shell, idempotency patterns. | Remaining production-hardening items are completed under R12 rather than reopening R1. |
| R2 — Portfolio + Project + Asset Core | **PARTIAL** | R1 Portfolio Foundation merged: Portfolio identity/lifecycle, one current parent Portfolio per Project, history, Arabic workspace. Existing sector assets/projects remain authoritative. | Shared Asset core/associations, portfolio documents/decisions/risks/budget relationships, authoritative Portfolio roll-up read models. |
| R3 — Complete Financial Control | **SUBSTANTIALLY COMPLETE** | Finance Core already has obligations, cash, receivables/revenue, payment/reconciliation, balanced postings, period close, reversal/repost, allocation/distribution mechanics for already-authorized rules. | Shared budget/forecast/commitment completion, Portfolio roll-up, and any missing AP/operational-finance links. Investor entitlement remains excluded until R14+. |
| R4 — Procurement & Shared Operations | **PROCURE-TO-PAY + CONTRACTS/EVIDENCE DELIVERED** | Organization-scoped Suppliers linked to Party; commercial POs and unposted commitments; Receiving; receipt-matched Supplier Invoices; Finance Core payable/payment/reconciliation; private versioned PO/contract/receipt/invoice files with typed Project/tenant links, SHA-256, append-only metadata/audit, signed reads and approval evidence gates; Arabic/RTL management path. | Only the separately bounded shared inventory-value concepts required by working flows, then R4 closeout audit. R4 is not marked complete while those remain. |
| R5 — Real Estate | **AUTHORIZED TECHNICAL PATH IMPLEMENTED** | Acquisition/control, development, cost/revenue, valuation separation, disposition, result/close surfaces from S0–S7/GF-010/GF-011. | Target-company gap: basic investment holding/rental-income flow and consolidated owner-facing investment performance. Do not expand into a full property-management suite. |
| R6 — Livestock | **AUTHORIZED TECHNICAL PATH IMPLEMENTED** | GF-020–GF-024 livestock operational foundation and subsequent hardening. | Target-company validation/simulation of multiple livestock projects in one Portfolio, plus any shared Procurement/Finance integrations exposed by the R13 scenario. |
| R7 — Agriculture | **AUTHORIZED TECHNICAL PATH IMPLEMENTED** | GF-013–GF-019 agriculture chain through land/farm/field/cycle, inputs, harvest/inventory, sale/revenue, profitability/closeout. | Target-company simulation and shared Procurement/Finance integration; do not create a second sector procurement/finance core. |
| R8 — Cross-sector Asset & Performance | **PARTIAL** | Sector and Finance read models exist. | One owner-facing layer for asset position, project result, sector result, approved valuation, realized/unrealized distinction, and exceptions. |
| R9 — Management UX | **LARGELY PRESENT** | Arabic/RTL sector workspaces, Portfolio workspace, Procurement workspace, project shell and operating pages. | Executive Home, consolidated Portfolios/Projects/Assets/Money/Approvals/Documents/Reports/Settings experience; mobile/tablet/desktop closeout. |
| R10 — Investor Transparency (safe/read-only portion) | **NOT DELIVERED AS A DEDICATED SLICE** | Supporting evidence/doc/audit primitives already exist. | Secure investor-facing projections for published updates, evidence, project/portfolio activity, as-of date, valuation basis, data freshness and statements framework. Entitlement-dependent numbers remain inert. |
| R11 — Reporting & Control | **PARTIAL / SUBSTANTIAL COMPONENTS PRESENT** | Project finance/sector read models, close controls, audit and reconciliation evidence. | Consolidated owner reports, cross-sector/Portfolio drill-down, exception reporting and traceability views. |
| R12 — Production Hardening | **PARTIAL** | Migration replay, two-tenant RLS suites, backup/restore rehearsal, concurrency/idempotency/invariant tests, pilot runbooks. | Complete observability/error handling/index review/export/opening import/document storage/production config/DR evidence and current deployment verification. |
| R13 — Full Company Simulation | **NOT YET DELIVERED** | Underlying sector/finance components mostly exist. | One integrated synthetic scenario covering Real Estate + Agriculture + Livestock, multiple Projects inside Portfolio(s), purchases, obligations, receipts, cash, revenue, valuation, sales, losses, closeout and full drill-down. This is the hard-stop gate. |
| R14 — Target Company Policy Pack | **DECISION PACK ISSUED — AWAITING OWNER ANSWERS** | The full owner questionnaire (`docs/R14_TARGET_COMPANY_DECISION_PACK_AR.md`) and technical impact matrix/legacy audit (`docs/R14_POLICY_IMPACT_MATRIX.md`) are delivered for BD-001…BD-012. | Obtain the authorized owner's explicit answers plus actual legal/accounting evidence where required, and record each resolution in `docs/OPEN_BUSINESS_DECISIONS.md`. All twelve items remain OPEN. |
| R15 — Agreements & Participation | **WAITING ON R14** | Existing mechanics may be reusable only after policy validation. | Implement the real participation/funding/ownership/result-allocation/operator-economics rules of the target company. |
| R16 — Distribution & Investor Statements | **WAITING ON R14/R15** | Shared distribution/payment mechanics exist for already-authorized historical scope. | Target-company investor ledger/statements/distribution policy based on verified rules. |
| R17 — Final Company UAT | **WAITING ON R14–R16** | Technical rehearsal infrastructure exists. | Enter real company data, reconcile against company records, owner/operator UAT and acceptance. |

## 3. Execution order from this snapshot

Do not restart completed sector construction and do not wait for the owner prematurely. The preferred sequence is:

1. **R4 remaining shared operations** — Contracts & Evidence Closure is implemented under ADR 0031; next is only the bounded shared inventory-value concepts required by authorized working flows, followed by the R4 closeout audit.
2. **R2/R3 remaining shared core gaps** — Asset relationships, budget/forecast/commitment and Portfolio roll-ups only where not already authoritative.
3. **R5 target-company Real Estate gap** — basic holding/rental income + investment performance, without full property management.
4. **R8/R9/R11 owner-management layer** — cross-sector asset/performance, executive UX, consolidated drill-down reporting.
5. **R10 safe Investor Transparency** — published progress/evidence/read models without guessed entitlement.
6. **R12 production hardening closeout**.
7. **R13 full-company simulation** against the target-company operating model.
8. **STOP and obtain R14 policy pack** from the target-company owner/contracts/accounting/legal evidence.
9. R15 → R16 → R17 only after the relevant decisions are resolved.

## 4. Target-company focus

The first target-company working name supplied by the product owner is **المجموعة العربية المتحدة**. The implementation priority is therefore not a generic feature checklist; it is to prove the operating model described in the owner-provided source material:

`Portfolio → multiple financially separate Projects → sector operations/assets → purchases/cost/revenue/cash → project result → Portfolio management roll-up → evidence/transparency`

The product must support Real Estate, Agriculture and Livestock through one shared investment/finance/control core while preserving sector-specific operational truth.

For the livestock diversification case described by the company, the R13 simulation must include at least one Portfolio with multiple independent Projects and prove that a gain/loss in one Project never destroys the separate accounts of another Project.

For the Real Estate strategy described by the company, the independent build must prove acquisition, holding cost, **basic rental income**, approved valuation separated from realized profit, and disposal.

For the transparency promise described by the company, management/investor-facing read models must be able to publish purchases, spend, progress, documents/photos/evidence and financial/project status without fabricating ownership or entitlement.

See `docs/TARGET_COMPANY_REFERENCE.md` for the exact evidence boundary and what remains unresolved.

## 5. Hard-stop rule remains unchanged

No target-company ownership, entitlement, operator-share, cross-project netting/recycling, reserve, tax, investor exit/transfer or distribution formula may be invented before R14.

The system should be as complete as possible before that conversation. The only work that waits is work whose correctness genuinely depends on the owner's verified policy/legal/accounting facts.

## 6. Addendum — F3–F10 execution session (2026-08-16, branch `arena/01a00890-terranex`)

This addendum updates the delivery map above without rewriting the dated snapshot.

| Phase | Update |
|---|---|
| R2 | Portfolio roll-up read models are now delivered (`portfolio_financial_rollup_read`, F10). Remaining: shared Asset core/associations and portfolio documents/decisions/risks. |
| R3 | Shared budget/forecast/commitment control is now delivered as an additive layer (F4 budgets with ceiling enforcement at obligation authorization, consumption/forecast read models). Remaining: any missing AP/operational-finance links. Investor entitlement remains excluded until R14+. |
| R8 | Cross-sector performance now has the authoritative `project_financial_position_read` + `project_performance_read` (F9), the Financial Integrity Center signal surface (F8) and org/portfolio consolidation (F10). Remaining: owner-facing asset-position/valuation surface. |
| R11 | Exception reporting and traceability are now delivered: unified `approval_exception_registry_read` (F5), `financial_integrity_signals_read` (F8), `organization_financial_consolidation_read` (F10). Remaining: consolidated owner reports polish. |
| R13 | The two blockers named by the previous status ("needs budget completion and portfolio roll-up") are now delivered. The full-company simulation is the next logical increment and the hard-stop gate. |

Phase-level evidence: `docs/F3_F10_EXECUTION_REPORT.md`, `docs/F7_PERIOD_CLOSE_AUDIT.md`, migrations `20260816050000_f3_contract_finance.sql` … `20260816058200_f3_f10_pgcrypto_compat_final.sql`, behavioral gate `supabase/tests/88_f3_f10_finance_control.sql`, concurrency gate `supabase/tests/90_f3_f10_budget_concurrency.sh`, unit tests `tests/f3-f10-control.test.ts`.

### Review round (2026-08-16, later the same day)

An independent audit found P0/P1 defects in the first F3–F10 delivery (reversal netting, budget-ceiling concurrency, revision-gap ceiling loss, currency mixing in exceptions, unusable schedules, idempotency-key reuse, hardcoded EGP/OMR, broken FX form, VOID inconsistency, F7 counters, invented F8 signal, non-historical F10) plus scope gaps (FAC definition, tiered approvals, reject/resubmit, exception actionability, roll-up scope). All were fixed with regression coverage (`docs/F3_F10_EXECUTION_REPORT.md` § Review defects).

## 7. Final R1–R13 closeout addendum (2026-08-16, PR #149)

This addendum supersedes stale phase labels in the dated snapshot above. It is based on the complete PR #149 app and PostgreSQL CI, including final gate `supabase/tests/95_r13_full_company_scenario.sql`.

| Phase | Final status | Evidence boundary |
|---|---|---|
| R1 | **COMPLETE** | Production foundation, exact money, RLS, audit, periods, reversal and idempotency gates. |
| R2 | **COMPLETE** | Portfolio/Project hierarchy plus canonical project RiskItem and immutable DecisionRecord command/read UI. Sector asset roots remain authoritative; a universal Asset table is intentionally not authorized. |
| R3 | **COMPLETE** | Independent finance-control scope, budgets, commitments, approvals, reconciliation, F9/F10 roll-ups. Investor economics excluded. |
| R4 | **COMPLETE** | Procurement, receiving, invoice/payment/evidence path complete; closeout correctly rejects a speculative generic inventory-value subsystem. |
| R5 | **COMPLETE** | Real Estate lifecycle and rental recognition → receivable → collection → bank reconciliation operator workflow. |
| R6 | **COMPLETE** | Livestock technical scope and same-Portfolio multi-project isolation proved. |
| R7 | **COMPLETE** | Agriculture technical scope and integrated Portfolio attribution proved. |
| R8 | **COMPLETE** | Cross-sector read projection without a universal asset base table; gross-result semantics remain explicit. |
| R9 | **COMPLETE** | Tenant-safe, FX-honest Executive Home and shared Arabic/RTL project navigation. |
| R10 | **COMPLETE (safe scope)** | Identity/provenance/funding facts only; policy-dependent investor economics remain blocked and characterized by permanent tests. |
| R11 | **COMPLETE** | Exact Project → Portfolio → Organization reporting/reconciliation and traceability read models. |
| R12 | **COMPLETE (independent technical scope)** | Full replay, RLS/ACL scanners, concurrency, idempotency, opening-import, backup/restore rehearsal, config/runtime and document controls. Claims requiring a live target deployment or customer evidence remain **REAL-WORLD EVIDENCE BLOCKED**. |
| R13 | **COMPLETE** | Final executable company gate passed PostgreSQL CI; non-zero revenue/cash/receivable differences are exactly zero and hostile tenant visibility is zero. See `docs/R13_FULL_COMPANY_EXECUTION_REPORT.md`. |
| R14 | **DECISION PACK ISSUED — AWAITING OWNER ANSWERS** | BD-001…BD-012 remain OPEN. The Arabic owner questionnaire (`docs/R14_TARGET_COMPANY_DECISION_PACK_AR.md`) and the impact matrix/legacy investor-economics audit (`docs/R14_POLICY_IMPACT_MATRIX.md`) are documentation-only deliverables; no runtime or migration behavior changed. The audit records one verified runtime policy-boundary defect: the intake route surfaces S5 allocation-rule configuration and makes mandatory readiness depend on ownership/allocation weights while BD-004/BD-006 are OPEN (three connected legs — see impact matrix §4.1). A separate **policy-safety-only** runtime hotfix (impact matrix §4.2/§4.3) is required after the R14 documentation PR merges; it must not resolve any BD decision. |

The hard stop is now active. No ownership percentage, investor entitlement, allocation policy, distributable cash, distribution, waterfall, carried/operator economics, cross-project netting or investor entry/exit economics may be activated until the relevant R14 decisions and evidence are resolved.

## 8. Post-R14 policy-safety hotfix — MERGED / CLOSED (2026-08-16)

The mandatory post-R14 §4.2/§4.3 policy-safety hotfix (see `docs/R14_POLICY_IMPACT_MATRIX.md`) is **MERGED / CLOSED** via PR #151 (final head `215a3c0e4de31600d6d9ad8931758a50690d988f`, merged on `main` as `b5854e5f80a1fdc152400d8839319c6ecadd4bbd`). R14 documentation work and its mandatory policy-safety closeout are complete. The hotfix closes the three-leg intake policy leak while BD-004 and BD-006 remain OPEN:

- `/projects/[projectId]/intake` no longer imports or renders `ConfigureRulesForm`, no longer queries allocation rules for readiness, and no longer passes an `allocationRulesConfigured` flag into the readiness model.
- `DS04_AGREEMENT` readiness no longer requires or implies ownership/allocation weights or a 100% total; unresolved investor economics are shown as policy-blocked («غير محددة بسياسة معتمدة») without degrading readiness.
- SAFE agreement/funding facts (participant identity, agreement/version provenance, `AgreementDraftForm` commitment amounts, capital-call/contribution facts, the DS05 separation) are preserved.
- Dormant S5 allocation/distribution machinery is untouched and remains dormant.
- BD-001…BD-012 remain OPEN; no business policy was inferred. R15 has not started.

Permanent regression coverage was added in `tests/r10-policy-block.test.ts` (seven policy-boundary proofs) and `tests/intake-readiness.test.ts` (behavioral scenarios A/B/C). No database migration or schema change was required.

No owner answer was recorded and no owner-specific policy was inferred. The exact next gate is **PRE-OWNER INDEPENDENT EVIDENCE AUDIT**: independent evidence and owner-decision validation only, not implementation. R15 has not started and remains blocked for every policy-dependent scope. This closeout does not begin that audit.

## 9. Pre-owner policy-safety boundary — corrective engineering (2026-08-16)

The independent pre-owner evidence audit (`docs/PRE_OWNER_POLICY_AUDIT.md`) found
that several investor/funding/allocation/distribution mechanisms remained
policy-reachable while BD-001…BD-012 are OPEN. The corrective engineering pass
(ADR 0033, migration `20260816062000_pre_owner_policy_safety.sql`) delivered the
policy-safety boundary:

- S5 allocation/distribution writes and the `attach_contribution_cash` posting
  fail closed with `target-company investor policy is not activated` until an
  approved `policy_authority` exists (the registry ships **EMPTY**);
- S1 agreement activation and capital-call issuance require OWNER;
- intake readiness no longer mandates investor + agreement + commitment;
- the stale S5 RE-sale-only source (`s5_realized_result_as_of_snapshot`) is
  truthfully read-labeled (COMMENT + terminology matrix) and the capacity bridge
  is relabeled `technical_capacity_bridge_minor_units`;
- S5 distribution payments reconcile through the shared bank-line reservation;
- pilot/control readiness no longer exposes partner-capital or investor-statement values.

S5 is therefore **retained but policy-inert**, not "dormant". BD-001…BD-012 remain
OPEN; R15 has not started; no target-company economics were invented.
