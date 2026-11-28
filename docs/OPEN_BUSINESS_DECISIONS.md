# Terranex — Open Business Decisions

**Status:** Canonical unresolved-business register  
**Decision authority:** Terranex product owner for general product boundaries/mechanics; the authorized owner/business decision-maker of the target company for that company’s legal, funding, investor, ownership, allocation, and distribution facts; qualified accounting/legal review where the consequence requires it  
**Rule:** An OPEN item is not a backlog feature and is not permission to invent a default. It blocks only the implementation that depends on that unresolved decision.

## 1. Purpose

Terranex deliberately separates proven/common product mechanics from company-specific legal, investor, funding, ownership, allocation, distribution, and cross-project rules.

When an implementation needs a material business rule that is not explicitly supported by the canonical Greenfield documents or an approved decision:

1. search the canonical documents and existing approved ADRs;
2. distinguish implementation fact from business authority;
3. use external standards/products only as evidence of possible patterns, never as proof of this company’s rule;
4. record or reference the unresolved item here;
5. stop only the dependent scope;
6. continue unrelated bounded work that does not require the answer.

Do **not** create a generic rules engine, nullable schema, guessed enum, fallback percentage, or “temporary” business default to avoid this stop.

## 2. Canonical baseline while these items are open

Until resolved:

- `InvestmentPortfolio` is a management/reporting parent for independent Investment Projects.
- Portfolio is **not automatically** a fund, legal entity, SPV, pooled vehicle, or shared investor pool.
- Investment Project remains the operational, budget, financial-attribution, execution, and close boundary.
- Sector assets/events remain project-bounded.
- Portfolio capital deployment/project funding is distinct from investor contribution, ownership, result allocation, distribution, and payment.
- Portfolio roll-ups are derived from project-authoritative facts and do not create a second ledger.
- No cross-project cash/result netting, recycling, transfer, pooling, or entitlement exists by implication.

## 3. Open decisions

**R14 status (2026-08-16):** the owner-facing questionnaire for all twelve items has been issued to the target company المجموعة العربية المتحدة as `docs/specs/owner/R14_TARGET_COMPANY_DECISION_PACK_AR.md`, with the technical mapping and dormant-code audit in `docs/specs/owner/R14_POLICY_IMPACT_MATRIX.md`. Issuing the questionnaire resolves nothing: every item below remains OPEN until the authorized owner's explicit decision is recorded per §5.

**Post-R14 policy-safety hotfix — MERGED / CLOSED (2026-08-16):** PR #151 corrected the R14-discovered live intake policy leak (ownership/allocation configuration surfacing and the readiness dependency on allocation rules). This is a policy-safety correction, not a business-policy implementation: it resolves no decision, invents no target-company investor policy, keeps dormant S5 machinery dormant, and leaves all twelve items OPEN. The next gate is **PRE-OWNER INDEPENDENT EVIDENCE AUDIT**; R15 has not started and remains blocked for policy-dependent scope.

**Pre-owner policy-safety boundary — corrective engineering (2026-08-16):** the independent pre-owner evidence audit (the pre-owner evidence audit — Git history, removed 2026-10-22) established that R1–R13 contain valid policy-independent work but that several investor/funding/allocation/distribution mechanisms remained policy-reachable while BD-001…BD-012 are OPEN. A corrective engineering pass (ADR 0033, migration `20260816062000_pre_owner_policy_safety.sql`) now enforces a policy-activation boundary: S5 allocation/distribution writes and the `attach_contribution_cash` contributed-capital posting fail closed with `target-company investor policy is not activated` until an approved `policy_authority` exists; S1 governing-agreement activation and capital-call issuance are raised to OWNER authority; and intake no longer mandates investor + agreement + commitment. This **retains every mechanism but makes them policy-inert**, preserves R1–R13 policy-independent capabilities, keeps all twelve items OPEN, and does not start R15.

| ID | Status | Decision required from owner | Blocks |
|---|---|---|---|
| BD-001 | OPEN | Is the Portfolio only a management grouping, or is there a real legal/entity/contract boundary above projects? If there is one, what exactly is it? | Any legal/fund/SPV/entity semantics at portfolio level |
| BD-002 | OPEN | Who actually provides capital to projects: operating company, named investors/partners, project-specific investors, lenders, or a mixture? | Universal funding-source model |
| BD-003 | OPEN | Do investors participate at Portfolio level, Project level, or both? Can the same investor have different terms by project? | Portfolio investor membership and entitlement model |
| BD-004 | OPEN | What does “ownership” legally/economically mean in the first company: company shares, project interest, contractual profit share, capital-account units, another basis, or combinations? | Ownership schema/rules and ownership-based reporting |
| BD-005 | OPEN | How are projects actually funded: company cash deployment/current account, loan, equity contribution, capital call/contribution, or another mechanism? Which mechanisms can coexist? | Portfolio-deployment posting and project-funding workflows |
| BD-006 | OPEN | How are realized project profits and losses assigned: ownership, funding ratio, fixed shares, project-specific agreement, operator share/fee, or another rule? | New allocation-rule behavior and partner result statements |
| BD-007 | OPEN | Are unrealized valuations ever allocable or distributable, or are they management information only? | Valuation-to-entitlement/distribution behavior |
| BD-008 | OPEN | What reserves, minimum cash, outstanding obligations, loss carryforward, and other deductions define distributable cash? | Distribution-availability formula beyond already-approved behavior |
| BD-009 | OPEN | Are there management/operator fees, carried/operator shares, or similar economics? If yes, what is their legal/accounting basis and calculation? | Fee/operator-share rules |
| BD-010 | OPEN | What tax/withholding obligations affect investor distributions or project income in the first operating company, and which are recorded vs calculated by Terranex? | Tax/withholding calculation or posting automation |
| BD-011 | OPEN | Can cash/capital move or be recycled between projects? If yes, under what approval and accounting/legal mechanism (due-to/from, loan, capital transfer, other)? Can project profits/losses be netted? | Cross-project transfers, pooling, recycling, and netting |
| BD-012 | OPEN | What happens for investor entry/exit, interest transfer, partial withdrawal, funding default, death/succession, or legal-identity change, and which notices/statements are contractual requirements? | Investor lifecycle/transfer workflows and contractual notice model |

## 4. R13 hard stop

The R0 canonical realignment defines the management hierarchy and the R1–R17 implementation gates (see `docs/ROADMAP_R0_R17.md`). R1–R13 implement only behavior that does **not** require guessing the open investor/legal/economic decisions above. The strategy is **Build Everything Independent First**: complete every feature whose correctness does not depend on unresolved policy; defer only the smallest rule-dependent portion.

**After R13, do not start a portfolio/investor-economics expansion that depends on any OPEN item.** The relevant item must first be changed to `RESOLVED`, with the explicit owner decision and evidence recorded. This hard stop does not block independent sector operations, bug fixes, security work, or other bounded product work that does not depend on the unresolved rule.

Resolving the OPEN items is exactly the small **R14 policy pack** asked of the target company owner after R13: it spans legal structure (BD-001), funding source (BD-002), participation level (BD-003), ownership basis (BD-004), project funding (BD-005), profit/loss assignment (BD-006), valuation allocability (BD-007), distributable-cash formula (BD-008), operator economics (BD-009), tax/withholding (BD-010), cross-project cash movement (BD-011), and investor lifecycle (BD-012). Until then, no investor profit, entitlement, ownership, or distributable number may be shown as if it were final.

## 5. Resolution record required

When resolving an item, update its status and append a record containing:

```text
Decision ID:
Status: RESOLVED
Decision date:
Decision owner:
Business decision:
Applies to: organization / portfolio / project / agreement scope
Effective date or version:
Business evidence/reference:
Accounting review required? yes/no + reference
Legal review required? yes/no + reference
Affected canonical docs/ADRs:
Implementation explicitly authorized:
Still deferred / not implied:
```

An explicit answer from the authorized decision-maker is valid business evidence once it is recorded here (or in a linked approved ADR) with its scope and effective context. An unrecorded casual remark, UI label, legacy field, synthetic demo, existing code path, or matching monetary amount is not sufficient authority by itself.

## 6. Owner input log (not a resolution)

This log keeps answers the product owner gave in conversation. An entry here is evidence for a later decision. It does not change any status above and does not authorize investor logic (§5 still governs).

| Date | Question asked | Answer given | Maps to | Effect |
|---|---|---|---|---|
| 2026-11-28 | Is the money in the projects from external investors, or only the owner's own money? | External investors ("مستثمرين"), via the product owner's Telegram reply. | BD-002 (who provides capital), and it makes BD-003, BD-004 and BD-006 to BD-012 relevant rather than optional | BD-002 stays OPEN: the answer names the source class but not which investors, which projects, or lenders and co-investment by the operating company. BD-001 to BD-012 stay OPEN. No investor logic is built. |
| 2026-11-28 | Do investors join one project, or the whole portfolio (and can one investor have different terms per project)? | Project by project, not the portfolio; terms can differ per project. The product owner replied "اوك اعتمد" to the status update whose only open investor question was this one, via Telegram message 30250197. | BD-003 | BD-003 stays OPEN as a formal resolution: the reply approves the question asked in a status message rather than a signed decision, and it does not say whether one investor may join several projects under different terms or whether portfolio-level participation is ever allowed. BD-001 to BD-012 stay OPEN. No investor logic is built. |
