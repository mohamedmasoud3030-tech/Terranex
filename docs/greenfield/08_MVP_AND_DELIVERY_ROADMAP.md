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

## 15. R1–R5 execution gates after R0

These are bounded future implementation gates. Each requires a fresh branch from current `main`, its own review, and the full changed-layer verification. Do not combine them into R0.

### R1 — Portfolio Foundation

Implement only the minimum organization-scoped Portfolio identity and Project parent/association required by the canonical hierarchy. Preserve every existing Project ID, sector object, journal source, agreement, and historical financial fact. Migration/backfill must be deterministic, auditable, and economically neutral.

**Not in R1:** investor pooling, portfolio ownership, new capital rules, cross-project transfers, duplicate finance core.

### R2 — Portfolio Workspace & Project Drill-Down

Add Arabic/RTL Portfolio list/detail and derived project roll-ups for lifecycle, sector, cash, realized result, committed cost, valuation, close state, and actionable exceptions. Every total must drill to Project composition and then to source truth. Handle multi-currency honestly; do not silently sum unlike currencies.

**Not in R2:** writable portfolio balances or investor economics.

### R3 — Portfolio Capital Deployment Planning

Add an approved **management deployment fact** that records intended/approved capital availability by Project, purpose, currency, date, evidence, and approval. It remains non-posting until a separately approved funding/accounting mechanism exists. Show planned/approved/deployed/used semantics only when their source facts exist.

**Not in R3:** treating deployment as investor contribution, ownership, distribution, loan, inter-project receivable/payable, or cash transfer by implication.

### R4 — Basic Real Estate Rental Income

For held Real Estate assets, reuse the shared Finance Core to support the narrow investment-revenue path: rental evidence/period → revenue/receivable recognition under approved policy → partial/multiple collection → project reporting/reconciliation/correction. Maintain property/asset traceability.

**Not in R4:** tenant CRM, lease administration suite, renewals, service charges, facilities operations, maintenance/work orders, or a second receivable/payment engine.

### R5 — Portfolio Reporting, Controls & Hardening

Complete owner-facing Portfolio reporting and operational hardening: project-level composition, as-of/currency/completeness semantics, permissions/RLS, audit, migration/recovery proof, reconciliation paths, performance, Arabic/RTL/mobile/accessibility, and regression protection across the existing sectors. Portfolio remains a projection/management layer over project-authoritative truth.

**R5 exit:** Portfolio can organize and review Projects, approve/observe non-posting management deployment planning, drill into project truth, and include narrow Real Estate rental income without introducing unapproved investor/legal/economic behavior.

## 16. Hard stop after R5 — owner decision required

After R5, **stop before implementing any feature whose correctness depends on unresolved portfolio/investor legal or economic rules**. Do not implement or extend:

- portfolio-level investors or pooled capital;
- portfolio/project ownership semantics;
- contribution-to-ownership inference;
- new profit/loss allocation or distribution formulas;
- cross-project netting, recycling, cash/capital transfers, or shared reserves;
- management/operator economics, tax/withholding automation, or investor lifecycle behavior not already governed.

The company owner must resolve the relevant IDs in `docs/OPEN_BUSINESS_DECISIONS.md`. Accounting/legal review is additionally required where the chosen business rule has accounting, tax, regulatory, or legal consequences. Only then may the next bounded roadmap be designed.

This hard stop does not block independent sector work, security/data-integrity fixes, or other product work that does not depend on those open decisions.
