# Terranex — R14 Policy Impact Matrix & Legacy Investor-Economics Audit

**Status:** R14 documentation deliverable — no runtime, migration, or behavior change
**Date:** 2026-08-16
**Base:** `main@0ce489bb83822477a19412d871362118ddd996eb` (post PR #149, R13 complete)
**Companion:** `docs/R14_TARGET_COMPANY_DECISION_PACK_AR.md` (owner-facing Arabic questionnaire)
**Register of record:** `docs/OPEN_BUSINESS_DECISIONS.md` — every BD item below remains **OPEN**

## 1. Scope and rules of this document

R14 is business-policy discovery for the target company **المجموعة العربية المتحدة**. This document:

- maps each BD-001…BD-012 decision to the affected domain, existing tables/functions, blocked R15–R17 functionality, and required professional review;
- audits dormant legacy investor-economics implementation and classifies its reuse potential;
- records professional-consistency flags against the R1–R13 baseline.

It does **not** resolve any decision, choose any alternative, enable any dormant code, add migrations, or change runtime behavior. Existing code, old migrations, synthetic fixtures, UI labels, demo percentages, industry convention, and AI recommendations are *not* evidence of company policy (`AGENTS.md`, anti-hallucination rules; `docs/OPEN_BUSINESS_DECISIONS.md` §5).

## 2. Per-decision analysis

Each entry follows the mandated structure: unresolved question → why software cannot infer it → known R1–R13 facts → resolving evidence → alternatives and consequences → features each answer would authorize → professional review. No option is chosen on the company's behalf.

### BD-001 — Portfolio legal/economic status

- **Unresolved:** whether `InvestmentPortfolio` is a management grouping only, or corresponds to a legal entity, SPV, fund, or contractual pooled vehicle.
- **Why not inferable:** legal/entity structure is a fact of company registration and contracts. Nothing in code, naming, or grouping behavior can prove it; inferring it would fabricate a legal boundary (`AGENTS.md` non-negotiable boundary).
- **Known R1–R13 facts:** Portfolio is implemented strictly as a management/reporting parent (R1 Portfolio Foundation, ADR 0025): `DRAFT|ACTIVE|ARCHIVED` lifecycle, one current parent per Project, append-only membership history, roll-ups derived from Project truth with zero-difference reconciliation proven by gate 95. No Portfolio ledger, capital, or obligations exist.
- **Resolving evidence:** commercial register / articles of incorporation / SPV or fund documentation / pooled-investment contract — or the owner's explicit statement that no such structure exists.
- **Alternatives & consequences:** (a) management grouping only → current model stands unchanged; (b) legal entity/SPV/fund/pooled contract → Portfolio would acquire its own accounting boundary, ownership, contracts, tax profile and reporting; this **contradicts the current independent-Project accounting model** and would require an approved later design/migration, not a reinterpretation.
- **Would authorize (if answered):** R15 agreement scoping at the correct level; R16 statement issuer identity; any future portfolio-entity accounting design (only under a new approved ADR).
- **Review:** legal — yes (unless "management only"); accounting — yes (unless "management only").

### BD-002 — Who funds Projects

- **Unresolved:** the actual capital sources: operating company cash, named investors/partners, project-specific investors, shareholder/current accounts, equity, debt, or a mixture.
- **Why not inferable:** cash movements prove amounts and dates, not the legal capacity in which money arrived. The exact-money model records facts; classification of the source is a business/legal fact.
- **Known R1–R13 facts:** the Finance Core posts cash, obligations, receivables/payables, and reconciles bank statements exactly. S1 (`parties`, `project_participants`, `investment_agreements`, `agreement_versions`, `commitment_terms`, `capital_calls`, `capital_call_lines`, `contributions`) can record investor identity, commitments, calls and contributions where such facts exist — recording never implies ownership or entitlement (ADR 0003).
- **Resolving evidence:** investor contracts, loan agreements, capital-increase minutes, shareholder current-account statements.
- **Alternatives & consequences:** company-cash-only → no external claims arise; investor/partner sources → each participant, amount and contract must be recorded per agreement; current-account funding → creates recorded company↔partner indebtedness; debt → creates lender obligations without profit rights unless contracted; mixed → per-project source documentation required.
- **Would authorize:** R15 funding-source classification on posted funding facts; correct capital vs liability vs current-account treatment.
- **Review:** accounting — yes; legal — yes where external investors/lenders exist.

### BD-003 — Investor participation level

- **Unresolved:** Project-level vs Portfolio-level vs both; whether one investor can hold different terms in different Projects.
- **Why not inferable:** participation scope is defined by the actual contract. The discovery source (docs/TARGET_COMPANY_REFERENCE.md) mentions sector portfolios and multi-project diversification but explicitly does not establish participation level.
- **Known R1–R13 facts:** S1 participation is Project-scoped; Portfolio has no investor membership model; R10 exposes identity/agreement transparency only with entitlement surfaces inert (enforced by `tests/r10-policy-block.test.ts`).
- **Resolving evidence:** the real investment contract template or executed examples.
- **Alternatives & consequences:** Project-level → matches current technical shape; Portfolio-level → implies combining results of several Projects for one investor, which does not exist today and interacts directly with BD-011 (no pooling/netting by implication); both → each agreement must declare its scope; per-project differing terms → terms are recorded per agreement, never generalized.
- **Would authorize:** R15 participation scoping; R16 statement scope.
- **Review:** legal — yes; accounting — yes if Portfolio-level participation exists.

### BD-004 — Meaning of ownership

- **Unresolved:** the legal/economic meaning of "ownership": company shares, partnership interest, Project contractual interest, profit-sharing right, capital-account units, direct asset ownership, another basis, or combinations.
- **Why not inferable:** a percentage number is meaningless without its legal basis; the alternatives are materially different instruments with different rights, risks and reporting. Contribution amount does not imply ownership (`AGENTS.md`).
- **Known R1–R13 facts:** no generic ownership-percentage field is active anywhere. S1 deliberately separates commitment / call / contribution / ownership / balances. The dormant S5 rule basis stores documented weights only against an activated agreement version and never infers them from cash (ADR 0008).
- **Resolving evidence:** articles of incorporation, shareholder/partner register, contract template, asset title deeds.
- **Alternatives & consequences:** each basis changes who legally holds what, whether losses attach, whether the interest is transferable, and how statements must read. Combinations require case-by-case documentation.
- **Would authorize:** R15 ownership/interest schema with the correct legal semantics and effective-dating; ownership-based reporting.
- **Review:** legal — yes (primary); accounting — yes.

### BD-005 — Project funding mechanism

- **Unresolved:** which mechanisms actually exist: operating-company deployment, shareholder/current-account funding, equity, capital contribution, capital call, loan, intercompany funding, other; and which may coexist.
- **Why not inferable:** the posting treatment (equity vs liability vs current account vs memorandum) depends on the mechanism's legal form, not on the cash amount.
- **Known R1–R13 facts:** S1 implements commitment→call→contribution mechanics with idempotency, concurrency safety and exact rollforward — as a *mechanism*, policy-inert. The Finance Core separates portfolio capital deployment from investor contribution by contract (greenfield 05 §8).
- **Resolving evidence:** actual funding contracts, capital-call notices used in practice, current-account ledgers.
- **Alternatives & consequences:** direct company spend → no third-party claim; current account → recorded partner debt; contribution/call → S1 mechanics become usable as company policy; loan/intercompany → interest/repayment schedule and cost bearer must be defined.
- **Would authorize:** R15 funding workflows bound to the confirmed mechanisms; correct posting-rule selection per mechanism.
- **Review:** accounting — yes; legal — yes for loans/intercompany.

### BD-006 — Profit and loss assignment (critical)

- **Unresolved:** the rule assigning realized Project profit/loss to participants. Explicitly **not inferable** from commitment, contribution, ownership, investment amount, or current capital balance.
- **Why not inferable:** real agreements frequently allocate on a basis different from cash ratios (fixed schedules, operator participation, asymmetric loss rules). Any default silently redistributes other people's money. `docs/greenfield/05` §9 defines the engine as a mechanism for an *already-approved* rule only.
- **Known R1–R13 facts:** dormant S5 supports `PRO_RATA` and `FIXED_SHARES` against a documented, immutable, evidence-referenced rule set with deterministic largest-remainder rounding and DB-side recomputation at approval (ADR 0008). It allocates `REALIZED_RESULT` only. No rule set is authorized for the target company; R10 keeps all entitlement surfaces inert.
- **Resolving evidence:** the signed contract or signed percentage schedule. Oral statements alone are insufficient for contracted percentages.
- **Alternatives & consequences:** ownership-based (requires BD-004 first); funding-ratio (requires the measurement date/basis rule); fixed contractual shares (clearest operationally; must trace to a signed schedule); per-project agreement (each Project's rule recorded separately); operator participation (ties into BD-009); another documented rule. Loss rule may differ from profit rule and must be asked separately.
- **Would authorize:** R15 allocation policy activation per agreement; R16 partner result statements.
- **Review:** accounting — yes; legal — yes.

### BD-007 — Unrealized valuation treatment

- **Unresolved:** whether approved unrealized valuations are management information only, accounting-recognized, allocable, distributable, or never distributable before realization.
- **Why not inferable:** valuation ≠ cash profit; distributing unrealized gains is a real solvency risk and its permissibility is an accounting/legal matter.
- **Known R1–R13 facts:** approved valuations exist in Real Estate (and sector performance reads) strictly as separately labeled facts; R11/R13 reporting distinguishes realized results from approved valuations; nothing valuation-based feeds allocation or distribution.
- **Resolving evidence:** written accounting policy; any contract clause referencing valuation-based rights.
- **Alternatives & consequences:** management-info-only → current behavior stands; recognition where permitted → accountant must specify the standard/treatment; allocable/distributable → requires contractual text, accounting approval, and an explicit markdown/clawback answer for later valuation declines.
- **Would authorize:** R15/R16 valuation-linked entitlement or disclosure behavior only per the explicit policy.
- **Review:** accounting — yes (any option beyond management-info); legal — yes if contracts grant valuation-linked rights.

### BD-008 — Distributable cash

- **Unresolved:** the company's actual rule for cash that may be distributed: treatment of unrestricted cash, supplier payables, committed obligations, retention, taxes, debt service, reserves, minimum operating liquidity, future committed expenditure, loss carryforward, unpaid Project liabilities, other restrictions. Terranex will not invent the formula.
- **Why not inferable:** a bank balance proves cash, not distributability; the deductions/reserves are business policy.
- **Known R1–R13 facts:** dormant S5 contains a conservative capacity *mechanism* (`s5_project_distributable_cash_internal`, `s5_distribution_capacity_read`) and an approval→payable→payment chain that never pays from a dashboard number. That mechanism's inputs are not the company's rule and must not be presented as one.
- **Resolving evidence:** written distribution policy or worked examples of actual past distributions with their computation.
- **Alternatives & consequences:** each deduction/reserve element the owner confirms becomes an explicit input; per-Project computation is consistent with the current isolation model; any cross-project element triggers BD-011.
- **Would authorize:** R16 distribution-availability computation and approval workflow per the confirmed formula.
- **Review:** accounting — yes (mandatory); legal — yes where contracts define distribution rules.

### BD-009 — Operator / management economics

- **Unresolved:** existence and form of management fees, operator fees, carried interest, promoter share, performance fees, acquisition fees, asset-management fees — or none. For each applicable item: contractual basis, calculation basis, timing, accounting treatment, tax treatment, Project/Portfolio scope.
- **Why not inferable:** the discovery source indicates operator alignment with investor success but no formula (docs/TARGET_COMPANY_REFERENCE.md §1.7). Greenfield 05 §9 explicitly defers carried interest, hurdles, catch-up and waterfalls.
- **Known R1–R13 facts:** no fee/carry computation exists anywhere in delivered scope; S5 supports an operator share only as an explicit documented rule-set participant, never as a default.
- **Resolving evidence:** fee clauses in contracts, or a documented management decision stating the formula.
- **Alternatives & consequences:** none → the company earns only as an investor/owner per BD-004/BD-006; any fee/carry → expense vs allocation treatment changes both investor economics and Project cost truth and must be specified per item.
- **Would authorize:** R15 operator-economics rules; R16 fee lines on statements.
- **Review:** accounting — yes; legal — yes.

### BD-010 — Tax / withholding

- **Unresolved:** what Terranex must record, calculate, withhold, report, or defer to external tax/accounting systems, per applicable tax type.
- **Why not inferable:** tax rules are jurisdiction/company-specific; building them from guesses is prohibited.
- **Known R1–R13 facts:** semantic account roles include a tax/withholding clearing concept as taxonomy only; no tax computation exists. The statutory GL remains external (greenfield 05 §1).
- **Resolving evidence:** accountant's statement of applicable taxes and current computation responsibility.
- **Alternatives & consequences:** record-only / calculate / withhold / report-only / fully external — each defines a strictly bounded system role per tax type; withholding interacts with BD-008/R16 payment amounts.
- **Would authorize:** R16 recording or withholding steps in the distribution chain, exactly as scoped.
- **Review:** accounting/tax — yes (mandatory); legal — case-dependent.

### BD-011 — Cross-project movement (critical)

- **Unresolved:** whether money may move between Projects at all; if yes, the actual mechanism (inter-project loan, due-to/from, company current account, capital transfer, repayment, temporary advance, other); and separately whether profits may be netted, losses netted, cash pooled, or one Project's obligations settled by another.
- **Why not inferable:** Project isolation is the load-bearing guarantee of the whole R1–R13 accounting model; implicit pooling would corrupt both Projects' truth.
- **Known R1–R13 facts:** no cross-project transfer, pooling, netting or recycling exists. Gate 95 proves exact per-Project attribution with zero roll-up differences. The account taxonomy reserves an `inter-project due-to/from` control role (taxonomy only — no active behavior).
- **Resolving evidence:** examples of actual historical inter-project transfers and their bookkeeping; contract clauses permitting/prohibiting movement.
- **Alternatives & consequences:** never → current model stands (cleanest); documented mechanism → each movement is posted in its legal capacity, preserving both Projects' truth; any "yes" to netting/pooling → **explicit flag: changes the independent-Project accounting model and requires a later approved migration/design; it will not be activated implicitly.**
- **Would authorize:** R15/R16 inter-project transaction types strictly per the confirmed mechanism.
- **Review:** accounting — yes for any movement; legal — yes where investor rights are affected.

### BD-012 — Investor lifecycle

- **Unresolved:** rules for new investor entry, additional investment, partial withdrawal, full exit, interest transfer, sale/assignment, funding default, death/succession, legal-identity change, contractual notices, statements/certificates, and approvals.
- **Why not inferable:** these are contractual terms; Terranex must not invent transfer mechanics (S1 deliberately froze participant sets under an activated version rather than guessing amendment carry-forward — ADR 0003).
- **Known R1–R13 facts:** S1 has no amendment/supersession workflow by design; R10 provides identity/document transparency only; no exit/transfer/valuation-at-entry mechanics exist.
- **Resolving evidence:** entry/exit/transfer/succession clauses in the contract template; documented management rules.
- **Alternatives & consequences:** for each event: contractual rule (attach text) / fixed management rule (record it) / undefined (remains OPEN; no workflow is built). Entry/exit valuation interacts with BD-004/BD-007.
- **Would authorize:** R15 agreement amendment/supersession workflows; R16 notices/statements/certificates; lifecycle approvals.
- **Review:** legal — yes (primary); accounting — yes for valuation/withdrawal events.

## 3. Compact impact matrix

| BD | Affected domain | Existing tables/functions/surfaces touched by a future answer | Blocked R15/R16/R17 functionality | Accounting review | Legal review | Status |
|---|---|---|---|---|---|---|
| BD-001 | Portfolio semantics | `investment_portfolios`, `investment_portfolio_state_history`, `portfolio_project_assignments`, F10 roll-up reads; no Portfolio ledger exists | Portfolio-entity semantics; statement issuer identity | If not "management only" | If not "management only" | **OPEN** |
| BD-002 | Funding source | `parties`, `project_participants`, `contributions`, cash/bank postings | R15 funding-source classification | Yes | If external investors/lenders | **OPEN** |
| BD-003 | Participation scope | `project_participants`, `agreement_versions`; R10 investor surface | R15 participation scoping; R16 statement scope | If Portfolio-level | Yes | **OPEN** |
| BD-004 | Ownership meaning | (none active) dormant `s5_allocation_rule_basis`; S1 concept separation | R15 ownership schema; ownership reporting | Yes | Yes (primary) | **OPEN** |
| BD-005 | Funding mechanism | `commitment_terms`, `capital_calls`, `capital_call_lines`, `contributions`, posting rules | R15 funding workflows per mechanism | Yes | For loans/intercompany | **OPEN** |
| BD-006 | P&L assignment | dormant `s5_allocation_rule_sets/rules/runs/lines`, `s5_configure_allocation_rules`, `s5_prepare/approve_allocation` | R15 allocation activation; R16 result statements | Yes | Yes | **OPEN** |
| BD-007 | Unrealized valuation | RE valuation facts; `sector_performance_read`; R11 reporting labels | Valuation-linked entitlement/disclosure | Yes (beyond mgmt-info) | If contracted | **OPEN** |
| BD-008 | Distributable cash | dormant `s5_project_distributable_cash_internal`, `s5_distribution_capacity_read`, `s5_distributions`, `s5_distribution_payments` | R16 distribution availability & approval | Yes (mandatory) | If contracted | **OPEN** |
| BD-009 | Operator economics | (none active) S5 rule-set participant mechanics | R15 fees/carry; R16 fee statement lines | Yes | Yes | **OPEN** |
| BD-010 | Tax/withholding | semantic account taxonomy (tax clearing role, inert) | R16 tax recording/withholding steps | Yes (mandatory) | Case-dependent | **OPEN** |
| BD-011 | Cross-project movement | none active; taxonomy reserves inter-project due-to/from role | R15/R16 inter-project transactions; any netting/pooling redesign | Yes (any movement) | If investor rights affected | **OPEN** |
| BD-012 | Investor lifecycle | S1 frozen-version design; R10 identity/document reads | R15 amendment/supersession; R16 notices/certificates | For valuation/withdrawal | Yes (primary) | **OPEN** |

**No BD item is RESOLVED.** Resolution requires the explicit recorded owner decision per `docs/OPEN_BUSINESS_DECISIONS.md` §5 (scope, effective date, evidence, required professional review).

## 4. Legacy investor-economics audit (dormant code inventory)

Classification legend: **SAFE-INFRA** = safe historical infrastructure; **REUSABLE-AFTER-POLICY** = potentially reusable after the mapped BD decisions; **CONTRADICTS-BOUNDARY** = contradicts the current policy boundary as-currently-surfaced; **DEPRECATED** = should not be reactivated. Nothing was deleted, enabled, or modified in R14.

| Artifact | Location | What it does | Classification | Gating decisions |
|---|---|---|---|---|
| S1 terms & funding schema (`parties`, `project_participants`, `investment_agreements`, `agreement_versions`, `commitment_terms`, `capital_calls`, `capital_call_lines`, `contributions`) + RPCs (`create_party`, `add_project_participant`, `create_agreement_draft`, `activate_agreement_version`, `create_capital_call`, `record_contribution`) | `supabase/migrations/20260810000200_s1_terms_and_funding.sql`, `src/features/funding/*` | Records identity, commitments, calls, contributions as facts; concept-separated by design; no entitlement inference | **SAFE-INFRA** (recording) / **REUSABLE-AFTER-POLICY** (as company funding workflow) | BD-002, BD-003, BD-005 |
| `partner_capital_position`, `project_capital_position` read views | same migration | Exact commitment/called/contributed rollforward projections | **SAFE-INFRA** — facts only; must never be labeled ownership/entitlement | BD-004, BD-006 |
| S5 allocation rule sets/rules + basis (`s5_allocation_rule_sets`, `s5_allocation_rules`, `s5_allocation_rule_basis`, `s5_configure_allocation_rules`) | `20260812000100`, `20260812000125/130/135` | Immutable, evidence-referenced, effective-dated weight schedules (`PRO_RATA`/`FIXED_SHARES`) tied to an activated agreement version | **REUSABLE-AFTER-POLICY** — a correct mechanism for executing an approved rule; no rule is approved for the target company | BD-004, BD-006 |
| S5 allocation runs/lines (`s5_allocation_runs`, `s5_allocation_lines`, `s5_prepare_allocation`, `s5_approve_allocation`, `s5_realized_result_as_of_snapshot`) | `20260812000100` | Deterministic largest-remainder allocation of `REALIZED_RESULT` from a closed-period snapshot; DB recomputation at approval | **REUSABLE-AFTER-POLICY** | BD-006 (plus BD-003/004 scope) |
| S5 distributions & payments (`s5_distributions`, `s5_distribution_payments`, `s5_prepare/approve/pay_distribution`) | `20260812000100` | Approval→payable→payment chain; no payment from dashboard numbers | **REUSABLE-AFTER-POLICY** | BD-008 (formula), BD-010 (withholding) |
| Distribution capacity (`s5_project_distributable_cash_internal`, `s5_distribution_capacity_read`) | `20260812000100`, `20260812000115` | Conservative capacity computation mechanism | **REUSABLE-AFTER-POLICY** — its inputs are *not* the company formula; must be re-derived from the BD-008 answer, not presented as a default | BD-008 |
| Partner capital statement (`s5_partner_capital_balance_internal`, `s5_partner_capital_statement_read`) | `20260812000100` | Reproducible partner-capital statement projection | **REUSABLE-AFTER-POLICY** | BD-004, BD-006, BD-012 |
| S5 segregation of duties | `20260812000140` | Preparer≠approver enforcement | **SAFE-INFRA** | — |
| Allocation/distribution app layer (`src/features/allocation/{actions,queries,schema}.ts`) | app code | Thin RPC wrappers/read types over S5 | **REUSABLE-AFTER-POLICY**; not linked from the investor surface (enforced by `tests/r10-policy-block.test.ts`) — but see the intake boundary defect below: `queries.ts` is imported by the live intake route | BD-006, BD-008 |
| `/projects/[id]/statements` page | app code | Redirects to the safe R10 investors surface; renders no economics | **SAFE-INFRA** (policy-block conformant) | — |
| `/projects/[id]/investors` page | app code | Identity/agreement transparency with explicit Policy-Blocked wording; no entitlement runtime | **SAFE-INFRA** (R10-conformant) | — |
| **Connected intake boundary defect (three legs — see §4.1)**: (A) `ConfigureRulesForm` exposure, (B) allocation-rule query/readiness data dependency, (C) mandatory ownership/allocation-weight readiness semantics | `src/app/(app)/projects/[projectId]/intake/page.tsx`, `src/features/intake/readiness.ts` | S7-era pilot intake keeps live S5 rule configuration reachable and makes canonical project readiness depend on — and mandate — policy-blocked ownership/allocation weights | **CONTRADICTS-BOUNDARY AS SURFACED** — the underlying S5 mechanism remains REUSABLE-AFTER-POLICY, but the current runtime surfacing is a live policy leak, broader than one form. Flagged only; **no runtime change made in PR #150** — corrected by the required post-R14 policy-safety hotfix (§4.2) | BD-004, BD-006 |
| `AgreementDraftForm` and commitment recording (`terms/forms.tsx`, DS05 readiness) | app code | Records participant identity, agreement/version provenance, and explicit contractual **commitment amounts** (`commitmentAmount`); DS05 wording keeps «الالتزام ≠ المطلوب ≠ المساهمة» | **SAFE-INFRA** — a recorded commitment is a historical/business fact and is not represented as ownership, entitlement, allocation weight, profit share, or distributable percentage; must stay that way | BD-002, BD-005 (facts only) |
| `DS15_DISTRIBUTIONS` opening-balance section (`readiness.ts`) | app code | Records pre-existing approved-but-unpaid distributions as opening payable facts | **SAFE-INFRA** — records historical facts; creates no new entitlement | — |
| `tests/s5-allocation-distribution.test.ts`, gate SQL for S5 | tests | Characterize the dormant mechanism's correctness | **SAFE-INFRA** — keeps the mechanism honest without authorizing it | — |
| `docs/runbooks/FAILED_ALLOCATION_OR_DISTRIBUTION.md` | runbook | Operational recovery procedure for the dormant chain | **SAFE-INFRA** | — |
| ADR 0008 (S5) historical authorization | `docs/decisions/0008_S5_ALLOCATION_AND_DISTRIBUTION.md` | Authorized the *mechanism* in the historical slice sequence | **SAFE-INFRA** as history; it is not target-company policy evidence | BD-006, BD-008 |

**Nothing classified DEPRECATED requires action in R14; no artifact was found that must be deleted now.** The CONTRADICTS-BOUNDARY finding is a **connected three-leg live policy leak** (detailed in §4.1), not a single surfaced form and not a data-corruption risk: the S5 command chain still requires an activated governing agreement version and documented evidence references, and R10 permanent tests keep entitlement output off the investor surface. However, the intake route currently exposes rule configuration and mandates policy-blocked semantics, so a policy-safety runtime hotfix (§4.2) is required after PR #150 merges.

### 4.1 Corrected finding — the connected intake boundary defect (verified against `main@0ce489bb` runtime)

The R14 audit initially recorded only the `ConfigureRulesForm` exposure. Independent verification shows the leak is broader: **three connected legs in the live intake surface**, all violating the R10/R14 boundary while BD-004 (meaning of ownership) and BD-006 (profit/loss assignment) remain OPEN.

**Leg A — live configuration surface.** `/projects/[projectId]/intake` imports `ConfigureRulesForm` (from `../investors/forms`) and renders it whenever an active governing agreement version exists and no allocation rule set exists (`{!activeRuleSet && <ConfigureRulesForm …/>}`, gated only by `disabled={!isOwner}`). This exposes live S5 allocation-rule configuration — the transcription of ownership/allocation weights — on a reachable operator route before any owner decision exists for the target company.

**Leg B — readiness data dependency.** The same page calls `getAllocationRuleSets(projectId)` (`src/features/allocation/queries.ts`), derives `activeRuleSet` for the active governing version, and passes `allocationRulesConfigured: Boolean(activeRuleSet)` into `buildIntakeSnapshot`. Policy-dependent allocation configuration therefore feeds the canonical intake-readiness model: project readiness *state* depends on whether policy-blocked weights have been configured.

**Leg C — readiness semantics.** `src/features/intake/readiness.ts` treats the policy-dependent semantics as **MANDATORY** in section `DS04_AGREEMENT`: it instructs «فعّل نسخة اتفاقية حاكمة … وأوزان ملكية مجموعها 100٪» (activate a governing version with *ownership weights totaling 100%*), reports «أوزان الملكية/التخصيص غير مثبتة على 100٪» while unconfigured, holds the agreement `IN_PROGRESS` until weights exist, and marks it `COMPLETE` only with «أوزان الملكية مثبتة». Because DS04 is MANDATORY, unconfigured weights flow into `mandatoryMissing` and degrade the phase-2 readiness verdict — the software effectively *requires* an ownership/allocation basis that BD-004/BD-006 say cannot yet exist.

**Classification:** the current runtime behavior of these three legs together is **CONTRADICTS-BOUNDARY AS SURFACED**, mapped to **BD-004 and BD-006**. BD-003 is *not* implicated: the exposure is strictly Project-scoped (rule sets bind to one project's governing version); no Portfolio-level participation semantics are involved, and the mapping is not broadened without evidence.

**Safe distinction (verified, must be preserved):** the agreement/funding flow itself is *not* unsafe. `AgreementDraftForm` records participant identity, agreement/version provenance, and explicit contractual **commitment amounts** — historical/business facts. DS05 readiness wording preserves the separation («الالتزام ≠ المطلوب ≠ المساهمة»). SAFE: participant identity; agreement/version provenance; explicit commitment amounts; funding facts. POLICY BLOCKED: ownership weights; allocation weights; profit/loss assignment; distribution percentages; distributable-cash economics.

### 4.2 Required post-R14 corrective action (policy-safety hotfix — NOT part of PR #150)

After PR #150 merges, a separate **policy-safety-only** runtime PR is required. It must **not** resolve any BD decision, must not add or drop S5 database machinery, and must not touch allocation mechanics beyond de-surfacing. Expected safe direction:

1. remove `ConfigureRulesForm` from every live R10/R14-blocked route (including `/projects/[id]/intake`);
2. remove the intake page's `getAllocationRuleSets` dependency so project readiness no longer reads allocation-rule configuration;
3. rework `DS04_AGREEMENT` readiness semantics and wording so no ownership/allocation percentage is required, implied mandatory, or shown as a 100% completion condition while BD-004/BD-006 are OPEN — replacing it with an explicit policy-blocked status, not a silent pass;
4. preserve participant identity, agreement/version provenance, and commitment-fact recording exactly as they are (SAFE list above);
5. preserve the dormant S5 database machinery untouched as historical mechanism, without presenting it as authorized current policy;
6. add permanent characterization tests (see §4.3) so the leak cannot regress.

### 4.3 Strengthened permanent policy-test plan (binding on the hotfix)

The hotfix must extend `tests/r10-policy-block.test.ts` (or equivalent permanent tests) beyond the `/investors` route. While BD-004 and BD-006 remain OPEN the tests must prove:

- the intake route does not import or render `ConfigureRulesForm`;
- the intake route does not query allocation rules (`getAllocationRuleSets`/`features/allocation`) for readiness;
- readiness does not require ownership weights;
- readiness does not require allocation weights;
- no "ownership/allocation must total 100%" requirement is shown anywhere;
- commitments remain distinguishable from ownership/entitlement (DS05-style wording preserved);
- dormant S5 mechanics are not accidentally exposed on any other live route.

### 4.4 MERGED / CLOSED — post-R14 policy-safety hotfix

**Status:** merged via PR #151 (final head `215a3c0e4de31600d6d9ad8931758a50690d988f`, `main` merge commit `b5854e5f80a1fdc152400d8839319c6ecadd4bbd`) with the policy-safety correction, permanent tests, and truthful status-doc updates. This subsection is an addendum; the audit body above remains historical evidence of the finding.

- The three-leg intake leak (§4.1) is corrected. `/projects/[projectId]/intake` no longer imports or renders `ConfigureRulesForm`, no longer queries allocation rules (`getAllocationRuleSets` / `features/allocation`), no longer derives an `activeRuleSet`, and no longer passes `allocationRulesConfigured` into the readiness snapshot. Project readiness no longer reads S5 allocation configuration.
- `DS04_AGREEMENT` no longer requires or implies ownership/allocation weights, a 100% total, or profit/loss assignment. It completes on safe agreement facts (active governing version, effective date, title/reference) and states the unresolved ownership/allocation/distribution policy explicitly as «غير محددة بسياسة معتمدة» — policy-blocked, not silently passed, and not a readiness gate.
- SAFE agreement/funding facts are preserved: participant identity, agreement/version provenance, `AgreementDraftForm` and its explicit `commitmentAmount`, capital-call/contribution facts, and the DS05 separation «الالتزام ≠ المطلوب ≠ المساهمة».
- Dormant S5 machinery (migrations, RPCs, read views, `src/features/allocation/*`, the dormant S5 forms) is untouched and remains dormant; it is not presented as target-company policy.
- Permanent regression coverage was extended: `tests/r10-policy-block.test.ts` (seven policy-boundary proofs, including a repository-wide runtime-source scan with an explicit dormant allowlist that catches indirect live exposure) and `tests/intake-readiness.test.ts` (behavioral scenarios A/B/C).
- No BD item was resolved: BD-001…BD-012 remain OPEN. No migration or schema change was introduced. R15 was not started.

### 4.5 Pre-owner policy-safety boundary (corrective engineering)

**Status:** delivered via ADR 0033 and migration `20260816062000_pre_owner_policy_safety.sql`.
This supersedes the "S5 dormant" characterization: the S5 mechanism is
**retained but policy-inert**. Policy-dependent writes fail closed until an
approved `policy_authority` exists (which none does, so the current state is
inert). It also de-couples intake from mandatory investor/agreement/commitment,
raises S1 activation/call to OWNER, read-labels the stale S5 result source, relabels
the capacity bridge, and reconciles S5 distribution payments through the shared
bank-line reservation. No BD is resolved; R15 is not started.

## 5. Professional consistency review — flags

Cross-checked against the Terranex accounting model, Project financial isolation, exact-money model, close/reversal/correction architecture, Portfolio reporting architecture, RE/Agriculture/Livestock operations, current funding facts, and the R10 policy block:

1. **Portfolio-pooled accounting (BD-001/BD-003/BD-011):** any owner answer implying Portfolio-level pooled accounting, investor pooling, or profit/loss netting **changes the current independent-Project accounting model** and requires a later approved migration/design plus accounting sign-off. The Arabic pack states this to the owner in plain language; it is not implementable by reinterpretation.
2. **Distribution capacity mechanism vs company formula (BD-008):** the dormant `s5_distribution_capacity_read` embeds mechanism-level conservatism from the historical slice. When BD-008 is answered, the formula must be rebuilt from the owner's confirmed elements — the existing view must not be presented as the company rule.
3. **Connected intake boundary defect (BD-004/BD-006):** see §4.1 — a three-leg live policy leak (ConfigureRulesForm exposure, allocation-rule readiness dependency, mandatory ownership/allocation-weight readiness semantics), classified CONTRADICTS-BOUNDARY AS SURFACED. Documented here with the required post-merge policy-safety hotfix defined in §4.2 and the permanent test plan in §4.3; runtime correction is deliberately **not** included in the R14 documentation PR.
4. **"13 questions" vs 12 BD IDs:** `AGENTS.md` and `docs/greenfield/08` speak of "13 business-policy questions" while the canonical register holds BD-001…BD-012. The 13 narrative questions map onto the 12 register IDs (the asset-legal-owner question folds into BD-004, reinvestment into BD-008/BD-012 scope). The register is canonical; no renumbering was done in R14.
5. **S5 source scope (BD-006/BD-007):** dormant S5 allocates `REALIZED_RESULT` only, which is consistent with the valuation boundary (BD-007). If the owner ever authorizes valuation-linked entitlement, that is a new design decision — not an extension of the existing run category by implication.
6. **No contradiction found** between R13-proven behavior and the decision pack: every question keeps Project isolation, exact money, close/correction and roll-up-as-projection invariants intact until an explicit answer says otherwise.

## 6. R14 end-state statement

- R1–R13 behavior untouched; no runtime, migration, schema, RPC, UI, or test behavior changed.
- Deliverables are documentation only: this matrix, the Arabic owner decision pack, and status-register cross-references.
- BD-001…BD-012: **all OPEN — awaiting the authorized owner of المجموعة العربية المتحدة.**
- One verified runtime policy-boundary defect is on record (§4.1) with a mandatory follow-up **policy-safety hotfix** (§4.2/§4.3). That hotfix is **MERGED / CLOSED** via PR #151 (§4.4): it removes the surfacing and the readiness dependency only and resolves no BD decision.
- R14 documentation work and the mandatory post-R14 safety closeout are complete; no owner-specific policy was inferred.
- The exact next gate is **PRE-OWNER INDEPENDENT EVIDENCE AUDIT** (independent evidence and owner-decision validation, not implementation). R15 is not started and must not start for any scope whose correctness depends on an OPEN item.