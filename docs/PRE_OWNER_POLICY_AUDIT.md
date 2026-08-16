# Terranex — Pre-Owner Independent Evidence Audit

**Audit date:** 2026-08-16  
**Audited baseline:** `origin/main@350c60b05c839a0a522e92128b3cc87d6fda37d6`  
**Audit type:** adversarial evidence, runtime, database, finance, professional-completeness, and external-authority review  
**Product changes:** none  
**Decision changes:** none — BD-001…BD-012 remain OPEN  
**R15:** not started

> **STOP / NOT READY:** do not send, re-send, or collect answers against `R14_TARGET_COMPANY_DECISION_PACK_AR.md`. The repository does not yet prove that the current twelve-item pack is owner-only, complete, neutral, or technically safe.

## 0. Corrective engineering addendum (2026-08-16)

This audit is canonical for the *findings* it records. The corrective engineering
it mandated (§14) has been delivered in a follow-up policy-safety PR (ADR 0033,
migration `20260816062000_pre_owner_policy_safety.sql`), which:

- gates all S5 allocation/distribution writes and the `attach_contribution_cash`
  posting behind an approved `policy_authority` (EMPTY by default → policy-inert);
- raises S1 agreement activation and capital-call issuance to OWNER authority;
- de-couples intake readiness from mandatory investor + agreement + commitment;
- renames the stale RE-sale-only S5 source (`s5_real_estate_sale_result_as_of_snapshot`,
  source category `REAL_ESTATE_SALE_RESULT`) and relabels the capacity bridge;
- reconciles S5 distribution payments through the shared bank-line reservation;
- removes partner-capital / investor-statement values from pilot/control readiness.

The audit body below remains historical evidence of the findings. No BD item is
resolved; R15 has not started.

## 1. Executive conclusion

# ARE WE REALLY OWNER-BLOCKED? **PARTIAL**

The company-specific legal rights, signed economics, discretionary commercial policy, and management authorities cannot be invented by engineering. There is a genuine owner/company-record dependency. But the repository is **not blocked only on the owner**:

1. many current prompts are document requests or legal/accounting determinations, not owner choices;
2. BD-002 (who/source funds) and BD-005 (the legal/accounting funding mechanism) are distinct but overlapping and dependent; they should share one evidence-intake schedule without merging or deleting either decision;
3. BD-001 (Portfolio legal status), BD-003 (participation scope), and BD-004 (meaning of the interest) are distinct decisions even though one consolidated legal/contract evidence intake can support all three;
4. BD-006, BD-007, BD-008, and BD-009 require separate decisions but their current prompts mix contractual economics, accounting recognition, cash availability, fees, and owner risk appetite;
5. BD-010 must be split: current law, rates, applicability, and accounting treatment belong to tax/accounting/legal professionals; what Terranex should record, calculate, withhold, report, or defer remains a Product/Business decision after that professional schedule exists;
6. the alternatives omit material mechanics that the existing implementation already depends on, including effective dates, amendment precedence, return of capital versus income, overfunding/refunds, recallability/reinvestment, deficit capital, fee offsets, and final closeout;
7. several options are misleading. In particular, a shareholder owns shares, not the company's underlying assets; a capital account is an accounting record rather than a legal ownership instrument; an unrealized fair-value gain can be accounting profit under an applicable policy even though it is not cash; and Portfolio-level participation does not by itself require Project P&L to be collapsed;
8. the supposedly dormant S5 chain has RPC execute grants to `authenticated`, with active-membership checks and selected OWNER/maker-checker gates inside the commands, but no separate BD/policy-activation gate. It is therefore database-executable rather than policy-inert; the permanent demo has executed the governed chain;
9. live intake still requires at least one Project investor, an active Project agreement, and a positive commitment for every investor, even though BD-002/003/005 say those facts are unknown;
10. S5's allocable-result function predates Agriculture, Livestock, and rental revenue and omits them; its distribution-capacity formula is an unapproved historical bridge; and S5 payments have no bank-statement reconciliation path;
11. S5 lacks a typed distribution-purpose and ordering model. Return-of-capital, refund/excess-capital, in-kind, and recallable/reinvestment flows are unsupported rather than proven to be silently classified as the existing allocation-based distribution;
12. live pilot/control views show “partner capital” and “investor statement total” and use partner-capital consistency in technical readiness while the relevant policy is OPEN.

The current pack contains **12 numbered owner items and at least 44 atomic prompts**. This audit preserves **all 12 canonical BD decisions as separate records** and replaces the raw pack with **12 conditional, pre-filled, one-decision-per-item confirmation/approval drafts**. None is ready to send until company documents have been inventoried, accountant and lawyer schedules have been produced, and a corrective engineering PR has made policy-dependent commands and readiness/output truly inert.

## 2. Frozen evidence base

### 2.1 Baseline proof

- `git fetch origin main` resolved `origin/main` to `350c60b05c839a0a522e92128b3cc87d6fda37d6`.
- Audit branch HEAD was the same SHA before this document was created.
- Working tree was clean.
- No baseline merge/rebase was needed.

### 2.2 Canonical documents inspected

The canonical order is declared by `AGENTS.md:10-31`. This audit read the policy-relevant content of:

- `AGENTS.md`;
- `docs/greenfield/01_PRODUCT_CHARTER_AND_MARKET.md` through `08_MVP_AND_DELIVERY_ROADMAP.md`;
- `docs/OPEN_BUSINESS_DECISIONS.md`;
- `GREENFIELD_EXECUTION.md`;
- `docs/ROADMAP_R0_R17.md`;
- `docs/DB_DEVELOPMENT.md`;
- `docs/TARGET_COMPANY_REFERENCE.md`;
- `docs/CURRENT_DELIVERY_STATUS.md`;
- `docs/R13_FULL_COMPANY_EXECUTION_REPORT.md`;
- `docs/R14_TARGET_COMPANY_DECISION_PACK_AR.md`;
- `docs/R14_POLICY_IMPACT_MATRIX.md`;
- the finance/control audit and execution reports relevant to F3–F10, period close, and R4;
- all 32 ADRs under `docs/decisions/`, with detailed review of ADR 0003, 0007, 0008, 0009, 0010, 0025, 0026, 0029, 0030, and 0032;
- policy-relevant pilot-readiness and runbook material.

### 2.3 Current implementation inventory

At the baseline:

| Evidence class | Count | Audit treatment |
|---|---:|---|
| Tracked files | 506 | `git ls-files` inventory |
| Forward SQL migrations | 95 | cumulative schema/RPC behavior inspected; S1/S2/S5/S6/S7/F9/F10/R8/R5 reviewed in detail |
| Distinct created public tables | 159 | static cumulative inventory |
| Distinct created public views | 161 | static cumulative inventory |
| Distinct public function names across migrations | 431 | policy-relevant current overloads/grants traced to their latest definitions |
| SQL/shell database tests | 105 | policy/finance/security gates inspected selectively; no broad replay |
| TypeScript/TSX tests | 43 | policy, intake, S5, and workspace tests inspected and targeted |
| Runtime `page.tsx` routes | 30 | all route names inventoried; policy-relevant pages inspected |
| ADRs | 32 | complete inventory; relevant decisions inspected in detail |

The 30 runtime pages comprise login, executive home, onboarding, assets, intake, portfolio list/new/detail, project new/shell/overview, and Project funding, terms, investors, statements, intake, cash, costs, close, controls, pilot, revenue, operations, budget, integrity, governance, procurement, Agriculture, Livestock, and Livestock operations routes.

The policy-sensitive RPC surface includes:

- S1: `create_party`, `add_project_participant`, `create_agreement_draft`, `activate_agreement_version`, `create_capital_call`, `record_contribution`;
- S2: `attach_contribution_cash`;
- S5: `s5_configure_allocation_rules` (current nine-argument evidence wrapper), `s5_prepare_allocation`, `s5_approve_allocation`, `s5_prepare_distribution`, `s5_approve_distribution`, `s5_pay_distribution`;
- S7/intake: opening capital/distribution mapping, reconciliation checkpoints, acceptance report, and guided-intake declarations.

All are present in the cumulative schema. S1 and S5 execute grants are to `authenticated`, but the grant is only the outer database exposure: the functions enforce active-organization membership; S5 configuration, allocation approval, distribution approval, and distribution payment additionally require OWNER, and maker/checker constraints apply to approvals. The policy defect is not an absence of authorization checks. It is the absence of a separate BD-status/policy-activation gate, leaving the chain database-executable before company policy is approved.

### 2.4 Targeted reproduction and test evidence

The complete suite and DB replay were deliberately not run. The following command completed in **1.20 seconds**, below the five-minute limit:

```text
npm test -- --run \
  tests/r10-policy-block.test.ts \
  tests/intake-readiness.test.ts \
  tests/s5-allocation-distribution.test.ts \
  tests/workspace.test.ts

4 files passed; 83 tests passed.
```

This is diagnostic evidence, not exoneration:

- `tests/intake-readiness.test.ts` positively proves that zero investors blocks DS04 and that investors, an active agreement, and commitments are mandatory;
- `tests/r10-policy-block.test.ts` scans direct TypeScript S5 imports only. It does not inspect database execute grants or indirect S5 dependencies through `s7_pilot_acceptance_report_read`;
- the policy test therefore passes while `/pilot` renders investor-statement totals, `/controls` uses partner-capital consistency, and the S5 RPC chain remains callable;
- `tests/s5-allocation-distribution.test.ts` validates input schemas, not the current cross-sector allocable-result basis or bank reconciliation completeness.

No diagnostic fixture was added. No database replay was necessary to prove the static reachability and formula contradictions.

**PR verification rule:** Greenfield CI completed successfully on the original audit head `078aece77693bc0ec3b8cc3eb79d11d26cb5a87c`. CI evidence is head-specific: every precision revision must be accepted only when the live PR checks are GREEN on that exact head. GitHub's PR check state, not a static status sentence in this document, is the authority; no earlier green result is projected onto a later commit.

## 3. Source-of-truth classification

Every row below has exactly one classification.

| Material proposition | Class | Evidence / reason |
|---|---|---|
| Portfolio is the current product's management/reporting parent; Project is the operational/financial-attribution/close boundary | **A. CANONICAL APPROVED FACT** | Greenfield contracts; ADR 0025; OPEN register baseline |
| Portfolio is not automatically a fund, SPV, legal entity, investor pool, pooled cash account, or second ledger | **A. CANONICAL APPROVED FACT** | `AGENTS.md`; ADR 0025 |
| Commitment, call, contribution, ownership, allocation, distribution payable, payment, and bank reconciliation must be distinct | **A. CANONICAL APPROVED FACT** | `AGENTS.md:55-57`; Greenfield 05 §§2, 8 |
| BD-001…BD-012 are OPEN and no target-company policy is approved | **A. CANONICAL APPROVED FACT** | `OPEN_BUSINESS_DECISIONS.md` |
| The source interview establishes three sectors, multi-project diversification, Project-separated accounts, and investor transparency | **A. CANONICAL APPROVED FACT** | `TARGET_COMPANY_REFERENCE.md` as approved discovery evidence, not legal evidence |
| Portfolio tables contain identity/lifecycle/membership only and no ledger, investor, ownership, capital, reserve, or fee field | **B. IMPLEMENTATION FACT** | `20260815030000_r1_portfolio_foundation.sql` |
| S1 stores only Project-scoped `INVESTOR` participants and one agreement envelope per Project | **B. IMPLEMENTATION FACT** | `20260810000200_s1_terms_and_funding.sql` |
| Any active member can draft and activate that Project agreement and issue calls; S1 activation freezes participants and sets Project lifecycle to `FUNDING` | **B. IMPLEMENTATION FACT** | latest S1 functions in `20260811000100`; no OWNER call |
| When explicitly invoked, OWNER-gated `attach_contribution_cash` posts Dr Bank Cash / Cr Contributed Capital; recording a Contribution alone does not post this journal | **B. IMPLEMENTATION FACT** | `20260811000300_s2_cost_and_cash.sql:643-748` |
| Guided intake treats investors, an active Project agreement, and a positive commitment for each investor as mandatory | **B. IMPLEMENTATION FACT** | `readiness.ts:260-303`; targeted tests |
| S5 RPCs have execute grants to `authenticated`; functions enforce active membership, selected OWNER gates, and maker/checker, and approved steps create journal batches/lines without a separate policy-activation check | **B. IMPLEMENTATION FACT** | execute grants and function bodies in S5 migrations |
| Current S5 allocable result includes only RE sale revenue, RE cost of sale, and mapped selling expense | **B. IMPLEMENTATION FACT** | `s5_realized_result_as_of_snapshot`, lines 478-515 |
| Current S5 “distributable cash” is max(0, cash − positive supplier payable − positive distribution payable) | **B. IMPLEMENTATION FACT** | S5 function/view |
| Current S5 distribution approval and payment are separate journal facts | **B. IMPLEMENTATION FACT** | S5 functions and ADR 0008 |
| Current S5 distribution payment has no shared bank-statement match type or reconciliation RPC | **B. IMPLEMENTATION FACT** | latest match-type constraint permits payment/property sale/rental collection only |
| Pilot and controls render/consume partner-capital and investor-statement values | **B. IMPLEMENTATION FACT** | S7 acceptance view; `/pilot`; `/controls` |
| Egyptian company legal form and registered identity are evidenced by incorporation documents and Commercial Register records | **C. EXTERNAL AUTHORITATIVE FACT** | official GAFI incorporation material; Egypt |
| Liability versus equity classification depends on contractual obligations; balance-sheet offset requires enforceable set-off plus net/simultaneous settlement intent | **C. EXTERNAL AUTHORITATIVE FACT** | IAS 32; applicable IFRS reporting only |
| Joint-arrangement classification depends on rights to assets and obligations for liabilities versus rights to net assets, not merely a label or separate vehicle | **C. EXTERNAL AUTHORITATIVE FACT** | IFRS 11; applicable IFRS reporting only |
| IAS 40 fair-value-model changes are recognized in profit or loss, while IFRS 13 says how to measure fair value and does not decide when it is required | **C. EXTERNAL AUTHORITATIVE FACT** | IAS 40.33/35; IFRS 13.1-5 |
| Cash/cash-equivalent reporting is not a distributability determination | **C. EXTERNAL AUTHORITATIVE FACT** | IAS 7 scope/definitions; no distribution formula |
| Mature private-capital reporting distinguishes transaction purpose, LPA basis, impact on unfunded commitment, recallability, carry/clawback, and inside/outside vehicle | **C. EXTERNAL AUTHORITATIVE FACT** | ILPA 2025 guidance; practice, not Egyptian law or company policy |
| Which management grouping the company wants to call a Terranex Portfolio, where documents leave a management choice | **D. OWNER / CONTRACT FACT** | company-specific management intent |
| Approved commercial reserve appetite, distribution cadence, and internal approvers where law/contracts/accounting leave discretion | **D. OWNER / CONTRACT FACT** | company-specific policy |
| Actual accounting classification of each funding instrument, fee, valuation, loss, distribution, and current-account balance | **E. ACCOUNTING-PROFESSIONAL FACT** | requires qualified accountant using actual books/framework |
| Applicable Egyptian taxes, withholding, rates, exemptions, filing party, and treatment | **E. ACCOUNTING-PROFESSIONAL FACT** | requires current tax professional and taxpayer facts |
| Legal nature of the company/vehicle, investor right, asset title, transfer restriction, succession, and regulatory status | **F. LEGAL-PROFESSIONAL FACT** | requires counsel and documents |
| Every real Project has named Project-level investors, one Project agreement, positive commitments, and capital calls | **G. UNSUPPORTED ASSUMPTION** | contradicted by BD-002/003/005 being OPEN; encoded in intake/S1 |
| Every participant receives a positive share and one 100% schedule governs both profit and loss | **G. UNSUPPORTED ASSUMPTION** | encoded by S5; no company evidence |
| Bank cash less only supplier/distribution payables is the company's distributable cash | **G. UNSUPPORTED ASSUMPTION** | historical S5 formula; BD-008 OPEN |
| A legal/SPV Portfolio necessarily destroys or replaces Project-separated accounting | **G. UNSUPPORTED ASSUMPTION** | legal/reporting entity and Project subledger can coexist; facts decide |
| The permanent demo's 60/40 allocation is target-company policy | **G. UNSUPPORTED ASSUMPTION** | synthetic demo only |
| “S5 is dormant” versus execute grants to `authenticated`, internal membership/selected OWNER/maker-checker gates that still permit the governed chain to post real journals without a policy-activation gate, and a permanently seeded S5 demo | **H. CONFLICT / INCONSISTENCY** | matrix/register versus runtime/database/demo |
| “No investor entitlement number is active” versus pilot investor-statement total and controls partner-capital readiness | **H. CONFLICT / INCONSISTENCY** | investor page/test versus indirect live surfaces |
| “R14 questionnaire issued/awaiting answers” versus this mandatory pre-owner audit and its NOT READY finding | **H. CONFLICT / INCONSISTENCY** | status docs versus current gate |
| “Only owner facts remain” versus document/accountant/lawyer questions and current implementation defects | **H. CONFLICT / INCONSISTENCY** | R14 pack versus this evidence audit |

## 4. Findings by severity

### CRITICAL

**C-01 — The owner pack is not owner-only and must be frozen.**  
The pack asks the owner to determine legal status, accounting recognition, tax applicability, and historical contract facts. Those belong first to company records, counsel, and accountant. Its status says it was formally issued, but no repository evidence records the actual documents, professional reviews, named authorized respondent, or answers.

**C-02 — S5 is not dormant at the database boundary.**  
The S5 RPCs have execute grants to `authenticated`, but their internal checks matter: prepare steps require active membership; configuration, approval, and payment steps use selected OWNER gates; allocation/distribution approvals have maker/checker constraints. Approved commands create real `PARTNER_CAPITAL`, `DISTRIBUTION_PAYABLE`, and bank-cash journal entries. The defect is that none checks BD status or a separate policy-activation record. UI de-surfacing therefore does not make the database chain policy-inert. The permanent demo executed a 60/40 allocation and EGP 3,000,000 distribution through the governed production RPC chain.

**C-03 — Live intake presupposes the answers to BD-002/003/005.**  
DS03, DS04, and DS05 are mandatory: at least one Project `INVESTOR`, an active Project agreement, and a positive commitment for every participant. The readiness verdict cannot progress without them. This excludes company-only funding, debt-only funding, Portfolio-level agreements, investors without commitments, direct contributions, and mixed mechanisms — all offered as unresolved R14 alternatives.

**C-04 — The live S5 allocable result is stale and can produce materially incomplete output.**  
`s5_realized_result_as_of_snapshot` knows only Real Estate sale revenue/cost and selling expense. It ignores rental revenue added later and all Agriculture/Livestock revenue and operating-result models. On those Projects it returns zero or a partial amount, while S5 remains callable and journal-posting. This is an actual correctness defect, not merely a wording issue.

**C-05 — S5 lacks typed distribution purpose and ordering, and its allocation-based ceiling semantics are incomplete.**
Current S5 permits preparation only from a positive approved allocation; it does **not** implement return-of-capital, refund/excess-capital, in-kind, or recallable/reinvestable-capital flows. Within the existing allocation-based flow, the requested amount is checked against total partner capital and the historical cash-capacity bridge rather than explicitly against a typed purpose/order or the triggering allocation line. The proven defect is therefore missing purpose/ordering/ceiling semantics plus an incomplete capacity bridge — not proof that unsupported return-of-capital or refund flows are silently classified as the current distribution.

### HIGH

**H-01 — The separate OWNER-gated S1/S2 cash-attachment command applies an equity classification before BD-005/accounting review.**
Recording a Contribution does not automatically post cash or capital. When an OWNER explicitly invokes `attach_contribution_cash`, however, the command always credits `CONTRIBUTED_CAPITAL`. A receipt that is legally a loan, shareholder current account, refundable advance, or company deployment would be misclassified if the operator selected this attachment/posting flow.

**H-02 — Material S1 authority is too broad for unresolved company policy.**  
Any active organization MEMBER can create Project investors, draft/activate the one governing agreement, freeze participant membership, issue capital calls, and record contributions. S1 has no maker/checker or owner approval for activation/call issuance. Authorization proves technical access, not authority under the company's contract.

**H-03 — Policy-dependent values leak through pilot/readiness surfaces.**  
`/pilot` renders `investor_statement_total_minor_units`; `/controls` includes partner-capital rollforward in “financial integrity”; the acceptance view depends on `s5_partner_capital_statement_read`; the control copy tells OWNER they can approve allocations/distributions “where policy permits,” though the database does not verify that permission. This is reachable and affects real runtime output.

**H-04 — Distribution payment is not bank-reconcilable through the canonical reconciliation domain.**  
S5 payment credits bank cash, but the shared bank-line allocation constraint has no S5 distribution-payment match type and no S5 reconciliation command. A matching bank debit cannot be linked to that payment through the implemented one-line reservation mechanism. “Payment” and “bank reconciliation” are therefore not end-to-end separated and connected for distributions.

**H-05 — BD-006 alternatives do not cover what the implementation would need.**  
S5 supports one all-positive 100% weight schedule over every participant, applied identically to positive and negative realized result. It has no zero/excluded participant, separate profit/loss schedules, category-specific allocation, preferred return, tiers, catch-up, carry/clawback, deficit-account rule, final residual rule, or mid-period segmentation workflow. `PRO_RATA` and `FIXED_SHARES` perform the same weight arithmetic; the label is not a complete policy model.

**H-06 — BD-007 is professionally mis-scoped.**  
The question lets an owner choose whether valuation is “recognized accounting.” That is not a free preference once the reporting framework and asset classification apply. IAS 40 can recognize unrealized fair-value changes in profit or loss; that still does not make the gain cash or distributable. Accounting recognition, contractual allocation, and cash distribution must be three questions owned by different authorities.

**H-07 — Current “realized result” labels are inconsistent.**  
S4 disposition result is revenue less carrying cost less selling costs. F10/R8 “realized result” is revenue less cost of sale and excludes `PROJECT_EXPENSE`; the executive home discloses that limitation, but Portfolio and sector surfaces use the shorter label without the same warning. S5 uses a third, RE-sale-only source. No owner can safely select a profit-allocation rule until the accountant defines the allocable-result taxonomy.

### MEDIUM

**M-01 — BD-001 overstates architectural consequences.**  
A legal entity, SPV, or contractual arrangement may require entity reporting and additional ledgers/interfaces, but it does not automatically invalidate Project subledgers or Project operational isolation. IFRS 10/11 and actual contracts determine reporting; “legal vehicle = Portfolio gets a ledger and contradicts Projects” is not proven.

**M-02 — BD-003 presupposes pooling.**  
An investor's contract can be vehicle- or Portfolio-scoped while internal books still attribute each Project separately. Participation scope does not by itself answer cash pooling, result netting, or allocation.

**M-03 — BD-004 includes misleading categories/explanations.**  
A capital account is a record of economics, not itself a legal ownership instrument. A company shareholder owns shares, not each company asset. Direct title, partnership interest, company equity, debt, and contractual profit rights require distinct legal/accounting models.

**M-04 — BD-011 conflates four different acts.**  
Physical cash movement, settlement of another Project's obligation, intercompany/inter-project receivable/payable, and net presentation of rights are not synonyms. IAS 32 offsetting has strict criteria. A documented due-to/from can preserve Project truth rather than “corrupt both Projects.”

**M-05 — R10's permanent test has a false-negative boundary.**  
It scans direct source imports and an allowlist. It does not traverse SQL-view dependencies, database grants, labels linking toward distribution, demo scripts, or runbooks. It therefore proves only de-surfacing from selected TypeScript pages.

**M-06 — Dead/orphan artifacts obscure actual reachability.**  
`investors/forms.tsx` and `features/allocation/*` are orphaned from pages but still compile; `getAllocationRuleLines` remains unused in intake queries. Conversely, SQL RPCs are live. Treating “not imported by page” as synonymous with “dormant system behavior” is incorrect.

### LOW

**L-01 — 13 narrative questions versus 12 BD IDs remains inconsistent.**  
The matrix explains the fold but the canonical agent policy and Greenfield roadmap still say 13.

**L-02 — Historical status documents are stale without a consistent historical banner.**  
`CURRENT_DELIVERY_STATUS.md`, R13, R14, and roadmap text record different moments and “issued/not started/complete” states. Historical evidence is useful, but current contact status is ambiguous.

**L-03 — Close UI is a legacy policy prompt.**  
The page title is “close and distribution” and tells users to issue allocation/distribute results through the investor route, which only displays a policy block. This is misleading even though it no longer renders S5 forms.

**L-04 — The demo is correctly labeled synthetic but disproves global dormancy.**  
The fixture itself is not company-policy evidence. Its documentation is clear. The problem is the R14 characterization, not the existence of a controlled synthetic mechanism test.

## 5. BD-001…BD-012 validation matrix

| BD | Primary audit result | Secondary defects | Correct first authority | Owner-only residue | Existing architecture impact |
|---|---|---|---|---|---|
| BD-001 | **PARTIALLY NECESSARY** | MIS-SCOPED, presupposes 1:1 Portfolio/legal vehicle; remains distinct from BD-003/004 | company registry + lawyer + accountant | legal-status confirmation and management mapping where documents leave choice | only some answers add entity reporting; Project subledgers need not disappear |
| BD-002 | **NECESSARY** | OVERLAPS/DEPENDS ON BD-005; MISSING SUB-QUESTIONS | bank/GL/contracts + accountant | confirm actual/future funding-source classes | new source/counterparty model; current S1 is insufficient |
| BD-003 | **PARTIALLY NECESSARY** | MIS-SCOPED, presupposes pooled results; remains distinct from BD-001/004 | executed agreements + lawyer | desired participation scope for new templates | Portfolio agreement scope may be additive; pooling is separate |
| BD-004 | **NECESSARY** as evidence issue | MIS-SCOPED, misleading options; remains distinct from BD-001/003 | title/share/company/contract records + lawyer | confirm intended commercial description after legal schedule | requires typed interest model; no current generic ownership field |
| BD-005 | **NECESSARY** | OVERLAPS/DEPENDS ON BD-002; MISSING SUB-QUESTIONS; current live leak | funding documents + accountant/lawyer | approve future allowed mechanisms/authorities | posting and cash-source redesign; current contribution posting may be wrong |
| BD-006 | **NECESSARY** | alternatives incomplete; MISSING SUB-QUESTIONS | signed agreement + accountant/lawyer | approve only discretionary/new-agreement economics | major S5 redesign; current source is stale |
| BD-007 | **MIS-SCOPED** | PARTIALLY NECESSARY | accountant first; contract/lawyer for rights | risk/distribution choice only where legally/accountingly permitted | valuation, close, reversal, capital and disclosure changes |
| BD-008 | **NECESSARY** | MISSING SUB-QUESTIONS; formula live | accountant + contracts/lawyer | discretionary reserves, cadence, approvers | replace/gate S5 capacity and add typed distributions |
| BD-009 | **PARTIALLY NECESSARY** | MIS-SCOPED; fees and carry conflated | contracts/invoices + accountant/lawyer | future commercial terms not already documented | fee accrual/payable/tax and/or waterfall design |
| BD-010 | **PARTIALLY NECESSARY; SPLIT REQUIRED** | law/rates/treatment are professional; system role is Product/Business | tax accountant/current law first, then Product/Business owner | choose record/calculate/withhold/report/defer from prefilled schedule | tax registry/calculation/withholding/reporting adapter |
| BD-011 | **NECESSARY** | MIS-SCOPED; MISSING SUB-QUESTIONS | bank/GL/contracts + accountant/lawyer | future permission, limits, approvers | additive due-to/from may preserve Project boundary; pooling/netting may not |
| BD-012 | **NECESSARY but conditional** | MISSING SUB-QUESTIONS; too compound | contract + lawyer; accountant for valuation | discretion left open by documents | agreement versioning, transfer lots, notices, KYC, capital rollforward |

## 6. Independent audit of each BD item

### BD-001 — Portfolio legal/economic status

1. **Exact current question:** «عندما نجمع عدة مشاريع تحت اسم واحد ... هل هذا التجميع مجرد تنظيم إداري ... أم أن هناك كيانًا حقيقيًا وراءه ...؟» (`R14_TARGET...:25-26`).
2. **Decision sought:** whether each Terranex Portfolio is management-only or corresponds to a company, SPV, regulated fund, or contractual pool.
3. **Technical importance:** determines issuer/reporting identity, agreement scope, data dimensions, consolidation/interface needs, and whether Portfolio needs legal-entity references.
4. **Affected behavior:** `investment_portfolios`, assignment history, Portfolio workspace, F10 rollups, Organization rollup, future agreement/statement scope. No Portfolio ledger exists.
5. **Finance effect:** reporting entity, consolidation/combination, cash/liability ownership, and related-party treatment may change; Project attribution can remain.
6. **Reporting effect:** legal issuer and statement scope must be labeled; current Portfolio reports are management projections.
7. **Security effect:** a separate legal vehicle may require separate Organization/tenant or scoped memberships; this cannot be inferred from the current Portfolio row.
8. **Repository evidence:** canonical baseline says management-only; discovery evidence does not establish legal form; implementation stores management facts only.
9. **External evidence:** GAFI records evidence Egyptian company existence; IFRS 10/11 show reporting depends on control/rights/obligations, not a product noun.
10. **Owner/company-record evidence:** commercial-register extracts, articles, group chart, fund/vehicle documents, pooled contract, and mapping from those records to Terranex names.
11. **Accountant evidence:** reporting entity, consolidation/combination, books, functional currency, and inter-entity accounting.
12. **Lawyer evidence:** legal personality, regulatory/fund status, contracting party, asset/cash ownership.
13. **Classification:** **PARTIALLY NECESSARY; MIS-SCOPED** as an oral choice.
14. **Alternatives complete?** No. One Portfolio may be a management view over several entities; several Portfolios may report one entity; contractual arrangements may exist without pooling; a separate vehicle may still retain Project books.
15. **Misleading/invalid option:** “entity/SPV/fund means Portfolio acquires its own ledger and contradicts Project accounting” is not universally valid.
16. **Presupposition:** assumes one Portfolio maps to one legal structure.
17. **Dependencies:** BD-003/004/010/011; company organization chart.
18. **Consequences:** management-only = current storage can remain; legal entity = add entity identity/reporting, not necessarily replace Projects; fund/regulated vehicle = legal/regulatory redesign; contractual pool = contract-specific scope and rights.
19. **R1–R13 impact:** management-only no change; other answers may add architecture, but Project isolation changes only if actual cash/accounting rights require it.
20. **Recommended owner wording (only after documents are pre-filled):** «أرفقنا جدولًا يربط السجلات والعقود بكل اسم محفظة في Terranex بعد اعتماده مهنيًا. هل تؤكدون أن الصفة المبينة لكل محفظة صحيحة، وما التجميع الإداري الذي تريدونه؟ لا تنشئ الإجابة صفة قانونية جديدة ولا تحسم نطاق المشاركة أو معنى الحق في BD-003/004.»

### BD-002 — Who provides funds

1. **Exact current question:** «من أين تأتي الأموال التي تُصرف على المشاريع فعليًا؟» (`R14_TARGET...:58-59`).
2. **Decision sought:** source counterparties/capacities funding Projects.
3. **Technical importance:** party roles, source classification, evidence, workflows, and reporting.
4. **Affected behavior:** Party/S1 Project investor model, contribution reads, cash postings, F10 contribution rollups, intake DS03-07.
5. **Finance effect:** equity, debt, current account, revenue/advance, internal cash, or memorandum treatment differs.
6. **Reporting effect:** source-of-funds and outstanding obligations; current “contributed capital” cannot represent every source.
7. **Security effect:** who may view/approve source-specific funding; current S1 allows any MEMBER to establish/activate facts.
8. **Repository evidence:** interview mentions investor capital but not universal source; S1 only implements named Project investors/commitments/calls/contributions.
9. **External evidence:** IAS 32 classification depends on contractual obligation; IAS 24 covers related-party finance arrangements/commitments.
10. **Owner/company-record evidence:** bank remitters, contracts, loan docs, shareholder-current-account statements, capital resolutions.
11. **Accountant evidence:** instrument classification and opening/current balances.
12. **Lawyer evidence:** counterparty capacity, enforceability, security, repayment/profit rights.
13. **Classification:** **NECESSARY**; overlaps with and depends on BD-005 but is not duplicated by it; **MISSING SUB-QUESTIONS**.
14. **Alternatives complete?** No: in-kind contributions, grants/subsidies, customer advances, supplier finance, retained cash/reinvestment, and refunds/excess funds are absent.
15. **Misleading option:** “company cash creates no external right” may be false when the company's cash itself is borrowed/held for others.
16. **Presupposition:** treats source party and legal instrument as independently answerable, although one shared evidence schedule must link each source (BD-002) to its mechanism (BD-005). The decisions remain separate.
17. **Dependencies:** BD-001/003/004/005/010/011.
18. **Consequences:** each source requires a linked but separately approved instrument/posting; mixed sources require lot-level traceability; unsupported source must not be forced into S1.
19. **R1–R13 impact:** new source/counterparty records plus the separate BD-005 mechanism/posting records; Portfolio rollups remain projections.
20. **Recommended owner wording:** «راجعوا عمود “مصدر التمويل/المموّل” في جدول التمويل المستخرج من العقود والبنوك والدفاتر. هل الجدول كامل وصحيح، وما فئات المصادر التي تسمحون بها مستقبلًا؟ لا تختاروا هنا الأداة أو القيد؛ ذلك قرار BD-005 مستقل في العمود التالي.»

### BD-003 — Participation scope

1. **Exact current question:** «... هل يستثمر في مشروع محدد ... أم في مجموعة مشاريع ... أم الاثنين ...؟ وهل ... شروط مختلفة ...؟» (`R14_TARGET...:97-98`).
2. **Decision sought:** legal/economic scope of each investor agreement and variability of terms.
3. **Technical importance:** agreement foreign keys, statement scope, access control, and allocation input scope.
4. **Affected behavior:** current `project_participants` and one Project agreement; no Portfolio participant/agreement model.
5. **Finance effect:** does not by itself decide pooling/netting; it determines where rights originate.
6. **Reporting effect:** Project, vehicle, or Portfolio statement and disclosure scope.
7. **Security effect:** Portfolio investor access could expose multiple Projects and needs explicit publication/entitlement rules.
8. **Repository evidence:** source mentions diversified Portfolio but explicitly does not establish investor participation level.
9. **External evidence:** IFRS 11 requires analysis of actual rights/obligations; scope labels are insufficient.
10. **Owner/company-record evidence:** every executed template/agreement/side letter and contracting party.
11. **Accountant evidence:** unit of account and reporting/consolidation consequences.
12. **Lawyer evidence:** enforceable scope and whether terms differ by instrument/project.
13. **Classification:** **PARTIALLY NECESSARY; MIS-SCOPED**.
14. **Alternatives complete?** No: company-share exposure, vehicle-level participation with Project allocations, co-investment, feeder/parallel arrangements, and separate side-letter terms are omitted.
15. **Misleading option:** Portfolio-level participation does not “practically mean” P&L mixing in every case.
16. **Presupposition:** equates participation scope with result-netting scope.
17. **Dependencies:** BD-001/004/006/011/012.
18. **Consequences:** Project scope fits current keys; broader scope needs agreement/member/access models; differing terms require versioned per-instrument schedules.
19. **R1–R13 impact:** additive participation architecture; Project ledger changes only if actual accounting policy requires it.
20. **Recommended owner wording:** «وفق جدول العقود المرفق، أكدوا إن كان نطاق كل نموذج جديد مشروعًا محددًا أم كيانًا/مجموعة محددة، وهل تسمحون بشروط خاصة تختلف عن النموذج القياسي. نطاق الربح والخسارة والتحويل يُعالج في جدول اقتصادي مستقل.»

### BD-004 — Meaning of ownership

1. **Exact current question:** «عندما نقول إن مستثمرًا “يملك” شيئًا ... ما هو هذا الشيء قانونيًا؟» (`R14_TARGET...:129-130`).
2. **Decision sought:** legal instrument/right represented by an interest.
3. **Technical importance:** typed interest schema, titles, units, effective dates, statements, transfer workflows.
4. **Affected behavior:** no active generic ownership field; S5 weight basis is not ownership storage; title/control records are sector facts.
5. **Finance effect:** equity/liability/joint-operation/direct-asset/profit-right and capital-account treatment differ.
6. **Reporting effect:** statements must label the actual instrument; no generic “ownership %.”
7. **Security effect:** rights to reports/documents may follow contract, not simply Party identity.
8. **Repository evidence:** canonical separation is correct; current S1 participant role and S5 weights do not prove ownership.
9. **External evidence:** IAS 32 and IFRS 11 distinguish rights/obligations; GAFI records company interests; title records govern direct asset ownership.
10. **Owner/company-record evidence:** articles, registers, contracts, title deeds, side letters.
11. **Accountant evidence:** recognition and partner/equity/current-account presentation.
12. **Lawyer evidence:** primary — actual legal right, control, asset title, transferability.
13. **Classification:** **NECESSARY; MIS-SCOPED** as owner selection rather than evidence extraction.
14. **Alternatives complete?** No: debt with profit participation, usufruct/beneficial rights, nominee/agency, joint operation/net-asset interests, options/conversion, and no proprietary interest.
15. **Misleading option:** “capital-account units” is not necessarily a legal instrument; shareholders do not directly own company assets.
16. **Presupposition:** assumes all recorded `INVESTOR` parties own something.
17. **Dependencies:** BD-001/003/006/007/009/012.
18. **Consequences:** each instrument requires distinct labels, balances, rights, transfers, and tax/accounting; combinations need component/lot records.
19. **R1–R13 impact:** new typed interest layer; do not reinterpret S1/S5 rows.
20. **Recommended owner wording:** «استخرج المستشار القانوني من كل مستند نوع الحق وصاحبه ونطاقه وتاريخ سريانه. يرجى منكم تأكيد أن الجدول يعكس الاتفاق التجاري المقصود، وتصحيح الغرض التجاري فقط؛ الصفة القانونية لا تُختار من قائمة عامة.»

### BD-005 — Funding mechanism

1. **Exact current question:** «عمليًا ... كيف يصل إليه المال؟ وما الآليات المسموح أن تجتمع معًا؟» (`R14_TARGET...:169-170`).
2. **Decision sought:** legal/accounting instrument and operational workflow for each source.
3. **Technical importance:** posting rules, schedules, repayment, calls, partial/overfunding, evidence.
4. **Affected behavior:** S1 requires commitment→call→contribution; S2 posts contributed capital; no loan/current-account/company-deployment workflow.
5. **Finance effect:** liability/equity/current-account/intra-group/cash classification and interest/fees.
6. **Reporting effect:** funded, due, callable, repayable, refundable, and uncalled balances.
7. **Security effect:** call/loan/equity approvals differ; current S1 has no owner gate.
8. **Repository evidence:** only S1 mechanism exists; canonical documents explicitly call other mechanisms unresolved.
9. **External evidence:** IAS 32 substance/obligation; IAS 24 related-party finance disclosure; ILPA practice distinguishes call purpose/commitment impact.
10. **Owner/company-record evidence:** actual instruments, notices, resolutions, bank/GL trail.
11. **Accountant evidence:** posting and cash-owner treatment.
12. **Lawyer evidence:** enforceability, maturity, security, default, interest/profit rights.
13. **Classification:** **NECESSARY**; overlaps with and depends on BD-002 but is not duplicated by it; **MISSING SUB-QUESTIONS**.
14. **Alternatives complete?** No: direct contribution without call, in-kind value, overfund/refund, unused/recallable capital, supplier/customer finance, grants, guarantees.
15. **Misleading option:** direct company payment does not prove no external claim; current account is not always simply payable to partner.
16. **Presupposition:** implies current S1 can become policy-ready merely by choosing “commitment/call.” It lacks approvals/notices/default/refund/amendments. A shared evidence schedule with BD-002 does not merge the mechanism decision into the source decision.
17. **Dependencies:** BD-002/003/004/010/011/012.
18. **Consequences:** confirmed call model may reuse parts of S1 after controls; every other instrument needs new typed commands/postings; mixed funding needs source lots.
19. **R1–R13 impact:** material Finance Core extension; exact money/Project dimensions remain.
20. **Recommended owner wording:** «لكل مصدر تمويل مؤكد في BD-002، أرفقنا الأداة القانونية والمعالجة التي اقترحها المحاسب: مساهمة/رأس مال، حساب جارٍ، قرض، صرف شركة، أو غير ذلك، مع الرد/الفائدة/الضمان. ما الأدوات التي تسمحون بها مستقبلًا، ومن يعتمد كل أداة وإصدار طلب الدفع؟ لا تعيدوا تصنيف حركة تاريخية شفهيًا.»

### BD-006 — Profit/loss assignment

1. **Exact current question:** «... بأي قاعدة يتوزع هذا الربح أو هذه الخسارة على المشاركين؟» plus three subquestions (`R14_TARGET...:206-223`).
2. **Decision sought:** complete contractual allocation/waterfall for each result category and period.
3. **Technical importance:** source amount, eligible population, effective version, algorithm, rounding, journals, correction.
4. **Affected behavior:** S5 rule/runs/lines, close snapshot, partner capital, statements, distribution eligibility.
5. **Finance effect:** partner capital/equity/liability and deficit/loss treatment.
6. **Reporting effect:** gross/net result, category, opening/closing capital, carry, residual and corrections.
7. **Security effect:** preparer/approver segregation exists, but policy authorization and participant access do not.
8. **Repository evidence:** S5 exact math exists but source is RE-sale-only and rule shape is one positive 100% schedule.
9. **External evidence:** ILPA practice makes LPA, waterfall, carry/clawback, fees, and transaction categories explicit; it is not company policy.
10. **Owner/company-record evidence:** signed agreement/schedules/side letters/resolutions.
11. **Accountant evidence:** allocable result taxonomy, capital accounts, losses/deficits, periods, corrections.
12. **Lawyer evidence:** enforceability, precedence, asymmetric rights, amendments.
13. **Classification:** **NECESSARY; MISSING SUB-QUESTIONS**.
14. **Alternatives complete?** No: preferred return/hurdle/catch-up, tiered waterfalls, category-specific and time-weighted allocation, zero/excluded parties, loss caps, deficits, clawback, final residual.
15. **Misleading option:** “fixed shares are clearest” leads the respondent; “realized” is not yet consistently defined across Terranex.
16. **Presupposition:** assumes one rule covers both signs and all income/cost categories.
17. **Dependencies:** BD-003/004/007/009/012 and result taxonomy/effective dates.
18. **Consequences:** ownership/funding/fixed choices all need dates and evidence; asymmetric/tiered answers replace rather than merely activate S5; loss/default answers affect capital calls and exit.
19. **R1–R13 impact:** major S5 source/rule redesign; Project/close/exact-money foundations can remain.
20. **Recommended owner wording:** «بعد أن يملأ المحاسب والمستشار “جدول الاقتصاد التعاقدي” لكل نموذج عقد (فئات الدخل/التكلفة، ترتيب رد رأس المال، الربح، الخسارة، العائد المفضل، حصة المشغّل، العجز، الاسترداد، التدوير، تاريخ السريان والأولوية)، يرجى اعتماد الجدول أو تحديد التعديل التجاري المطلوب. لا تختاروا نسبة عامة خارج العقد.»

### BD-007 — Unrealized valuation

1. **Exact current question:** «عندما يرتفع سعر أصل ... دون بيعه — كيف تتعاملون مع هذه الزيادة؟» (`R14_TARGET...:245-246`).
2. **Decision sought:** accounting recognition, investor attribution, and cash distribution — three different decisions.
3. **Technical importance:** valuation journals/disclosures, allocation source, statements, markdown/clawback, close.
4. **Affected behavior:** approved RE valuations and cross-sector reads are management-only; S5 excludes them.
5. **Finance effect:** applicable asset classification may produce P&L/OCI/disclosure; none equals cash.
6. **Reporting effect:** realized, unrealized recognized, management valuation, and distributable cash need separate labels.
7. **Security effect:** valuation evidence/approval and investor publication scope.
8. **Repository evidence:** current management-only treatment is safe as a product baseline, not proof of company accounting policy.
9. **External evidence:** IAS 40 can recognize fair-value change in P&L; IFRS 13 only defines measurement; sector classification can invoke different standards.
10. **Owner/company-record evidence:** contracts granting valuation-linked rights and management risk intent.
11. **Accountant evidence:** mandatory primary determination — framework, classification, measurement, recognition, reversal.
12. **Lawyer evidence:** whether rights/distributions may be valuation-linked; capital/solvency constraints.
13. **Classification:** **MIS-SCOPED; PARTIALLY NECESSARY**.
14. **Alternatives complete?** No: OCI/revaluation reserve, impairment, fair value less costs, valuation frequency, independent valuer, participant entry/exit price, markdown/clawback.
15. **Misleading/invalid option:** “paper gain is not profit” is not always accounting-correct; “can distribute it” omits legal/cash-source constraints.
16. **Presupposition:** treats owner preference as accounting authority and focuses on price increase, not decrease.
17. **Dependencies:** BD-004/006/008/010/012; asset classification.
18. **Consequences:** management-only no ledger effect; recognized change affects statements/tax/close; contractual attribution needs capital-account logic; cash distribution requires separate availability and legality.
19. **R1–R13 impact:** non-management options require new accounting and correction design; current management valuation can remain alongside it.
20. **Recommended owner wording:** «سيحدد المحاسب معالجة التقييم من تصنيف الأصل والمعيار، وسيحدد المستشار أي حق تعاقدي. بعد ذلك فقط: هل تعتمدون استخدام التقييمات المعتمدة في قرارات الإدارة/الدخول/الخروج ضمن الحدود الموضحة، وما مستوى المخاطرة أو الموافقة الإدارية المطلوب؟ لا يُسأل المالك عن اختيار القيد المحاسبي.»

### BD-008 — Distributable cash

1. **Exact current question:** «قبل توزيع أي مبلغ ... ما الذي يجب خصمه أو حجزه أولًا؟» plus scope/approval/timing (`R14_TARGET...:278-300`).
2. **Decision sought:** mandatory restrictions plus discretionary reserve and governance.
3. **Technical importance:** capacity calculation, approval blocks, distribution type, as-of/versioning.
4. **Affected behavior:** live S5 capacity/prepare/approve/pay; intake opening distribution payable; pilot reconciliation.
5. **Finance effect:** liabilities, restricted cash, reserves, debt service, working capital, tax, return of capital, solvency.
6. **Reporting effect:** capacity bridge with each deduction, source, date, policy version, and uncertainty.
7. **Security effect:** who prepares, recommends, approves, overrides, and pays; maker/checker alone is insufficient.
8. **Repository evidence:** S5 subtracts only two positive payable roles; exact cash does not prove availability.
9. **External evidence:** IAS 7 defines cash reporting, not distribution permission; IAS 10 supports liability timing after appropriate declaration; ILPA distinguishes distribution categories/recallability.
10. **Owner/company-record evidence:** contracts, resolutions, reserve policy, debt covenants, historical computations.
11. **Accountant evidence:** complete capacity schedule and classification.
12. **Lawyer evidence:** contractual/statutory restrictions and approval authority.
13. **Classification:** **NECESSARY; MISSING SUB-QUESTIONS**.
14. **Alternatives complete?** No: restricted/escrow cash, receivable uncertainty, customer advances/refunds, contingent liabilities, capex, legal capital, recallability, return-capital ordering, residual closeout, currency.
15. **Misleading option:** the list implies owner may opt out of mandatory liabilities/taxes/covenants.
16. **Presupposition:** treats all desired distribution purposes alike and Project cash as legally owned by that Project. Current S5 actually supports only an allocation-based distribution; it does not implement the other purposes.
17. **Dependencies:** BD-001/004/006/007/009/010/011/012.
18. **Consequences:** each mandatory deduction is non-discretionary; owner reserve/cadence is versioned policy; cross-Project source invokes BD-011; any future return-capital/refund/in-kind/recallable answer requires a new typed flow rather than reinterpretation of S5.
19. **R1–R13 impact:** gate/replace S5 capacity; define the current allocation-based ceiling; add new typed purpose/ordering only for professionally approved future flows, plus reconciliation.
20. **Recommended owner wording:** «أرفق المحاسب جسر النقد المتاح بعد الالتزامات والقيود القانونية/التعاقدية. يرجى اعتماد البنود الإدارية فقط التي تركتها المستندات مفتوحة: احتياطي الإدارة/الحد الأدنى للسيولة، دورية الاقتراح، وحدود وسلطات الاعتماد. حددوا كذلك الأغراض التي تريدون دعمها مستقبلًا؛ النظام الحالي يدعم توزيعًا مرتبطًا بتخصيص موجب فقط ولا يدعم رد رأس المال/رد الفائض/التوزيع العيني/القابل لإعادة الاستدعاء.»

### BD-009 — Operator/management economics

1. **Exact current question:** «هل تتقاضى الشركة ... مقابلًا لإدارة الاستثمار وتشغيله؟ وما شكله؟» plus six details (`R14_TARGET...:316-338`).
2. **Decision sought:** service fees, expense reimbursements, profit participation/carry, and co-investment.
3. **Technical importance:** fee contracts/accruals, allocation order, payables, tax, statements.
4. **Affected behavior:** no dedicated fee model; S5 can include operator only as another allocation participant.
5. **Finance effect:** project expense versus related-party payable versus allocation/equity are not interchangeable.
6. **Reporting effect:** gross/net fees, offsets/waivers, related-party disclosure, carry/clawback.
7. **Security effect:** conflicts of interest, related-party approval, maker/checker and disclosure access.
8. **Repository evidence:** discovery indicates alignment only; no formula. Existing expenses can record invoices but not fee policy.
9. **External evidence:** IAS 24 related-party finance/service disclosure; ILPA requires governing-document consistency and fee/carry detail (practice only).
10. **Owner/company-record evidence:** contracts, invoices, resolutions, schedules, co-investment documents.
11. **Accountant evidence:** accrual, expense/allocation, capitalization, VAT/tax, offsets.
12. **Lawyer evidence:** enforceability, related-party/conflict approvals, carry/waterfall/clawback.
13. **Classification:** **PARTIALLY NECESSARY; MIS-SCOPED**.
14. **Alternatives complete?** No: reimbursements, offsets, waivers, break fees, monitoring/transaction fees, VAT, related parties, hurdle/catch-up/clawback, co-investment.
15. **Misleading option:** “no fee means company earns only as investor” need not be true; it may earn operating margins or other contracted revenue.
16. **Presupposition:** conflates service compensation and profit allocation.
17. **Dependencies:** BD-004/006/008/010/012.
18. **Consequences:** service fee creates expense/payable/tax; carry changes waterfall; co-investment follows investor instrument; reimbursements need cost evidence.
19. **R1–R13 impact:** dedicated fee/related-party layer and/or S5 redesign; procurement/AP may be reusable for invoiced services.
20. **Recommended owner wording:** «بعد استخراج جدول الأتعاب والمصروفات وحصة النجاح من العقود والفواتير، أكدوا الشروط التجارية المقصودة للنماذج الجديدة فقط: نوع المقابل، أساسه، توقيته، الإعفاءات/المقاصات، والنطاق. يحدد المحاسب القيد والضريبة، ويعتمد المستشار الصياغة والتعارضات.»

### BD-010 — Tax/withholding

1. **Exact current question:** «ماذا تريدون من النظام أن يفعل بخصوص الضرائب والاستقطاعات ...؟» (`R14_TARGET...:354-355`).
2. **Decision sought:** product automation scope, not the underlying tax law alone.
3. **Technical importance:** registry, calculation versions, withholding payable, reporting/export.
4. **Affected behavior:** generic tax registry/tax-number fields and semantic role; no investor tax engine.
5. **Finance effect:** current/deferred taxes, withholding, VAT, tax paid for participants, gross/net distributions.
6. **Reporting effect:** returns/certificates/reconciliation and gross-to-net statements.
7. **Security effect:** sensitive taxpayer IDs, restricted rates/certificates, preparer/approver.
8. **Repository evidence:** F6 is an explicit registry, not target tax calculation; statutory GL remains external.
9. **External evidence:** ETA official law and current 2026 materials show tax rates/exemptions can depend on recipient, instrument, listing, regime, and later legislation; repository cannot select applicability.
10. **Owner/company-record evidence:** tax registration, taxpayer regime, residency, investor tax forms, historic filings.
11. **Accountant evidence:** mandatory — applicable taxes, current law, calculation, filing/withholding party.
12. **Lawyer evidence:** treaties/regulatory interpretation when needed.
13. **Classification:** **PARTIALLY NECESSARY; MIS-SCOPED; SPLIT REQUIRED**. The professional determination and Product/Business scope decision are separate, but BD-010 remains a distinct canonical decision.
14. **Alternatives complete?** No: gross-up, relief/treaty, exemption, tax paid on behalf, certificates, corrections, effective versions, external return IDs.
15. **Misleading option:** “leave entirely external” does not remove required operational data or posting/reconciliation.
16. **Presupposition:** assumes owner preference can define legal obligations; “calculate” lacks rule owner/version/liability. Conversely, routing law to professionals does not answer what Terranex should do.
17. **Dependencies:** all legal instrument/scope items, especially BD-004/007/008/009/012.
18. **Consequences:** record-only still needs typed authority and posting; calculate/withhold needs professional specification and versioning; report/export needs adapter contract; defer/external still needs an explicit system-boundary decision.
19. **R1–R13 impact:** optional bounded tax slice after professional specification and explicit Product/Business scope approval.
20. **Recommended split wording:** professional schedule first: «حدد لكل كيان/أداة/مستفيد الضريبة والاستقطاع والجهة الملزمة والحساب والنموذج وتاريخ السريان.» Then Product/Business decision: «استنادًا إلى الجدول المعتمد، ماذا يجب أن يفعل Terranex لكل بند: يسجل مبلغًا معتمدًا، يحسب بقاعدة مُصدَّرة، يستقطع ويرحّل، يجهز تقريرًا/تصديرًا، أم يؤجل بالكامل لنظام خارجي؟»

### BD-011 — Cross-project movement/netting

1. **Exact current question:** «هل يجوز ... أن ينتقل مال من مشروع إلى مشروع آخر؟ ... بأي صفة؟» plus four yes/no netting questions (`R14_TARGET...:385-408`).
2. **Decision sought:** historical/current treasury mechanics, contractual entitlement netting, and future permissions.
3. **Technical importance:** paired postings, due-to/from, bank ownership, approvals, elimination, reporting.
4. **Affected behavior:** no cross-Project movement command; constraints enforce same Project; Portfolio rollup is read-only.
5. **Finance effect:** loans/current accounts/due-to/from/agency payments/capital transfers differ; offsetting has strict rules.
6. **Reporting effect:** gross balances, related-party disclosure, cash pool, Project performance, consolidated elimination.
7. **Security effect:** dual-Project authorization, conflicts, limits, audit, no one-sided write.
8. **Repository evidence:** only a canonical taxonomy example mentions inter-project due-to/from; no active account/command. Project isolation is strong.
9. **External evidence:** IAS 32.42 limits offset; IAS 24 requires related-party transaction/balance/commitment disclosure; neither proves company practice.
10. **Owner/company-record evidence:** bank/GL examples, treasury policy, contracts, board resolutions.
11. **Accountant evidence:** paired entries, reporting entity, interest/impairment/elimination, cash ownership.
12. **Lawyer evidence:** authority, enforceability, investor restrictions, lending/regulatory implications.
13. **Classification:** **NECESSARY; MIS-SCOPED; MISSING SUB-QUESTIONS**.
14. **Alternatives complete?** No: central treasury sweep, agency settlement/recharge, intercompany rather than inter-Project movement, restricted accounts, noncash transfer, distribution then reinvestment, refund/re-funding.
15. **Misleading option:** “no transfer is safest” leads; “any yes changes Project isolation” is too broad. Proper paired accounting can preserve it.
16. **Presupposition:** assumes Projects themselves are legal counterparties and own bank cash.
17. **Dependencies:** BD-001/002/003/004/005/006/008/010.
18. **Consequences:** no movement = current commands remain absent; due-to/from/loan = additive paired workflow; cash pooling = bank/project attribution design; entitlement netting = contract/allocation redesign; presentation offset only if criteria met.
19. **R1–R13 impact:** documented paired mechanisms can retain Project boundary; true pooled entitlement/reporting may alter later architecture.
20. **Recommended owner wording:** «بعد أن يحدد المحاسب والمستشار الآليات الجائزة لكل كيان/عقد، هل تسمحون مستقبلًا بأي من الآليات المحددة في الجدول؟ حددوا الغرض، الحد، المدة، المشروعين، الموافقين، وهل الحركة نقدية أم مديونية أم سداد وكالة. لا يُجمع الربح/الخسارة أو تُعرض أرصدة بالصافي إلا إذا نص الجدول المهني صراحة.»

### BD-012 — Investor lifecycle

1. **Exact current question:** «ما القواعد والإجراءات الفعلية ...؟» followed by twelve event classes (`R14_TARGET...:429-447`).
2. **Decision sought:** entry, increase, withdrawal/exit, transfer/assignment, default, succession, identity change, notices/statements, approvals.
3. **Technical importance:** agreement versioning, interest lots, valuation cutoffs, participant state, approvals/notices.
4. **Affected behavior:** S1 freezes forever after first activation; no amendment/supersession/transfer/exit; current participant role cannot change.
5. **Finance effect:** contribution/refund, realized/unrealized accrual, deficit, fees/tax, receivable/payable, final closeout.
6. **Reporting effect:** historical versus current holder, statements, certificates, notices, final balances.
7. **Security effect:** KYC/beneficial owner, revoked/new access, estate/authorized representative, approvals.
8. **Repository evidence:** explicit S1 deferral proves the implementation needs carry-forward/effective-date rules.
9. **External evidence:** GAFI succession/change documents demonstrate record-driven legal events; ILPA practice shows amendments/recallable flows but is not governing law.
10. **Owner/company-record evidence:** contract clauses, transfer/death records, historic cases, internal authority matrix.
11. **Accountant evidence:** entry/exit valuation, cut-off, deficits, settlement, tax.
12. **Lawyer evidence:** primary — transfer restrictions, consent/pre-emption, succession, notices, identity/KYC.
13. **Classification:** **NECESSARY but conditional; MISSING SUB-QUESTIONS**.
14. **Alternatives complete?** No: effective cutoff, partial lots, accrued P&L, unpaid calls, overfund/refund, sanctions/KYC, incapacity, dispute, insolvency, final residual, data retention/access.
15. **Misleading option:** “management rule” may not override contract/law; “undefined” cannot safely become an owner oral rule for existing rights.
16. **Presupposition:** assumes every event applies to every instrument and that “investor” is one legal type.
17. **Dependencies:** all instrument/economic/tax items, especially BD-003/004/006/007/009.
18. **Consequences:** prohibited event = validation only; permitted event = effective-dated transfer/amendment and settlement; default/succession need legal workflow; statement obligations need publication/access design.
19. **R1–R13 impact:** replaces S1's permanent freeze with governed version/transfer mechanics; historical exactness must remain.
20. **Recommended owner wording:** «أرفق المستشار مصفوفة دورة الحياة لكل نوع عقد وحدد ما يحكمه القانون/العقد. بالنسبة للخانات التي تركها المستند مفتوحة فقط، اعتمدوا هل الحدث مسموح، ومن يوافق، ومتى يسري، ومتى يُحال للمستشار. لا تُنشأ قاعدة دخول/خروج شفهيًا لعقد قائم.»

## 7. Code/runtime policy-leak classification

| Artifact/behavior | Classification | Finding |
|---|---|---|
| Portfolio identity/lifecycle/current-parent/history | **SAFE FACTUAL MECHANISM** | no economic semantics |
| Project/currency dimensions, bigint money, balanced journals, reversal, close | **SAFE FACTUAL MECHANISM** | reusable invariants |
| Commitment/call/contribution stored separately | **SAFE FACTUAL MECHANISM** | correct separation when those facts genuinely apply |
| Mandatory Project investor/agreement/commitment intake | **LIVE POLICY-DEPENDENT BEHAVIOR** | presupposes BD-002/003/005 |
| S1 agreement activation/call issuance by any active member | **LIVE POLICY-DEPENDENT BEHAVIOR** | freezes rights/workflow without owner-policy gate |
| Explicit OWNER-gated `attach_contribution_cash` credits contributed capital | **LIVE POLICY-DEPENDENT BEHAVIOR** | selected posting flow imposes equity treatment before instrument confirmation; Contribution recording alone does not post it |
| S5 RPC execute grants plus internal membership/selected OWNER/maker-checker gates | **LIVE POLICY-DEPENDENT BEHAVIOR** | authorization exists, but no BD/policy-activation gate makes the database chain policy-inert |
| S5 RE-sale-only source after sector/rental expansion | **ACTUAL BUG** | incomplete/zero allocable result on supported runtime sectors/revenue |
| S5 capacity formula enforced as “distributable cash” | **LIVE POLICY-DEPENDENT BEHAVIOR** | unapproved BD-008 formula; incomplete deductions |
| S5 lacks typed distribution purpose/ordering and explicit triggering-allocation ceiling semantics | **ACTUAL BUG** | current flow is allocation-based; return-capital/refund/in-kind/recallable flows are unsupported, not silently implemented |
| S5 distribution payment without bank match path | **ACTUAL BUG** | payment cannot complete canonical bank reconciliation |
| `/pilot` investor-statement total | **LIVE POLICY-DEPENDENT BEHAVIOR** | indirect S5 read exposed as technical readiness metric |
| `/controls` partner-capital gate | **LIVE POLICY-DEPENDENT BEHAVIOR** | policy-dependent model affects financial-integrity output |
| close title/instruction to allocate/distribute | **MISLEADING LABEL** | suggests action exists/authorized while safe route blocks it |
| F10/R8 “realized result” without expense in some surfaces | **MISLEADING LABEL** | gross result can be mistaken for Project profit |
| `investors/forms.tsx` allocation/distribution forms | **DEAD CODE** | orphaned from live pages, but actions/RPCs are not dead |
| unused intake `getAllocationRuleLines` | **DEAD CODE** | residual dependency obscures boundary |
| S5-focused runbooks as “normal product command” | **LEGACY LEAK** | operational docs treat policy chain as active |
| permanent synthetic 60/40 demo | **DORMANT POLICY-DEPENDENT MECHANISM** | acceptable only as labeled synthetic proof; not company policy; disproves global dormancy |
| opening approved-but-unpaid distribution import | **SAFE FACTUAL MECHANISM** | historical liability only if accountant/records substantiate it |
| tax/withholding semantic role/registry without computation | **DORMANT POLICY-DEPENDENT MECHANISM** | taxonomy is not policy |
| no cross-Project transaction command | **SAFE FACTUAL MECHANISM** | absence preserves current Project truth |
| R10 direct-import policy test | **POTENTIAL BUG** | test claim exceeds what its scan proves |

### Reachability distinctions

- **Dormant UI:** orphan S5 forms are not rendered.
- **Live database behavior:** S5 RPCs are executable and post journals.
- **Live indirect UI:** S7 acceptance reads S5 partner statements and displays totals/gates.
- **Synthetic versus real:** demo economics are clearly labeled synthetic; the financial mechanisms and generated rows are nevertheless real database behavior.
- **Wording versus financial truth:** close-page copy is a wording defect; S5 source/capacity/type/reconciliation defects affect financial truth.

## 8. Finance consistency audit

| Concept | Current status | Collapse/contradiction |
|---|---|---|
| Portfolio capital deployment | **Not implemented as a fact/command** | canonical docs describe it, but no record exists; do not use contribution as proxy |
| Project funding | **Partially implemented only as S1 investor flow** | company cash, debt, current account, intercompany, direct contribution absent |
| Investor contribution | Separate S1 fact | recording alone is non-posting; the later explicit OWNER-gated cash attachment imposes contributed-capital treatment regardless instrument |
| Commitment | Separate positive S1 fact | mandatory intake assumption is unsafe |
| Capital call | Separate from commitment/contribution | cannot cancel/account, overfund, direct-fund, or handle default; issuance authority broad |
| Contribution | Separate append-only non-posting fact | requires a call; no overfund/refund/in-kind; cash/equity effect occurs only through separate attachment |
| Ownership | Not actively modeled | S5 weights must not be relabeled ownership |
| Capital balance | S1 funding rollforward plus S5 partner-capital ledger | labels may imply equity before BD-004/005; two meanings need accountant |
| Profit/loss allocation | Separate S5 run/lines | live, stale source, incomplete rule shape |
| Distribution entitlement | No standalone complete entitlement-purpose model | positive approved allocation is required; requested amount is checked against total partner capital/capacity, but purpose/ordering and triggering-allocation ceiling semantics are not typed |
| Distributable cash | Separate S5 calculation | formula is policy-dependent and incomplete |
| Approved distribution | Separate payable journal | correct state separation, missing policy activation and typed purpose; unsupported return-capital/refund flows are not implemented |
| Payment | Separate cash-settlement journal | correct state separation |
| Bank reconciliation | Separate shared domain | **missing link for S5 distribution payment** |

### Exact money and isolation

- Monetary storage/transport is generally strong: PostgreSQL `bigint`, text read models, deterministic rational/rounding logic, balanced journals, idempotency, and reversal links.
- Project/tenant scoping is generally strong: composite scope checks, RLS, same-Project cash/payment constraints, and Project-derived Portfolio rollups.
- No cross-Project money command was found.
- Exact arithmetic does not make an unapproved source, classification, or formula economically correct.

### Accounting-boundary effects of possible answers

- **Project boundary:** can remain for operational attribution under most answers. A legal vehicle/Portfolio scope does not automatically erase it.
- **Portfolio rollup:** may need issuer/reporting dimensions; must remain a projection unless an actual reporting entity ledger is designed.
- **Cash ownership:** unresolved; a `project_cash_account` is a Project dimension, not legal title proof.
- **Liability recognition/current accounts:** absent for investor funding; requires accountant-approved instruments.
- **Revenue/cost attribution:** independent from investor economics, but “allocable result” must be defined from complete categories.
- **Distribution payable:** correct state concept; legal approval and distribution type unresolved.
- **Cross-Project due-to/from:** absent; a future paired mechanism can preserve Project truth.
- **Period close:** S6 can remain, but S5 source and policy versions must reconcile to the closed period.
- **Reversal/correction:** strong journal foundation; policy amendments, valuation markdown/clawback, tax corrections, and lifecycle carry-forward are absent.

## 9. Professional-completeness additions

Add these only as **prefilled document/professional schedules**, not as raw owner prompts:

1. **Effective dates, versions, and precedence:** contract, side letter, amendment, board resolution, later owner decision; required because S1 freezes and S5 uses effective ranges.
2. **Allocable-result taxonomy:** sale margin, rental income, Agriculture/Livestock operating result, overhead, finance cost, tax, valuation, fee, and prior-period correction; required by the three inconsistent “result” definitions.
3. **Separate profit and loss mechanics:** loss caps, deficit capital, restoration, future-profit offset, additional call; required because S5 applies one schedule to both signs.
4. **Funding exceptions:** partial call, direct contribution, overfunding, unused funds, refunds, in-kind funding, default, cure; required because S1 only supports positive commitment/call/contribution within ceilings.
5. **Distribution type and ordering:** distinguish the current allocation-based distribution from future return of capital, income/profit, refund/excess capital, in-kind, recallable/reinvestable, and final residual flows; required because S5 has no typed model for those unsupported purposes or their ordering.
6. **Fee detail:** service fee versus profit share, reimbursements, offsets, waiver, VAT/tax, related party, carry/hurdle/catch-up/clawback; required by accounting and S5 gaps.
7. **Cash and restrictions:** legal bank-account owner, restricted/escrow cash, debt covenants, customer/supplier obligations, contingencies, future capex, currency; required by BD-008 and S5 capacity.
8. **Entry/exit valuation and cut-off:** effective date, accrued result, partial lots, rounding/residual, tax/fee, final closeout; required by S1 versioning and statements.
9. **Treasury movement taxonomy:** cash sweep, loan, due-to/from, agency settlement, recharge, repayment, distribution/reinvestment; required to avoid BD-011 collapse.
10. **Authorization/evidence:** preparer, business approver, accountant, lawyer, bank signer, notice recipient, evidence ID; current “OWNER” application role is not contractual authority.
11. **Identity/compliance:** legal capacity, beneficial owner/KYC, sanctions, death/incapacity/succession, data/access handover; only if the actual instrument requires investor lifecycle workflows.
12. **Rounding and final residual:** per currency, nominated residual recipient, negative amounts, final liquidation; required for exact investor statements.

## 10. Questions to REMOVE, MERGE, REWRITE, and ADD

### REMOVE from owner contact

- The **law/rate/applicability/accounting-treatment subquestions** inside BD-010; preserve BD-010's later Product/Business system-scope decision.
- The **accounting-recognition choice** inside BD-007; preserve its separate contractual/management decision after professional review.
- Oral requests for legal status/ownership that company records and lawyer should answer (parts of BD-001/004); preserve both canonical decisions.
- Any request to re-state historical funding, fees, distributions, or transfers from memory when bank/GL/contracts can answer.
- Leading statements that fixed shares are clearest, no transfer is safest, or a legal Portfolio necessarily contradicts Projects.
- **No BD ID is removed or merged.**

### MERGE — evidence collection only, never the decisions

- **BD-002 and BD-005:** use one linked source-and-instrument evidence schedule, but record two separate decisions: who/source funds versus legal/accounting mechanism.
- **BD-001, BD-003, and BD-004:** use one legal-structure/contract/right evidence matrix, but record three separate decisions: Portfolio legal status, participation scope, and meaning of the interest.
- **BD-006, BD-007, and BD-009:** use one versioned economics schedule for consistency, while separately approving result allocation, valuation-linked treatment/rights, and operator compensation.
- **BD-008, BD-011, and BD-012:** cross-reference one cash/lifecycle evidence pack, while separately approving distributable-cash policy, cross-Project movement, and investor lifecycle.

Shared evidence intake removes duplicate evidence requests. It does not collapse independent business decisions.

### REWRITE

All retained items require the conditional Arabic wording in §6. No current R14 item should be sent unchanged.

### ADD as missing professional schedules/questions

Add the 12 items in §9. Section 13 then preserves twelve separate, concise owner/Product-Business confirmation drafts — one per BD — because professional schedules pre-answer the law, accounting, tax, and historical-fact portions without merging the decisions.

## 11. Correct authority routing

### Questions for accountant / tax accountant

1. What is the reporting entity and accounting boundary for each legal/contractual arrangement?
2. For every historic/current funding receipt/payment, what instrument and account classification applies: equity, liability, shareholder/current account, intercompany, advance, income, or other supported category?
3. Who legally/accountingly owns each bank balance, and how is Project attribution reconciled to that owner?
4. What complete Project result categories are recognized and which are allocable under each agreement?
5. How are losses, deficit capital, prior-period corrections, reversals, and final closeout treated?
6. Which asset classifications/measurement policies govern Real Estate, Agriculture, and Livestock valuations, and how are increases/decreases recognized?
7. How are service fees, reimbursements, carry/profit shares, offsets, tax, and related-party items recorded?
8. What is the full distributable-cash bridge, including restricted cash, liabilities, reserves, debt service, capex, tax, and contingencies?
9. How are return of capital, profit distribution, refund/excess capital, recallable amount, reinvestment, and in-kind distribution distinguished?
10. How are cross-entity/Project movements, due-to/from, loans, eliminations, impairment, and IAS 24 disclosures handled?
11. Which taxes/withholding/VAT/regimes/treaties apply to each entity, instrument, recipient, and effective period; who files/remits/certifies?
12. What rounding, currency, cut-off, statement, and reconciliation rules are required?

### Questions for lawyer

1. Identify each legal entity/vehicle/arrangement, contracting party, regulatory/fund/securities status, and its relationship to Terranex Portfolio/Project names.
2. Identify the legal nature of every investor/partner/lender right and every asset title; distinguish shares, partnership/net-asset rights, debt, direct title, profit right, agency/nominee, and no ownership.
3. Extract scope, effective date, amendment/side-letter precedence, and approval authority from every governing document.
4. Extract allocation/waterfall, loss, fees/carry, reserves, distribution, return-capital, reinvestment, clawback, and capital-maintenance terms.
5. Extract funding/call, partial/default/cure, overfund/refund, loan/current-account, security, and notice terms.
6. Extract entry, increase, withdrawal, exit, transfer/assignment, pre-emption, death/incapacity/succession, identity change, and statement/certificate rights.
7. Determine whether proposed cash pooling, inter-Project/entity lending, due-to/from, set-off, or obligation settlement is permitted and by whom.
8. Confirm KYC/beneficial ownership, data/access, dispute, governing-law, and regulatory notices applicable to the actual instruments.

### Questions for Product / Business owner after professional schedules

1. For BD-010, which approved tax/withholding facts should Terranex record, calculate from a versioned professional rule, withhold/post, report/export, or leave to an external system?
2. What control level and implementation priority apply to that scope, without changing the professional determination of law, rate, taxpayer, accounting, or filing authority?
3. For every BD, confirm only the commercial/operating discretion explicitly left open by the legal and accounting schedules; Product/Business approval cannot override mandatory treatment.

### Questions answerable from company documents before oral contact

- commercial register, articles, incorporation certificates, shareholder/partner registers, group chart;
- board/general-assembly resolutions and authority matrix;
- executed investor/partner/lender agreements, templates, schedules, side letters, amendments;
- title deeds and asset-control documents;
- bank account ownership, statements, remitter data, GL/trial balance, current-account ledgers;
- capital increases, calls, contributions, refunds, transfers, distributions, reinvestments;
- loan/intercompany/due-to-from agreements and schedules;
- historical fee invoices/calculations, distribution computations, notices, certificates;
- tax registrations, returns, withholding certificates, taxpayer-regime evidence;
- past entry/exit/default/transfer/succession cases and associated approvals.

## 12. External validation

**Access status:** network research was available. Access date for all links below: 2026-08-16.

| Source | Proposition supported | Jurisdiction/currentness | Authority level |
|---|---|---|---|
| [GAFI — company incorporation services](https://www.gafi.gov.eg/English/eServices/Pages/DepartmentService.aspx?DSID=7) and [Companies Law 159/1981 official-hosted translation](https://www.gafi.gov.eg/English/StartaBusiness/Laws-and-Regulations/Documents/Lawno159oftheyear1981.pdf) | legal form, articles/incorporation, Commercial Register and partner/share records are document facts | Egypt; official site, page accessed 2026; counsel must confirm amendments/current Arabic law | official/government; legal review still mandatory |
| [IAS 32 Financial Instruments: Presentation, 2024 edition](https://www.ifrs.org/content/dam/ifrs/publications/html-standards/english/2024/issued/ias32.html) | liability/equity classification follows contractual substance/obligation; offset only under paragraph 42 criteria | international; 2024 edition | mandatory only for entities applying the relevant IFRS framework |
| [IFRS 10 Consolidated Financial Statements](https://www.ifrs.org/content/dam/ifrs/publications/html-standards/english/2021/issued/ifrs10.html) | control, not product naming, drives consolidation | international; official published standard page | same qualification |
| [IFRS 11 Joint Arrangements, 2024 edition](https://www.ifrs.org/content/dam/ifrs/publications/html-standards/english/2024/issued/ifrs11.html) | rights to assets/obligations versus rights to net assets drive classification; separate vehicle alone is not conclusive | international; 2024 edition | same qualification |
| [IAS 24 Related Party Disclosures, 2026 edition](https://www.ifrs.org/content/dam/ifrs/publications/html-standards/english/2026/issued/ias24.html) | related-party transactions, outstanding balances and commitments require identification/disclosure | international; 2026 edition | same qualification |
| [IAS 40 Investment Property, 2025 edition](https://www.ifrs.org/content/dam/ifrs/publications/html-standards/english/2025/issued/ias40.html) | fair-value-model changes are recognized in P&L; unrealized does not mean “never accounting profit” | international; 2025 edition | same qualification; classification must first apply |
| [IFRS 13 Fair Value Measurement, 2025 edition](https://www.ifrs.org/content/dam/ifrs/publications/html-standards/english/2025/issued/ifrs13.html) | provides measurement framework but does not itself require fair value | international; 2025 edition | same qualification |
| [IAS 7 Statement of Cash Flows, 2025 edition](https://www.ifrs.org/content/dam/ifrs/publications/html-standards/english/2025/issued/ias7.html) | cash/cash-equivalent and cash-flow reporting do not define distributable cash | international; 2025 edition | same qualification |
| [IAS 10 Events after the Reporting Period, 2022 edition](https://www.ifrs.org/content/dam/ifrs/publications/html-standards/english/2022/issued/ias10.html) | distribution/dividend liability timing depends on declaration/obligation | international; 2022 edition | same qualification |
| [Egyptian Tax Authority — Law 199/2020 official PDF](https://www.eta.gov.eg/sites/default/files/2024-03/law_no.199-2020.pdf) and [ETA 2026 FAQ](https://portal.eta.gov.eg/ar/alasylt-alshayt) | Egyptian distribution/withholding treatment is law/regime/recipient dependent and has later exemptions/changes; no repository-wide rate is safe | Egypt; 2020 law plus 2026 official FAQ | mandatory law/current administration, but exact current taxpayer result unresolved |
| [ILPA 2025 Capital Call & Distribution Template Guidance](https://ilpa.org/wp-content/uploads/2025/09/ILPA-Suggested-Guidance-2025-Final.pdf) | mature practice ties values to LPA/accounting, distinguishes transaction purpose, vehicle boundary, commitment impact, recallability, carry/clawback | global private-capital practice; released Sep 2025 | industry practice only; not Egyptian law or company policy |

### External evidence gaps still unresolved

- no current legal opinion on المجموعة العربية المتحدة's legal identity, shareholder/partner structure, assets, or contracts;
- no current Egyptian counsel conclusion on whether the described activity is regulated fundraising/fund/securities activity under the actual facts;
- no verified consolidated current Arabic-law analysis of capital maintenance, distributions, lending/cash pooling, set-off, transfer, succession, insolvency, or notices;
- no tax-professional confirmation of 2026 ETA law/regime/treaty applicability to this taxpayer and each recipient;
- no confirmation whether Egyptian Accounting Standards, IFRS, another basis, or management-only books govern each entity;
- no accountant conclusion on Real Estate/Agriculture/Livestock classification or valuation;
- no external company documents were available in the repository.

External evidence validates constraints and professional routing. It does **not** answer the company's optional economics.

## 13. Final OWNER-ONLY question set — DRAFT ONLY, **NOT YET SENT**

The twelve drafts below preserve BD-001…BD-012 as separate canonical decisions. Shared schedules are evidence-collection aids only. BD-010's final system-scope answer belongs to the authorized Product/Business decision-maker (which may or may not be the company owner); its professional tax determination is not owner-owned. Bracketed schedules do not yet exist; therefore all twelve currently fail owner-only test condition 6 (known context pre-filled), and some fail conditions 5/7 until professional review.

### OQ-01 / BD-001 — Portfolio legal-status confirmation

«أرفقنا [جدول الكيانات والعقود وربطها بأسماء Terranex] بعد مراجعته قانونيًا ومحاسبيًا. هل تؤكدون أن ربط كل محفظة بالصفة القانونية/التعاقدية المبينة صحيح، وما التجميع الإداري الذي تريدونه؟ لا تنشئ الإجابة صفة قانونية جديدة ولا تحسم نطاق مشاركة المستثمر.»

### OQ-02 / BD-002 — Funding sources

«راجعوا عمود “مصدر التمويل/المموّل” في [جدول التمويل المستخرج من العقود والبنوك والدفاتر]. هل الجدول كامل وصحيح، وما فئات المصادر التي تسمحون بها مستقبلًا؟ لا تختاروا هنا الأداة أو القيد؛ ذلك قرار BD-005 مستقل.»

### OQ-03 / BD-003 — Participation scope

«وفق [جدول العقود]، هل نطاق كل نموذج جديد مشروع محدد، أم كيان/مجموعة محددة، أم يسمح بالاثنين؟ وهل تسمحون بشروط مختلفة لنفس الطرف بين النطاقات؟ هذه الإجابة لا تحدد معنى الملكية في BD-004 ولا تسمح تلقائيًا بدمج النتائج.»

### OQ-04 / BD-004 — Meaning of the legal/economic interest

«استخرج المستشار في [جدول الحقوق] نوع الحق وصاحبه ونطاقه وتاريخ سريانه. هل يؤكد الجدول الغرض التجاري المقصود لكل نموذج جديد؟ لا يُعامل الحساب الرأسمالي أو الدفع أو نسبة التخصيص كملكية قانونية من تلقاء نفسه.»

### OQ-05 / BD-005 — Funding mechanism and authority

«لكل مصدر مؤكد في BD-002، أرفقنا الأداة القانونية والمعالجة التي اقترحها المحاسب في [جدول التمويل]: مساهمة/رأس مال، حساب جارٍ، قرض، صرف شركة، أو غير ذلك، مع الرد/الفائدة/الضمان. ما الأدوات التي تسمحون بها مستقبلًا، ومن يعتمد كل أداة وإصدار طلب الدفع؟»

### OQ-06 / BD-006 — Profit and loss assignment

«بعد أن أعد المحاسب والمستشار [جدول توزيع النتيجة] لكل نموذج — فئات النتيجة، ترتيب رد رأس المال، نسب/مراحل الربح، الخسارة والعجز، تاريخ السريان والتقريب — هل تعتمدون الغرض التجاري المبين أم تطلبون تعديلًا للعقود الجديدة؟ لا تُختار نسبة عامة خارج العقد.»

### OQ-07 / BD-007 — Valuation use after professional treatment

«حدد المحاسب معالجة التقييم وحدد المستشار أي حق تعاقدي في [جدول التقييم]. ضمن الحدود المعتمدة فقط، هل تستخدمون التقييم في معلومات الإدارة أو قرارات الدخول/الخروج، وما الموافقات المطلوبة؟ الاعتراف المحاسبي والسيولة القابلة للتوزيع ليسا اختيارًا شفهيًا هنا.»

### OQ-08 / BD-008 — Discretionary reserve and distribution governance

«بعد خصم الالتزامات والقيود القانونية/التعاقدية والمحاسبية في [جسر النقد المتاح]، ما الاحتياطي الإداري والحد الأدنى للسيولة الذي تعتمدونه، وما دورية الاقتراح وحدود وسلطات الاعتماد؟ حددوا الأغراض التي تريدون دعمها مستقبلًا؛ النظام الحالي يدعم توزيعًا مرتبطًا بتخصيص موجب فقط ولا يدعم رد رأس المال/رد الفائض/التوزيع العيني/القابل لإعادة الاستدعاء.»

### OQ-09 / BD-009 — Operator compensation

«بعد استخراج [جدول أتعاب وحصة المشغّل] من العقود والفواتير، ما الشروط التجارية التي تعتمدونها للنماذج الجديدة: نوع المقابل، أساسه، توقيته، الإعفاءات/المقاصات، والنطاق؟ يحدد المحاسب القيد والضريبة ويعتمد المستشار الصياغة والتعارضات.»

### OQ-10 / BD-010 — Terranex tax/withholding scope

«حدد المختصون في [جدول الضرائب والاستقطاعات] القانون والنسبة والجهة الملزمة والمعالجة لكل حالة. استنادًا إلى الجدول فقط، ماذا يجب أن يفعل Terranex لكل بند: يسجل مبلغًا معتمدًا، يحسب بقاعدة مهنية مُصدَّرة، يستقطع ويرحّل، يجهز تقريرًا/تصديرًا، أم يؤجل لنظام خارجي؟»

### OQ-11 / BD-011 — Permitted cross-Project treasury actions

«ضمن الآليات التي أجازها [رأي المحاسب والمستشار] فقط، أي حركة مستقبلية تسمحون بها بين النطاقات المحددة؟ حددوا الغرض والحد والمدة والموافقين. لا يسمح الرد بدمج الأرباح/الخسائر أو عرض الصافي إلا إذا نص الجدول المهني صراحة.»

### OQ-12 / BD-012 — Lifecycle discretion left open by contracts

«يبين [جدول دورة الحياة القانوني] ما يحكمه القانون والعقد. للخانات المفتوحة فقط، هل تسمحون بالحدث، ومن يوافق، ومتى يسري، ومتى تجب الإحالة للمستشار؟ يشمل ذلك الدخول/الزيادة/الانسحاب/الخروج/النقل/التعثر/الوفاة أو تغير الهوية.»

### Owner-only test result

| Condition | Result now |
|---|---|
| repository cannot answer company choice | PASS for the narrow discretionary residue |
| external authority cannot answer company-specific choice | PASS for the narrow residue |
| not merely implementation detail | PASS only after BD-010 is split: professional tax determination first, Product/Business system-scope decision second; PASS for the twelve staged drafts |
| materially changes behavior/rights/reporting | PASS |
| owner/company record is correct authority | PARTIAL until lawyer/accountant separate mandatory facts |
| technically known context pre-filled | **FAIL** |
| alternatives complete/non-leading | **FAIL until schedules exist** |
| understandable without engineering knowledge | PASS for draft wording, subject to Arabic owner review |

## 14. Code/runtime corrections required before owner contact

A separate corrective engineering PR is required. It must not resolve any BD item or implement company policy. Minimum safe scope:

1. introduce an enforceable database/runtime policy-disable gate for all S5 write RPCs while relevant BDs are OPEN, or revoke client execution until explicit activation exists;
2. remove S5 partner-capital/investor-statement dependencies and values from generic pilot/control readiness while policy is disabled;
3. remove the mandatory investor/agreement/commitment presupposition from real-project intake; represent the funding-model section as policy/document blocked or conditionally applicable;
4. prevent S1 activation/call and the separate OWNER-gated `attach_contribution_cash` posting from being used as universal target-company funding; at minimum de-surface/gate each pending confirmed source, instrument, and authority;
5. correct misleading close/distribution and “realized result” labels before using those values as owner context;
6. if S5 is ever re-enabled later, redesign/revalidate allocable-result sources for all sectors/revenue categories, the current allocation-based distribution ceiling, typed purpose/ordering for any newly supported return-capital/refund/in-kind/recallable flows, capacity formula, and bank reconciliation;
7. extend permanent policy tests across SQL grants/view dependencies, runtime labels, readiness, demo boundaries, and indirect reads — not direct TypeScript imports only.

This corrective PR is a policy-safety and correctness prerequisite, **not R15**.

## 15. Documentation contradictions

1. `R14_TARGET_COMPANY_DECISION_PACK_AR.md` says the pack is formally issued and awaiting answers; this audit finds it NOT READY.
2. `OPEN_BUSINESS_DECISIONS.md` repeats “issued to the company”; no repository evidence records actual delivery or authorized receipt.
3. `R14_POLICY_IMPACT_MATRIX.md` globally calls S5 dormant despite executable RPCs, posted demo economics, S7 dependencies, and operational runbooks.
4. The matrix says the only live leak was corrected; intake still mandates the unresolved investor/funding shape.
5. R10/investor copy says entitlement/allocation/distribution fields are inactive while pilot/control surfaces expose indirect partner-capital/investor-statement values.
6. Canonical docs say no policy-dependent behavior ships while BDs are OPEN; S1 and S5 behavior contradicts that boundary.
7. Greenfield/R14 use 13 narrative questions while the register/pack has 12 IDs.
8. “Realized result” is not one consistent finance measure across S4, S5, F10/R8, Agriculture, and Livestock.
9. Current/historical status documents use different SHAs and phase claims without one controlling current-contact banner.
10. The matrix's statement “no contradiction found” is disproved by C-02 through C-05 and H-01 through H-07.

## 16. Questions count and disposition summary

- **Before audit:** 12 numbered owner questions; at least 44 atomic prompts.
- **After audit:** 12 separate conditional, pre-filled owner/Product-Business confirmation drafts aligned one-to-one with BD-001…BD-012; 0 ready to send.
- **Removed from owner:** no BD ID. Removed only professional law/rate/accounting subquestions from BD-010, accounting recognition from BD-007, and legal/accounting/document facts throughout all BDs.
- **Merged for evidence intake only:** one linked schedule may support BD-002/005; one legal matrix may support BD-001/003/004; shared economics/cash packs may support other related items. **The decisions and resolution records remain separate.**
- **Rewritten:** all twelve owner/Product-Business decision prompts.
- **Added:** 12 professional schedules/subquestions in §9, routed before owner contact.

## 17. Remaining uncertainty and final gate

Remaining uncertainty is substantial because the repository contains no company legal/accounting evidence set: no commercial-register extract, articles, investor contracts, partner/share register, loan/current-account agreements, bank ownership schedule, historical funding/distribution computation, tax file, legal opinion, or accountant policy memorandum.

The implementation proves what Terranex does; it does not prove what المجموعة العربية المتحدة is entitled or required to do. External standards prove constraints/patterns; they do not prove which optional arrangement the company uses.

### Final status

- **Owner contact:** **NOT READY**.
- **Corrective engineering PR required first:** **YES**.
- **Company-document intake required first:** **YES**.
- **Accountant review required first:** **YES**.
- **Lawyer review required first:** **YES**.
- **R15 started:** **NO**.
- **Any BD resolved:** **NO**.
- **S5 activated for target-company policy:** **NO authorization exists; current technical executability is a defect, not an approved activation**.
