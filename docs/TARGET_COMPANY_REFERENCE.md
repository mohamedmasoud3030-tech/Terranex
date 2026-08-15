# Terranex — Target Company Reference

**Status:** Product-discovery evidence for the first target company; not a canonical legal/accounting contract  
**Working company name supplied by the product owner:** المجموعة العربية المتحدة  
**Market context supplied by the product owner:** Egypt  
**Source basis:** owner-provided audio/transcript shared during product discovery on 2026-08-15. The audio itself is not stored in this repository.  
**Rule:** source-derived facts below may guide product priorities; anything not established by the source remains an OPEN decision and must not be invented.

## 1. What the source actually establishes

The target business operates or intends to operate across:

- Real Estate;
- Agriculture;
- Livestock.

The source describes a private investment-operator model rather than a generic project-management business. The relevant operating evidence is:

1. Investor capital is discussed in connection with sector-oriented investment portfolios/groupings.
2. A sector portfolio may contain multiple projects; the livestock example explicitly uses several projects as a diversification mechanism rather than placing all exposure into one project.
3. Each project is expected to keep financially separate accounts so project performance can be inspected independently even when management reports aggregate the portfolio.
4. The operator's work includes sourcing opportunities, feasibility work, bringing relevant specialists, establishing projects, and ongoing management.
5. Investor transparency is a core commercial promise: the investor should be able to see what was purchased, what was spent, project progress, supporting photos/videos/documents, financial accounts, profit, and loss.
6. The business objective includes creating durable real assets and operating businesses, not merely recording short-term cash movements.
7. The source indicates that the operator's own economic benefit should be aligned with investor success, but it does not establish the formula or legal basis.
8. A Real Estate strategy described in the source is: acquire for cash when an asset can be bought at a discount, hold the asset, earn rental income where applicable, benefit from approved value appreciation, and eventually dispose of it.

These facts support the existing Terranex product hierarchy and the current product direction:

`Organization → Investment Portfolio → Investment Project → Assets / Sector Operations → Financial Facts → Management Roll-up`

They do **not** turn `InvestmentPortfolio` into a legal fund or accounting ledger.

## 2. What the source does NOT establish

The audio/transcript does not prove any of the following and Terranex must not fabricate them:

- the legal nature of a Portfolio;
- whether a Portfolio is a fund, SPV, company, contractual pool, or only a management grouping;
- whether investors legally own company shares, project interests, asset interests, contractual profit rights, capital-account units, or another instrument;
- whether investors participate at Portfolio level, Project level, or both;
- whether the operating company co-invests and on what terms;
- the operator fee, carried share, management fee, performance fee, or other compensation formula;
- the loss-allocation formula;
- whether profit/loss is netted across projects;
- whether capital/cash may be moved or recycled across projects and by what legal/accounting mechanism;
- reserve policy or distributable-cash formula;
- reinvestment rules;
- withdrawal, redemption, transfer, succession, or investor-default rules;
- the legal owner of each asset;
- tax/withholding treatment;
- custody, public solicitation, regulated-fund, or securities status.

Those items remain governed by `docs/OPEN_BUSINESS_DECISIONS.md` and the R13 → R14 hard stop in `docs/ROADMAP_R0_R17.md`.

## 3. Product consequences that are safe to build before owner-policy answers

The following capabilities are directly useful to the target company and do not require inventing investor entitlement rules:

- multiple Projects inside one management Portfolio;
- Project-separated operational and financial truth;
- Portfolio roll-up without a second ledger;
- full shared Procurement chain linked to the Finance Core;
- cash, obligations, receivables, payables, bank reconciliation, period close, reversal/repost, audit, and evidence;
- Real Estate acquisition, holding cost, basic rental income, approved valuation, and disposal;
- Agriculture operational cycles and profitability;
- Livestock herd/cohort operations and profitability;
- shared asset register and cross-sector performance reporting;
- Arabic/RTL owner-management UX;
- documents, photos/evidence, approvals, and material-event history;
- investor-facing read models for published project/portfolio updates and evidence, with entitlement-dependent amounts left inert;
- production hardening and full-company simulation.

## 4. Target-company acceptance lens

Before asking the company owner for the R14 policy pack, Terranex should be able to demonstrate a complete synthetic scenario that answers, without invented investor rights:

- Which Portfolio contains which Projects?
- Where is the organization's/project cash?
- What has been committed, received, invoiced, paid, and reconciled?
- What assets were acquired or produced?
- What did each Project cost and earn?
- Which results are realized and which are only approved valuations?
- Which projects are profitable, losing, delayed, or operationally exceptional?
- Can every material amount drill down to its Project, source transaction/event, approval, and evidence?
- Can management inspect Real Estate, Agriculture, and Livestock performance without mixing their operational truth?
- Can a permitted investor-facing view publish progress/evidence without exposing another investor or fabricating entitlement?

The core target metric remains **Reconciled Capital Traceability**: every material amount attributed to management reporting must have an explainable current state and drill-down path.

## 5. Hard stop for company-specific economics

After the independent product is complete and R13 full-company simulation passes, the target-company owner and the relevant signed/legal/accounting evidence are required for the remaining investor-policy layer.

Terranex must then resolve the corresponding `BD-001` through `BD-012` records before implementing company-specific ownership, allocation, distribution, operator economics, cross-project netting/recycling, or investor-lifecycle behavior.

Until then:

`mechanism Terranex can support ≠ rule this company actually uses`.
