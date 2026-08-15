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

## 4. R5 hard stop

The R0 canonical realignment may define the management hierarchy and the future R1–R5 implementation gates. R1–R5 may implement only behavior that does **not** require guessing the open investor/legal/economic decisions above.

**After R5, do not start a portfolio/investor-economics expansion that depends on any OPEN item.** The relevant item must first be changed to `RESOLVED`, with the explicit owner decision and evidence recorded. This hard stop does not block independent sector operations, bug fixes, security work, or other bounded product work that does not depend on the unresolved rule.

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
