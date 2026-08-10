# Terranex Greenfield — 08 MVP & Delivery Roadmap

**Status:** Execution baseline v1  
**Goal:** Reach a paid design partner quickly without compromising money, ownership, security, or audit integrity.

## 1. MVP decision

Do not build equal depth for all three sectors before revenue. Build:

1. the shared investment/finance/control core;
2. one production-ready sector pack selected by the first paying design partner;
3. thin schema/workflow spikes for the other sectors only to prove the core boundary.

Recommended commercial default: start with **real-estate acquisition/development/disposal** because investment agreements, partner capital, property costs, approvals, and distributions expose the core product value with less daily biological/offline complexity. If the first committed buyer is agricultural or livestock, switch the sector pack without changing the core.

## 2. MVP promise

> “For every project, Terranex shows the signed terms, what happened operationally, every pound in and out, what is due, the realized result, and each partner’s position—with approvals and evidence.”

If a feature does not help deliver or prove that promise for a contracted design partner, it does not enter MVP.

## 3. MVP scope

### Platform core — must ship

- organization, membership, role and project-scoped permission;
- parties and project participants;
- investment project setup and lifecycle;
- immutable agreement versions with commitments/ownership/simple allocation rules;
- private versioned documents and typed links;
- capital calls, contributions, investor capital rollforward;
- obligations, receipts, payments, basic sales/collections;
- project cash accounts and CSV bank-statement reconciliation;
- balanced project subledger, posting rules, periods, close, reversal;
- simple result allocation and distribution approval/payment;
- approvals, tasks, exceptions, audit trail;
- project dashboard, capital statement, project performance pack;
- Arabic/RTL, responsive web/PWA, offline sector-event drafts;
- CSV import/export with controlled opening-balance workflow.

### First sector pack — real-estate default

- asset/parcel and acquisition record;
- title/due-diligence checklist and documents;
- development phase/milestones and budget vs actual/committed cost;
- valuation record with method/source/approval;
- disposition, cost/proceeds, collection, and realized closeout.

### Not MVP

- public investor onboarding or marketplace;
- native money movement/bank connections;
- advanced waterfall/carry/preferred return;
- general ledger, tax returns, consolidation, payroll;
- AI advice/forecasting or automated valuation;
- IoT/satellite/RFID integration;
- leasing/property management;
- full agronomy/dairy/processing;
- custom report builder and public API marketplace.

## 4. Thin vertical slices

Build working slices, not disconnected layers:

| Slice | User-visible outcome | Proof |
|---|---|---|
| S0 Foundation | Secure organization and project shell | Two-tenant isolation, roles, audit |
| S1 Terms & funding | Activate agreement, call and receive capital | Capital rollforward and immutable version |
| S2 Cost & cash | Record obligation, approve/pay, reconcile bank | Balanced posting and evidence trail |
| S3 Sector operation | Capture one complete sector lifecycle path | Quantity/state rollforward + cost drilldown |
| S4 Revenue & result | Recognize sale/collection and project result | Carrying-cost/revenue postings and report |
| S5 Allocation & distribution | Allocate closed result, approve/pay distribution | Investor statement and concurrency protection |
| S6 Close & correction | Close period, reverse/repost, regenerate reports | Locked period and complete audit chain |
| S7 Pilot hardening | Import customer project and operate one cycle | UAT, restore, security, support runbook |

Each slice includes schema, domain, application, UI, permissions, tests, telemetry, and documentation before starting the next material slice.

## 5. Delivery phases

### Phase 0 — Evidence and commercial validation (1–2 weeks)

Outputs:

- three qualified customer interviews and one committed design partner;
- sanitized real spreadsheets, agreement, bank statement, invoices/receipts, and monthly partner report;
- selected first sector and exact pilot project;
- validated terminology and workflow map;
- paid/purchase-intent pilot terms and success criteria;
- legal boundary confirmation: private operational system, no public solicitation/custody.

**Exit:** one buyer provides data, weekly access to users, and commercial commitment. No code beyond prototypes/setup if this is absent.

### Phase 1 — Architecture runway and UX prototype (1–2 weeks)

Outputs:

- repository/CI, environments, migrations, tenant/auth/RLS baseline;
- accounting policy/semantic accounts and posting-rule ADR;
- domain command/API contracts;
- clickable Arabic prototype for the eight critical tasks;
- import mapping and data migration rehearsal plan;
- threat model and authorization matrix.

**Exit:** finance, operator, manager, and investor can complete prototype tasks; technical spikes prove transaction/RLS/offline assumptions.

### Phase 2 — Core vertical slices (4–6 weeks)

Deliver S0–S2, then S4 financial foundation:

- project/party/agreement;
- capital call/contribution;
- obligation/payment/reconciliation;
- documents/approval/audit;
- balanced subledger and basic project/capital statements.

**Exit:** a real opening project can be imported and every financial balance reproduced.

### Phase 3 — First sector and result lifecycle (3–5 weeks)

Deliver S3, S4, S5, S6 for the selected sector.

**Exit:** one real project runs from operational event through cost/revenue, close, allocation, distribution, statement, and correction in staging.

### Phase 4 — Controlled paid pilot (4 weeks)

- import verified opening data;
- parallel run with customer spreadsheet/accounting process;
- daily exception triage, weekly reconciliation, and signed UAT;
- no native cash execution; payments are recorded after existing banking process;
- production backup/restore rehearsal and incident/support readiness.

**Exit:** four consecutive weekly reconciliations, one period close, accurate investor statement, zero unresolved critical security/data issues, and buyer acceptance.

### Phase 5 — General availability

- hardened onboarding/import;
- support/admin console and service-level policy;
- billing/plan limits;
- external accounting export adapter;
- second design partner and only then second sector pack.

## 6. Backlog priority

Use this order:

1. legal/financial correctness and tenant isolation;
2. workflows required by the paid pilot;
3. reduction of manual reconciliation/report preparation;
4. usability/field capture that improves data completeness;
5. repeatable onboarding and support cost;
6. sector breadth;
7. analytics/automation/AI.

No feature outranks a broken financial invariant, cross-tenant risk, or inability to close/reconcile.

## 7. Definition of done

A feature is done only when:

- behavior and states match an approved journey;
- authorization and tenant isolation are enforced/tested;
- material commands are atomic/idempotent and auditable;
- reversal/correction and closed-period behavior exist where relevant;
- Arabic/RTL and mobile states are verified;
- loading/error/empty/offline/conflict states are honest;
- accessibility checks pass for the workflow;
- telemetry/runbook/support notes exist;
- no seeded/fake production data masks missing behavior;
- acceptance is demonstrated on realistic customer data.

## 8. Release gates

### Engineering

- typecheck, lint, unit/integration/contract/E2E gates green;
- migration replay from empty and upgrade from previous release;
- RLS tests with at least two organizations and investor self-scope;
- concurrency/idempotency/reversal/period-lock tests;
- dependency/secret/static security scans;
- preview and production smoke tests.

### Finance/data

- opening balance control total signed off;
- bank/book/project/partner rollforwards reconcile;
- sample allocations independently recalculated;
- statement totals trace to posted lines;
- import rejects are zero or explicitly accepted;
- statutory export mapping reviewed by qualified accountant.

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
| Partner statement production time | < 10 minutes after close approval |
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
| Three sectors create scope explosion | shared core changes for every sector edge case | ship one sector; protect bounded contexts |
| Agreement rules are more complex than v1 | preferred returns/carry/custom loss clauses appear | choose simpler pilot or scope a dedicated rules phase |
| Customer source data is unreliable | balances/documents do not reconcile | paid data-cleaning gate and signed opening controls |
| Product drifts into regulated offering | public discovery/subscription/custody requested | stop; legal review and separate product decision |
| External accountant rejects exports | chart/policy mapping discovered late | involve accountant in Phase 0/1 and close rehearsal |
| Field users do not capture events | late WhatsApp/paper remains source | reduce fields, mobile/offline drafts, accountable work queue |
| Investor portal leaks data | role/project/participant model unclear | deny by default; dedicated self-scope tests and views |
| Financial engine gains false complexity | generic formulas/config everywhere | versioned named policies; defer uncommon waterfalls |

## 12. Build-start checklist

Coding may start only after these eight greenfield documents are approved as the working baseline and Phase 0 identifies the first design partner/sector. Before the first production schema:

- convert open discovery items into recorded decisions;
- write ADRs for tenant model, accounting boundary, money representation, agreement versioning, posting/reversal, and offline scope;
- produce the command/state/authorization matrix;
- validate the first customer’s agreement and expected partner statement with an accountant/legal reviewer;
- archive legacy Terranex product documents and freeze legacy code as non-authoritative reference.

## 13. Immediate next execution batch

1. Recruit/interview three target companies using the ICP and jobs in Document 01.
2. Secure one paid design partner and artifacts listed in Phase 0.
3. Choose the first sector based on contracted demand, defaulting to real estate only if evidence is tied.
4. Produce clickable Arabic prototype for J1–J8 and test it with the four roles.
5. Finalize ADRs and physical schema from real artifacts.
6. Build S0 → S7 without parallel feature branches that create competing domain/design systems.

This is the boundary between **product design** and **software construction**. The legacy codebase is not refactored into this model; reusable technical pieces may be evaluated later against these contracts.

