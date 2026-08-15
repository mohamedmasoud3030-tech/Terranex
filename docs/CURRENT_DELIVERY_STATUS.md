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
| R4 — Procurement & Shared Operations | **OPERATIONAL FOUNDATION MERGED** | Organization-scoped Suppliers; Project-scoped Purchase Requests/Orders; maker-checker; Receiving; quantity truth; RLS/audit/idempotency; Arabic/RTL workspace; concurrency and coherence guards. | **Next active product gate:** PO commercial terms/pricing/currency → commitment/obligation → supplier invoice → payable → payment → reconciliation; contracts/attachments and only the shared inventory concepts actually required by working flows. |
| R5 — Real Estate | **AUTHORIZED TECHNICAL PATH IMPLEMENTED** | Acquisition/control, development, cost/revenue, valuation separation, disposition, result/close surfaces from S0–S7/GF-010/GF-011. | Target-company gap: basic investment holding/rental-income flow and consolidated owner-facing investment performance. Do not expand into a full property-management suite. |
| R6 — Livestock | **AUTHORIZED TECHNICAL PATH IMPLEMENTED** | GF-020–GF-024 livestock operational foundation and subsequent hardening. | Target-company validation/simulation of multiple livestock projects in one Portfolio, plus any shared Procurement/Finance integrations exposed by the R13 scenario. |
| R7 — Agriculture | **AUTHORIZED TECHNICAL PATH IMPLEMENTED** | GF-013–GF-019 agriculture chain through land/farm/field/cycle, inputs, harvest/inventory, sale/revenue, profitability/closeout. | Target-company simulation and shared Procurement/Finance integration; do not create a second sector procurement/finance core. |
| R8 — Cross-sector Asset & Performance | **PARTIAL** | Sector and Finance read models exist. | One owner-facing layer for asset position, project result, sector result, approved valuation, realized/unrealized distinction, and exceptions. |
| R9 — Management UX | **LARGELY PRESENT** | Arabic/RTL sector workspaces, Portfolio workspace, Procurement workspace, project shell and operating pages. | Executive Home, consolidated Portfolios/Projects/Assets/Money/Approvals/Documents/Reports/Settings experience; mobile/tablet/desktop closeout. |
| R10 — Investor Transparency (safe/read-only portion) | **NOT DELIVERED AS A DEDICATED SLICE** | Supporting evidence/doc/audit primitives already exist. | Secure investor-facing projections for published updates, evidence, project/portfolio activity, as-of date, valuation basis, data freshness and statements framework. Entitlement-dependent numbers remain inert. |
| R11 — Reporting & Control | **PARTIAL / SUBSTANTIAL COMPONENTS PRESENT** | Project finance/sector read models, close controls, audit and reconciliation evidence. | Consolidated owner reports, cross-sector/Portfolio drill-down, exception reporting and traceability views. |
| R12 — Production Hardening | **PARTIAL** | Migration replay, two-tenant RLS suites, backup/restore rehearsal, concurrency/idempotency/invariant tests, pilot runbooks. | Complete observability/error handling/index review/export/opening import/document storage/production config/DR evidence and current deployment verification. |
| R13 — Full Company Simulation | **NOT YET DELIVERED** | Underlying sector/finance components mostly exist. | One integrated synthetic scenario covering Real Estate + Agriculture + Livestock, multiple Projects inside Portfolio(s), purchases, obligations, receipts, cash, revenue, valuation, sales, losses, closeout and full drill-down. This is the hard-stop gate. |
| R14 — Target Company Policy Pack | **BLOCKED UNTIL R13** | Questions are registered as BD-001…BD-012. | Obtain owner answers plus actual legal/accounting evidence where required. |
| R15 — Agreements & Participation | **WAITING ON R14** | Existing mechanics may be reusable only after policy validation. | Implement the real participation/funding/ownership/result-allocation/operator-economics rules of the target company. |
| R16 — Distribution & Investor Statements | **WAITING ON R14/R15** | Shared distribution/payment mechanics exist for already-authorized historical scope. | Target-company investor ledger/statements/distribution policy based on verified rules. |
| R17 — Final Company UAT | **WAITING ON R14–R16** | Technical rehearsal infrastructure exists. | Enter real company data, reconcile against company records, owner/operator UAT and acceptance. |

## 3. Execution order from this snapshot

Do not restart completed sector construction and do not wait for the owner prematurely. The preferred sequence is:

1. **R4 Financial Procurement Integration** — finish the real shared procure-to-pay spine.
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
