# Terranex Greenfield — 01 Product Charter & Market

**Status:** Foundational baseline v1  
**Date:** 2026-08-10  
**Authority:** This greenfield set supersedes legacy Terranex product assumptions. Legacy code and documents are evidence only, never requirements.

## 1. Executive decision

Terranex is an Arabic-first **Investment Operations OS** for owner-managed investment companies and private partnerships operating real-estate, crop-farming, and livestock projects.

Inside an Organization, Terranex uses **Investment Portfolio → Investment Project** as the management hierarchy. The Portfolio groups independent projects for owner-level planning, capital-deployment visibility, and consolidated management reporting. It is **not automatically a fund, legal entity, SPV, pooled vehicle, or shared investor pool**. Each Investment Project remains the operational, budget, financial-attribution, execution, and close boundary for one deal/venture.

It connects four things that are usually split across spreadsheets, chat, paper files, and accounting software:

1. the approved investment agreement and participation history where those terms actually apply;
2. the real operational activity of each project;
3. project cash, obligations, realized result, approved capital activity, and traceable management roll-ups;
4. approvals, evidence, statements, and an immutable audit trail.

Terranex v1 is **not** a public investment marketplace, crowdfunding platform, broker, custodian, bank, wallet, or statutory accounting/ERP replacement. Public fundraising, pooled retail products, payment custody, and regulated investment advice are outside the product until separately licensed and designed.

## 2. Launch customer

### Primary ICP

An Egyptian or MENA owner-managed investment company with:

- 3–30 active projects;
- 2–50 investors/partners;
- one finance person plus sector operators;
- real-estate deals and/or farms/herds;
- operations currently coordinated through Excel, WhatsApp, paper receipts, and an external accountant;
- a recurring need to answer: **what do we own, what happened, how much did it cost, what is each partner entitled to where applicable, and what needs approval now?**

### Economic buyer

The managing partner, company owner, CFO, or investment director. They pay to reduce disputes, missed obligations, spreadsheet reconciliation, slow investor reporting, and invisible project leakage.

### Daily users

| User | Job | Success signal |
|---|---|---|
| Managing partner | See portfolio truth and approve material actions | No surprises; approvals take minutes |
| Finance officer | Record money once and reconcile it to projects/investors | Every amount has source, allocation, and status |
| Sector operator | Capture work, quantities, evidence, and issues from the field | Same-day reliable operational record |
| Investor/partner | See own position, notices, documents, and distributions where governed | Fewer calls and statement disputes |
| Auditor/accountant | Trace balances to immutable events and evidence | Reperformance without spreadsheet archaeology |

## 3. Problem statement

Generic accounting systems know invoices and journal entries but usually do not know the operational object that created value: a land deal, development phase, crop cycle, harvest lot, herd cohort, or animal event. Sector tools know field or herd activity but generally do not maintain investment agreements, investor capital accounts, capital calls, allocations, and distributions. Investor portals communicate balances but do not originate operational truth.

Terranex owns the connective layer: **portfolio context → project → operation → money → approved entitlement where applicable → evidence**.

## 4. Jobs to be done

1. When organizing investments, group independent projects into a management Portfolio without merging their economic or operational truth.
2. When starting a project, establish its legal/operational context, approved participants/terms where known, budget, asset, and controls before money moves.
3. When money or goods move, record the event once with amount, currency, counterparty, project, purpose, evidence, approval, and accounting effect.
4. When field work happens, capture the sector-specific event and connect it to cost, inventory, yield, health, risk, and responsible person.
5. When management asks about performance, show portfolio roll-up and project drill-down across actual cash, accruals, commitments, cost-to-date, realized result, valuation, and forecast without mixing them.
6. When profit is allocated or cash distributed under an approved investor agreement, apply the exact governing version, preserve calculation inputs, require approval, and generate partner statements.
7. When a dispute or audit occurs, reproduce who did what, when, under which approved terms, with which evidence and resulting balances.

## 5. Product principles

| Principle | Product consequence |
|---|---|
| Portfolio organizes management; Project owns execution/attribution | Portfolio rolls up independent projects; every material operation and monetary event remains project-dimensioned |
| Sector truth stays sector-specific | No fake universal model for parcels, crop cycles, herds, or animals |
| Money is exact | Integer minor units, explicit currency, balanced postings, no floating-point arithmetic |
| Approved agreement drives entitlement | Ownership and allocation rules exist only when supported by effective-dated approved terms and are never overwritten |
| Cash is not profit | Cash, accrual profit, valuation, commitments, and distributable cash are separate measures |
| Capital deployment is not investor capital | Portfolio/project funding decisions are not automatically contributions, ownership, allocation, distribution, or payment |
| Evidence is first-class | Documents link to the event/version they support, not just a generic folder |
| Correction is reversal | Posted financial history is append-only; errors are reversed and reposted |
| Approval is a state transition | Sensitive actions cannot be “approved” by merely editing a status field |
| Arabic field reality first | RTL, mobile capture, weak-connectivity drafts, simple language, Latin/Arabic digit tolerance |
| Progressive depth | Fast daily capture first; accounting and audit depth remains available behind it |

## 6. Product boundaries

### Terranex owns in v1

- organization, memberships, roles, **investment portfolios**, projects, parties, and documents;
- Portfolio → Project management grouping and traceable project roll-up reporting;
- project investment terms, commitments, contributions, ownership interests, and effective versions **only where those business terms are explicitly approved**;
- cash accounts as operational subledgers, receipts/payments, obligations, approvals, and reconciliation status;
- project-level double-entry investment/operational subledger and approved partner capital accounts;
- real-estate acquisition/development/disposal tracking plus **basic rental-income recognition/receivable/collection for held property**;
- crop cycle planning, field activity, input use, harvest lots, inventory, and sales;
- herd/cohort operations, individual animal identity where justified, health/weight/birth/death/movement, input use, and sales;
- allocation, distribution proposals, approvals, payments, reversals, and investor statements only under approved governing rules;
- exports/integration contracts for statutory accounting and Egyptian e-invoicing later.

### Explicitly outside v1

- public offerings, crowdfunding, trading, tokenization, investment advice, KYC/AML decisioning, custody, or holding client money;
- payroll, full procurement suite, tax return preparation, statutory consolidation, depreciation/tax books, and full ERP;
- IoT, satellite imagery, automated valuation, bank API aggregation, and government submissions;
- complex private-equity waterfalls, carried interest, preferred-return catch-ups, and multi-GAAP reporting;
- **full lease administration/property management** such as tenant lifecycle, renewals, service charges, maintenance/work orders, and facilities operations; food processing/manufacturing; and slaughterhouse operations.

## 7. Competitive pattern study

The product combines mature patterns without copying any vendor’s data model:

| Product/category evidence | Mature pattern to adopt | What Terranex will not copy |
|---|---|---|
| Yardi Investment Suite connects investor portal, capital raising, investment accounting, debt, acquisitions, and asset operations | One connected investment record and self-service investor reporting | Enterprise breadth and real-estate-only assumptions |
| Juniper Square standardizes capital calls, distributions, capital accounts, notices, and review controls | Notice → review → approval → payment → statement lifecycle | Fund-admin complexity in the first MVP |
| AGRIVI centers farm, crop, field activity, team responsibility, inventory, and traceability | Cycle/field/activity/input/harvest records with operational accountability | Agronomy recommendation engine and supply-chain suite |
| AgriWebb tracks animals, pastures, health, weight, breeding, movement, RFID, and mobile records | Cohort-first livestock records with optional individual identity | Country-specific compliance modules in v1 |
| ILPA templates emphasize standardized, transparent capital-call/distribution notices | Consistent transaction types and investor-readable notices | Claiming ILPA compliance before a formal mapping audit |

These patterns are external evidence, not authority for the first company’s legal structure, ownership basis, contribution model, or profit-allocation rules.

## 8. Regulatory posture

The first commercial version is B2B operational software used by a company to manage its own/private projects and partners. It must not market investments or accept investor funds.

Before any public-investment or regulated-finance feature, obtain Egyptian legal review. Egypt’s FRA states that Law No. 5 of 2022 regulates FinTech use in non-bank financial activities, and in 2025 it issued controls for digital platforms offering real-estate fund certificates. That boundary is why public discovery, subscriptions, custody, and payment execution remain out of scope.

Required product wording:

- “operational and investment records,” not “regulated fund administration”;
- “record payment,” not “send/hold money”;
- “management valuation,” not “guaranteed value”;
- “calculated return,” never “promised return”;
- reports include accounting-policy and data-completeness disclaimers.

## 9. Business model and first revenue

### Sellable offer

**Founding-company implementation:** configure one organization, migrate up to 10 projects, train users, and provide 60 days of support.

Recommended commercial structure to validate willingness to pay:

- setup/migration fee;
- monthly subscription per organization tier, not per transaction;
- included operator and investor seats with a fair-use boundary;
- paid add-ons later for extra entities, custom statements, accounting integration, and advanced sector modules.

Pricing numbers are a commercial experiment, not a product requirement. The first sale should prove that a buyer will pay for project truth and partner transparency—not for generic dashboards.

## 10. North-star and guardrail metrics

### North-star

**Verified project events per active project per week**: posted operational/financial events with project, actor, date, evidence/status, and valid downstream impact.

### Activation

- organization created;
- first Portfolio created/selected and first project configured with sector;
- only required/approved agreement terms configured;
- opening balances/import reviewed;
- first funding/contribution event and first operating cost posted as applicable;
- first project statement generated.

### Value metrics

- time to produce project/partner statement where applicable;
- percentage of financial events fully allocated to project/purpose;
- unreconciled cash count and age;
- overdue approvals/obligations;
- percentage of sector events captured within 24 hours;
- number of corrections after period close;
- monthly active operating projects.

### Guardrails

- zero cross-organization data access;
- zero unbalanced posted journal batches;
- zero destructive edits to posted events;
- every distribution traceable to approved calculation and payment;
- never label estimated/unapproved figures as actual or distributable;
- never infer portfolio-level investor economics from project membership or cash movement.

## 11. Kill criteria and sequencing

Technical sector expansion was deliberately sequenced **Real Estate → Agriculture → Livestock** so the shared core could be proven without competing sector-specific ownership, finance, payment, approval, or audit engines. That authorized construction sequence is now complete through Agriculture GF-019 and Livestock GF-024. Preserve those bounded contexts and technical evidence; do not treat the historical sequence as an instruction to reopen or rebuild a completed sector.

The Portfolio realignment is a **canonical management-model correction**, not authorization to rebuild the existing runtime or to invent portfolio/investor economics. Implementation that depends on unresolved ownership, funding, pooling, allocation, distribution, or cross-project rules must stop at the relevant roadmap gate until the company owner’s decision is recorded in `docs/OPEN_BUSINESS_DECISIONS.md`.

Validate common behavior against established industry patterns, authoritative standards, public/reference artifacts, and executable end-to-end scenarios; do not wait for customer interviews to begin implementation. Real customer evidence remains mandatory before claiming customer validation, buyer UAT, a paid pilot, or the commercial Phase 2/3 exits. When the first Egyptian company onboards, represent its differences through configuration, versioned policies, templates, or bounded extensions—not a tenant-specific fork. Stop or narrow any feature that cannot be justified as common product behavior or isolated cleanly from company-specific practice.

## 12. Foundational decisions

| ID | Decision |
|---|---|
| P-001 | Greenfield product; legacy Terranex has no automatic authority |
| P-002 | B2B private investment operations, not public investing/crowdfunding |
| P-003 | Egypt launch, Arabic/RTL first, EGP base with multi-currency transaction support |
| P-004 | One investment core plus three bounded sector contexts |
| P-005 | Exact double-entry operational/investment subledger; statutory accounting is integrated/exported |
| P-006 | First paid pilot ships platform core plus the sector of the first contracted customer |
| P-007 | Technical sector construction was sequenced Real Estate first, Agriculture second, Livestock third; technical completion remains separate from customer/commercial validation |
| P-008 | Investment Portfolio is the organization’s management/reporting parent above independent Investment Projects; it is not automatically a fund, legal entity, SPV, pooled vehicle, or investor pool |
| P-009 | Portfolio capital deployment/project funding is distinct from investor contribution, ownership, allocation, distribution, and payment; unresolved investor/legal/economic rules are explicit business decisions, never inferred defaults |

## Sources

- [IFRS IAS 40 — Investment Property](https://www.ifrs.org/issued-standards/list-of-standards/ias-40-investment-property/)
- [IFRS IAS 41 — Agriculture](https://www.ifrs.org/issued-standards/list-of-standards/ias-41-agriculture/)
- [IFRS 11 — Joint Arrangements](https://www.ifrs.org/issued-standards/list-of-standards/ifrs-11-joint-arrangements/)
- [Yardi Investment Management](https://www.yardi.com/market/investment-management/)
- [Juniper Square investor reporting](https://www.junipersquare.com/platform/investor-reporting)
- [AGRIVI Farm Enterprise](https://www.agrivi.com/products/360-farm-enterprise/)
- [AgriWebb animal management](https://www.agriwebb.com/us/solutions/animal-management/)
- [ILPA Capital Call & Distribution Template](https://ilpa.org/industry-guidance/templates-standards-model-documents/ilpa-templates-hub/ilpa-capital-call-distribution-template/)
- [Egypt FRA — Financial Technology](https://fra.gov.eg/en/%D8%A7%D9%84%D8%AA%D9%83%D9%86%D9%88%D9%84%D9%88%D8%AC%D9%8A%D8%A7-%D8%A7%D9%84%D9%85%D8%A7%D9%84%D9%8A%D8%A9)
- [Egypt FRA — Digital real-estate fund platforms](https://fra.gov.eg/fra_news/%D8%A7%D9%84%D8%B1%D9%82%D8%A7%D8%A8%D8%A9-%D8%A7%D9%84%D9%85%D8%A7%D9%84%D9%8A%D8%A9-%D8%AA%D8%B5%D8%AF%D8%B1-%D8%B6%D9%88%D8%A7%D8%A8%D8%B7-%D8%A5%D9%86%D8%B4%D8%A7%D8%A1-%D8%A7%D9%84%D9%85%D9%86/)
