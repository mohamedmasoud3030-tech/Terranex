# Terranex Greenfield — 08 MVP & Delivery Roadmap

**Status:** Execution baseline v3  
**Goal:** Reach a paid design partner quickly without compromising money, ownership, security, audit integrity, or inventing unresolved investor rules.

## 1. MVP decision

The sellable MVP remains the shared core plus the technically implemented Real Estate pack. The canonical management hierarchy is now **Organization → Investment Portfolio → Investment Project**:

1. Portfolio provides owner-level grouping, capital-deployment context, and consolidated management reporting;
2. Project remains the independent operational, budget, financial-attribution, execution, and close boundary;
3. Real Estate, Agriculture, and Livestock remain bounded sector contexts under Projects;
4. portfolio/investor legal and economic rules are not inferred from the hierarchy.

Real Estate remains the first commercial presentation path. Agriculture and Livestock technical construction is complete for the currently authorized scopes, but that does not make them commercially validated. Never create duplicate investment, finance, ownership, payment, approval, document, or audit cores for a sector or for Portfolio.

## 2. MVP promise

> “Across the portfolio and inside every project, Terranex shows what happened operationally, every pound in and out, what is due, the realized result, the approved terms that actually apply, and what needs action—with traceable approvals and evidence.”

If a feature does not help deliver or prove that promise for a contracted design partner, it does not enter MVP.

## 3. MVP scope

### Platform core — must ship

- organization, membership, role and project-scoped permission;
- **investment portfolio identity, Portfolio → Project management grouping, and traceable roll-up**;
- parties and project participants where applicable;
- investment project setup and lifecycle;
- immutable agreement versions with only the commitments/ownership/allocation rules actually approved for that project/company;
- private versioned documents and typed links;
- capital calls, contributions, investor capital rollforward only where an approved investor model requires them;
- obligations, receipts, payments, basic sales/collections;
- project cash accounts and CSV bank-statement reconciliation;
- balanced project subledger, posting rules, periods, close, reversal;
- approved result allocation and distribution approval/payment only under governing terms;
- approvals, tasks, exceptions, audit trail;
- Portfolio overview plus Project dashboard, capital statement where applicable, and project performance pack;
- Arabic/RTL responsive web; PWA installation and offline sector-event drafts are added only when the sector-capture slice proves the need;
- CSV import/export with controlled opening-balance workflow.

### First sector pack — real-estate default

- asset/parcel and acquisition record;
- title/due-diligence checklist and documents;
- development phase/milestones and budget vs actual/committed cost;
- valuation record with method/source/approval;
- **basic rental-income recognition, receivable, and collection for held property**;
- disposition, cost/proceeds, collection, and realized closeout.

### Not MVP

- public investor onboarding or marketplace;
- native money movement/bank connections;
- advanced waterfall/carry/preferred return;
- general ledger, tax returns, consolidation, payroll;
- AI advice/forecasting or automated valuation;
- IoT/satellite/RFID integration;
- **full lease administration/property management** including tenant lifecycle, renewals, service charges, maintenance/work orders, and facilities operations;
- full agronomy/dairy/processing;
- custom report builder and public API marketplace.

## 4. Thin vertical slices

Build working slices, not disconnected layers:

| Slice | User-visible outcome | Proof |
|---|---|---|
| S0 Foundation | Working Arabic app: authenticate, create organization, create/list/open Real Estate project shell | Two-tenant isolation, RLS, minimal audit |
| S1 Terms & funding | Activate approved agreement terms, call and receive capital where applicable | Capital rollforward and immutable version |
| S2 Cost & cash | Record obligation, approve/pay, reconcile bank | Balanced posting and evidence trail |
| S3 Sector operation | Capture one complete sector lifecycle path | Quantity/state rollforward + cost drilldown |
| S4 Revenue & result | Recognize sale/collection and project result | Carrying-cost/revenue postings and report |
| S5 Allocation & distribution | Allocate closed result, approve/pay distribution under approved terms | Investor statement and concurrency protection |
| S6 Close & correction | Close period, reverse/repost, regenerate reports | Locked period and complete audit chain |
| S7 Pilot hardening | Import customer project and operate one cycle | UAT, restore, security, support runbook |

Each implementation slice includes schema, domain, application, UI, permissions, tests, telemetry, and documentation before starting the next material slice. A documentation/governance slice such as R0 does not create runtime artifacts.

## 5. Delivery phases

### Phase 0 — Product foundation and reference validation (complete)

Outputs:

- approved Greenfield product, operating, domain, sector, finance, architecture, UX, and delivery baselines;
- product-first execution decision and explicit separation of common core, sector packs, and company configuration;
- first operating market set to Egypt and first sector-pack default set to real estate;
- legal/product boundary confirmed as a private B2B operational system with no public solicitation or custody;
- implementation assumptions marked for later professional, standards, and production validation.

**Exit:** the Greenfield baseline and product-first decision are approved and recorded. Customer interviews, a design partner, and customer documents are not prerequisites for Phase 1.

### Phase 1 — Executable foundation and first vertical slice

Outputs:

- one maintained Next.js application with minimal CI and validated environment contract;
- Supabase migration, Auth integration, default-deny RLS, and two-tenant tests;
- working Arabic/RTL organization and Real Estate project-shell flow;
- only the just-in-time decisions, commands, audit, and UI primitives used by that flow.

**Exit:** a fresh checkout installs, replays migrations, passes targeted gates, builds, and proves an authenticated member can create/open a project while another organization cannot access it.

### Phase 2 — Core vertical slices

Deliver S0–S2, then S4 financial foundation:

- project/party/agreement;
- capital call/contribution where governed;
- obligation/payment/reconciliation;
- documents/approval/audit;
- balanced subledger and basic project/capital statements.

**Exit:** an opening project can be imported and every financial balance reproduced.

### Phase 3 — First sector and result lifecycle

Deliver S3, S4, S5, S6 for the selected sector.

**Exit:** one project can run from operational event through cost/revenue, close, approved allocation/distribution where applicable, statement, and correction in staging.

### Phase 4 — Controlled paid pilot

- import verified opening data;
- parallel run with customer spreadsheet/accounting process;
- daily exception triage, weekly reconciliation, and signed UAT;
- no native cash execution; payments are recorded after existing banking process;
- production backup/restore rehearsal and incident/support readiness.

**Exit:** four consecutive weekly reconciliations, one period close, accurate required statements, zero unresolved critical security/data issues, and buyer acceptance.

### Phase 5 — General availability

- hardened onboarding/import;
- support/admin console and service-level policy;
- billing/plan limits;
- external accounting export adapter;
- second design partner before declaring a second sector commercially validated; technical sector construction may precede that evidence under P-007.

## 6. Backlog priority

Use this order:

1. legal/financial correctness and tenant isolation;
2. workflows required by the paid pilot;
3. reduction of manual reconciliation/report preparation;
4. usability/field capture that improves data completeness;
5. repeatable onboarding and support cost;
6. sector breadth;
7. analytics/automation/AI.

No feature outranks a broken financial invariant, cross-tenant risk, inability to close/reconcile, or an unresolved business rule that the feature depends on.

## 7. Definition of done

A feature is done only when:

- behavior and states match an approved journey and do not depend on an OPEN business decision;
- authorization and tenant isolation are enforced/tested;
- material commands are atomic/idempotent and auditable;
- reversal/correction and closed-period behavior exist where relevant;
- Arabic/RTL and mobile states are verified;
- loading/error/empty states are honest; offline/conflict states are required only after offline behavior exists;
- accessibility checks pass for the workflow;
- telemetry/runbook/support notes exist;
- no seeded/fake production data masks missing behavior;
- the claimed level of acceptance is truthful: technical evidence is not mislabeled as customer UAT/commercial validation.

## 8. Release gates

### Engineering

- typecheck, lint, unit/integration/contract/E2E gates green for changed runtime scope;
- migration replay from empty and upgrade from previous release when schema changes;
- RLS tests with at least two organizations and relevant self-scope;
- concurrency/idempotency/reversal/period-lock tests for affected material commands;
- dependency/secret/static security scans;
- preview and production smoke tests when deployment is in scope.

### Finance/data

- opening balance control total signed off;
- bank/book/project/partner rollforwards reconcile for the enabled model;
- sample allocations independently recalculated when allocation is in scope;
- statement totals trace to posted lines;
- import rejects are zero or explicitly accepted;
- statutory export mapping reviewed by qualified accountant before production use.

### Operations

- backup restore demonstrated;
- owner/admin recovery and membership revocation tested;
- incident, incorrect posting, failed import/integration, and rollback runbooks;
- monitoring and support ownership defined;
- customer data processing/retention terms approved.

## 9. Pilot success metrics

| Metric | Target |
|---|---|
| Time to first configured real project | ≤ 2 business days after clean source data |
| Material events linked to project and evidence/status | ≥ 95% |
| Unreconciled cash older than 7 days | 0 at close |
| Required statement production time | < 10 minutes after close approval |
| Statement variance vs independently approved calculation | 0 |
| Cross-tenant/security critical issues | 0 |
| Posted events changed destructively | 0 |
| Weekly active users in pilot roles | ≥ 80% of invited operating users |
| Critical workflow completed without developer intervention | 100% |

## 10. Commercial learning plan

Validate in order:

1. buyer gives access to real operational/financial artifacts;
2. buyer accepts the product boundary and first sector;
3. buyer pays setup/pilot fee;
4. users capture data without the founder operating the system for them;
5. management uses a Terranex statement/exception to make a real decision;
6. monthly subscription is renewed;
7. onboarding can be repeated for a second company without custom code.

If onboarding requires code for every customer, pause sector expansion and productize configuration/import first.

## 11. Risk register

| Risk | Early signal | Response |
|---|---|---|
| Three sectors create scope explosion | shared core changes for every sector edge case | ship one sector at a time; protect bounded contexts |
| Investor/company economics are guessed | portfolio/funding UI starts implying ownership or entitlement | hard-stop dependent scope; resolve `OPEN_BUSINESS_DECISIONS` first |
| Agreement rules are more complex than v1 | preferred returns/carry/custom loss clauses appear | choose simpler pilot or scope a dedicated rules phase |
| Customer source data is unreliable | balances/documents do not reconcile | paid data-cleaning gate and signed opening controls |
| Product drifts into regulated offering | public discovery/subscription/custody requested | stop; legal review and separate product decision |
| External accountant rejects exports | chart/policy mapping discovered late | involve accountant before production export/close rehearsal |
| Field users do not capture events | late WhatsApp/paper remains source | reduce fields, mobile/offline drafts, accountable work queue |
| Investor portal leaks data | role/project/participant model unclear | deny by default; dedicated self-scope tests and views |
| Financial engine gains false complexity | generic formulas/config everywhere | versioned named policies; defer uncommon waterfalls |

## 12. Build-start checklist

Coding is authorized only for the active approved implementation slice. Resolve only the decisions required by that slice. Do not create a complete ADR catalogue, universal domain framework, all-sector schema, offline engine, integration infrastructure, or generic investor rules in advance.

## 13. Technical baseline at R0

At the R0 base on 2026-08-15:

- Real Estate S0–S7/GF-010/GF-011 is technically implemented for its authorized scope;
- Agriculture GF-013 through GF-019 is technically implemented for its authorized scope;
- Livestock GF-020 through GF-024 is merged/technically implemented for its authorized scope, including GF-023 Operations Completion and GF-024 Commercial, Profitability & Closeout;
- those facts are implementation evidence, not customer validation or authority to generalize investor/company economics;
- the existing project-centric runtime remains untouched by R0 unless a later bounded implementation slice explicitly migrates it.

### Historical Agriculture construction record

Before the Portfolio realignment, Agriculture was deliberately completed through **three independently reviewed major phases** after the earlier foundations. This is a historical construction record, not the active roadmap:

1. **GF-017 — Agricultural Land Asset, Acquisition & Control (merged)** — established the land investment/control object and preserved separation between acquisition/control and seasonal operations.
2. **GF-018 — Agriculture Sale, Dispatch & Revenue (merged)** — added sale, dispatch/control transfer, shared-core revenue/receivable, and collection without guessing inventory value or COGS.
3. **GF-019 — Agriculture Profitability, Cycle Closeout & Technical Gate** — completed authoritative cost attribution, cycle result/closeout, and the Agriculture technical gate.

GF-013 through GF-019 are technically implemented. These statements preserve the completed sector history and do not reopen Agriculture, count as customer validation, or authorize new investor/company economics.

## 14. R0 — Canonical Portfolio Realignment & Anti-Hallucination Governance

**Scope: documentation/governance only.** R0 establishes:

- Organization → Investment Portfolio → Investment Project as the management hierarchy;
- Portfolio as management/reporting parent, not automatic fund/legal entity/SPV/investor pool;
- Project as the independent operational, budget, financial-attribution, execution, and close boundary;
- explicit separation of portfolio capital deployment from investor contribution/ownership/allocation/distribution/payment;
- basic Real Estate rental-income boundary without full property management;
- Portfolio → Project → source UX/traceability rules;
- `docs/OPEN_BUSINESS_DECISIONS.md` and anti-hallucination governance.

**R0 does not authorize** schema, migrations, routes, services, runtime behavior, UI components, or placeholders.

## 15. R1–R13 independent build, R13 hard stop, R14–R17 policy pack

The canonical roadmap is the **R0–R17 sequence** in `docs/ROADMAP_R0_R17.md`. The controlling strategy is **Build Everything Independent First**: complete every feature whose correctness does not depend on unresolved legal/economic policy; defer only the smallest rule-dependent portion. The hard stop is moved from R5 to R13 so the company owner is asked only after the product is already ~85–95% complete. Each gate is a separate bounded branch from current `main` with the full changed-layer verification. Slice-label note: the merged "R1 — Portfolio Foundation" slice (PR #139, ADR 0025) delivers the Portfolio-identity portion of phase R2 below; the R-numbers below are roadmap phases, the slice names are the delivered increments (mapping in `docs/ROADMAP_R0_R17.md`).

### R1 — Production Foundation
Organization, users/memberships, party registry, roles/capabilities, RLS, audit trail, maker/checker, documents/evidence, idempotency, exact money, period model, notifications foundation, Arabic/RTL foundation. (Largely present in S0–S2/S6/S7.)

### R2 — Portfolio + Project + Asset Core
Portfolio → Projects → Assets → Documents → Decisions → Risks → Budgets → Operational/financial position; many independent Projects inside one Portfolio. Portfolio remains a management/reporting parent over project-authoritative truth — not a fund, legal entity, SPV, pooled vehicle, or second ledger. **Delivered so far:** the merged R1 — Portfolio Foundation slice (PR #139, ADR 0025) implements Portfolio identity, the narrow `DRAFT | ACTIVE | ARCHIVED` lifecycle, one current parent Portfolio per Project, append-only membership history, and the Arabic/RTL Portfolio workspace. Remaining: Asset/Document/Decision/Risk/Budget modeling and Portfolio roll-up read-models.

### R3 — Complete Financial Control
Budget, forecast, commitment, obligation, accrual, expense/actual, revenue, receivable, payable, payment, receipt, cash, bank accounts, bank reconciliation, project subledger, reversal/repost, period close, portfolio roll-up. (Shared Finance Core S2–S6 already implements the authoritative engine.) The only deferred part is **who among investors is entitled to how much of the result** — not the accounts themselves.

### R4 — Procurement & Shared Operations
Suppliers, purchase requests, purchase orders, receiving, invoices, payments, contracts, attachments, approvals, shared inventory concepts where needed, counterparties — so Agriculture/Livestock do not reinvent procurement and suppliers. This slice is deferred farm-ERP scope in GF-019 and is the first genuinely missing independent gate. **Delivered so far:** the shared quantity-only Procurement operational foundation + receiving (GF-025: organization-scoped suppliers, project-scoped purchase requests/orders; GF-026: receiving against APPROVED purchase orders with over-receipt protection), preserved on the post-R1 canonical lineage with ADRs 0027/0028. Pricing/commitment, supplier invoicing/payment (Finance Core linkage), contracts/attachments, and shared inventory-value concepts remain the next bounded steps.

### R5 — Real Estate (complete)
Opportunity/due diligence, acquisition, asset registration, purchase costs, holding, basic rental income, holding expenses, valuation history, development/improvement projects, disposal, realized result, asset profitability, project profitability — without turning into a large property-management SaaS. (Technically implemented S0–S7/GF-010/GF-011.)

### R6 — Livestock (complete)
Site, herd, cohort/batch, animal categories, purchase/birth, placement/movement, feed, veterinary/health, vaccination, weight, mortality, production, sale, inventory consumption, direct/allocated operating costs, cycle economics, herd/project profitability — bound to the Finance Core, not a parallel ledger. (Technically implemented GF-020–GF-024.)

### R7 — Agriculture (complete)
Farm, field, crop, crop cycle/season, planting, inputs, irrigation activity, fertilizer/pesticide usage, labor/activity costs, harvest, yield, produce inventory, waste/loss, sale, cycle profitability, field profitability — the operating cycle is real. (Technically implemented GF-013–GF-019.)

### R8 — Cross-Sector Asset & Performance Layer
Unify what can be unified without distorting each sector: asset register, acquisition cost, current approved valuation, operating income/cost, maintenance/improvement, disposal, realized vs unrealized result, project/portfolio/sector performance — so the owner sees how much Real Estate, Livestock, and Agriculture each made, where capital is, where cash is, and which projects are losing.

### R9 — Management UX (complete)
Home/executive dashboard, Portfolios, Projects, Assets, Real Estate, Agriculture, Livestock, Money, Procurement, Documents, Approvals, Reports, Settings; mobile/tablet/desktop + Arabic/RTL.

### R10 — Investor Transparency (read-models only, no invented rights)
Investor/party identity, secure login, documents available to that party, project updates, photos/evidence, portfolio/project activity, published reports, notices, statements framework, as-of date, valuation basis, data freshness. **Do not display** a computed investor profit/entitlement number until the real contract and accrual basis are fixed. Build the UI and read-model architecture now; keep the entitlement-dependent field inert until R15.

### R11 — Reporting & Control
Portfolio position, project P&L/economic result, cash position, budget vs actual, commitments, receivables, payables, asset register, valuation movement, procurement, livestock performance, agriculture yield/economics, real-estate returns, audit/approval reports, exceptions. Investor-specific financial statements wait only for their policy.

### R12 — Production Hardening
Backups/restore proof, migration replay, RLS/security tests, concurrency tests, idempotency tests, financial invariant tests, audit tests, performance indexes, error handling, observability, data export, opening-data import, document storage, production configuration, seed/demo templates, disaster-recovery procedure.

### R13 — Full Company Simulation
A large synthetic scenario: a Real Estate portfolio with ≥3 projects, a Livestock portfolio with several herd/cohort operations, an Agriculture portfolio with farm + fields + multiple crop cycles; pass purchases, expenses, revenue, cash, assets, valuations, sales, receivables, payables, losses, project close, and portfolio reporting; prove every pound is traceable. Use company/internal capital or neutral funding facts — never invented investor entitlements.

## 16. Hard stop after R13 — owner decision required (the policy pack)

**R13 is the hard stop.** After R13, stop before implementing any feature whose correctness depends on unresolved portfolio/investor legal or economic rules. Do not implement or extend:

- portfolio-level investors or pooled capital;
- portfolio/project ownership semantics;
- contribution-to-ownership inference;
- new profit/loss allocation or distribution formulas;
- cross-project netting, recycling, cash/capital transfers, or shared reserves;
- management/operator economics, tax/withholding automation, or investor lifecycle behavior not already governed.

At R13 the target company owner is asked only the **small R14 policy pack** — the 13 questions only they/their contracts can answer (investor inside Portfolio or Project; exact legal right; whether management moves capital between projects; whether the company co-invests; whether one Project's loss offsets another's profit; how loss is distributed; how/when the company takes its share; the definition of distributable profit; whether a reserve exists; whether profits are reinvested; exit/transfer terms; legal owner of assets; the actual contract used). Some answers require reading the real contract and legal/accounting documents, not just oral replies.

The company owner must resolve the relevant IDs in `docs/OPEN_BUSINESS_DECISIONS.md`. Accounting/legal review is additionally required where the chosen business rule has accounting, tax, regulatory, or legal consequences. Only then may the R15–R17 work proceed.

## 17. R15–R17 after the policy pack is fixed

### R15 — Investor Economics
Capital commitments, contributions, economic participation, profit/loss allocation, operator economics, reserves, reinvestment — reflecting the real agreement, never invented defaults.

### R16 — Distribution & Investor Statements
Distribution payable, approval, payment, investor ledger, statements.

### R17 — Final Company UAT
Enter real data and reconcile it against the company's own accounts.

This hard stop does not block independent sector work, security/data-integrity fixes, or other product work that does not depend on those open decisions.
