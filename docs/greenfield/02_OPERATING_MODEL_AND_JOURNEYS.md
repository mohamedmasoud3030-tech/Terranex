# Terranex Greenfield — 02 Operating Model & Journeys

**Status:** Foundational baseline v1  
**Depends on:** `01_PRODUCT_CHARTER_AND_MARKET.md`

## 1. Operating model

Terranex manages an **Investment Portfolio** that groups independent Investment Projects for owner-level planning, capital-deployment visibility, and consolidated management reporting. A Portfolio is an operating and reporting container inside one Organization; it is **not automatically a fund, legal entity, SPV, pooled vehicle, or shared investor pool**.

Each Investment Project remains the operational, budget, financial-attribution, execution, and close boundary for one deal/venture with exactly one primary sector. Sector assets and operating cycles remain independent and project-bounded unless a later approved business rule explicitly introduces a different legal/economic relationship.

```mermaid
flowchart TD
  O["Organization"] --> PF["Investment portfolio"]
  PF --> P["Investment project"]
  P --> A["Agreement & participants"]
  P --> S["Sector operations"]
  P --> M["Money & obligations"]
  A --> R["Allocation & reporting"]
  S --> R
  M --> R
```

## 2. Roles and segregation of duties

| Role | Can prepare | Can approve | Cannot do alone |
|---|---|---|---|
| Organization owner | Configuration, invitations | Role grants, periods, material actions | Override immutable history |
| Investment manager | Project, budget, agreement draft, valuation, distribution proposal | Normal project changes within mandate | Approve own distribution/payment |
| Finance officer | Contributions, receipts, payments, obligations, reconciliation, journal draft | Low-risk entries if policy permits | Approve own high-value payment or reopen period |
| Sector manager | Plans, work events, quantities, evidence, completion | Operational event confirmation | Post bank movement or distribution |
| Reviewer/approver | Review queues and exceptions | Agreement, payment, valuation, distribution, close | Change prepared calculation silently |
| Investor | Profile and requested documents | Acknowledge notices when enabled | See other investors or operational private data |
| Auditor/read-only | Reports, evidence, audit trail | None | Modify any record |

Rules are organization-configurable only within safe templates. Default: maker and approver must be different users for bank payments, agreement activation, allocation, distribution, period close/reopen, and opening-balance import.

## 3. Investment portfolio operating layer

The Portfolio answers management questions across projects without erasing project independence. At minimum it can identify which projects belong to the management portfolio and support roll-up of project status, deployed capital, cash, realized result, valuation, risks, and exceptions from project-authoritative sources.

Rules:

- portfolio membership does not transfer ownership, cash, liabilities, profit, or loss between projects;
- a project keeps its own lifecycle, sector root, budget, financial attribution, agreements, close, and evidence;
- “portfolio capital deployment” means an owner/management decision to make capital available to or invest into a project. It is **not** the same fact as an investor contribution, ownership interest, result allocation, distribution, or payment;
- cross-project netting, recycling, transfers, pooled investor economics, and portfolio-level entitlement are **unresolved business decisions**, not defaults;
- consolidated portfolio views are projections over project truth, never a second mutable ledger.

## 4. Project lifecycle

| State | Entry condition | Allowed work | Exit gate |
|---|---|---|---|
| DRAFT | Project shell created | Configure sector, parties, agreement, budget, asset | Required setup complete |
| DUE_DILIGENCE | Opportunity accepted for review | Documents, checks, assumptions, valuation, decision memo | Approved investment decision |
| FUNDING | Active agreement and commitment plan | Capital calls, contribution receipts, acquisition obligations | Minimum funding/acquisition condition met |
| ACTIVE | Project controls active | Full sector operations and finance | Approved exit/closure plan |
| EXITING | Disposal/harvest liquidation/closure started | Settlement, receivable collection, asset disposition | No unresolved material obligations |
| CLOSED | Periods closed and final statement approved | Read/report, permitted late adjustment by reopen workflow | Reopen approval only |
| CANCELLED | Pre-activation cancellation | Read-only plus documented reason | No transition back; clone if needed |

Lifecycle state does not replace asset or sector state. A project may be ACTIVE while one crop cycle is closed and another is planned.

## 5. Canonical end-to-end journeys

### J0 — Create and maintain an investment portfolio

1. Organization owner or investment manager creates the management portfolio and records name, purpose, reporting context, and responsible manager.
2. Existing or new Investment Projects are associated without changing their project identity, sector, agreements, ledgers, or lifecycle.
3. Portfolio views roll up project-authoritative status and financial/operational measures with explicit “as of”, currency, valuation, and completeness semantics.
4. Removing a project from a management portfolio does not delete or rewrite the project or its history.

**Invariant:** portfolio membership alone creates no investor entitlement, legal ownership, inter-project receivable/payable, or cash movement.

### J1 — Create and activate an investment project

1. Create project inside the selected Investment Portfolio and choose exactly one primary sector.
2. Define legal/operating entity, location, reporting currency, dates, manager, and materiality policy.
3. Attach due-diligence checklist and evidence.
4. Define only the agreement/participant terms that are actually approved for this project. Do not infer portfolio-level ownership, investor pooling, contribution basis, allocation, fee, or distribution rules from portfolio membership.
5. Configure project accounts and opening budget.
6. Add sector baseline: real-estate asset, farm/fields, or herd/cohorts.
7. System validates totals, dates, required evidence, role conflicts, and accounting setup.
8. Reviewer approves; activation creates an immutable agreement snapshot and audit event.

**Invariant:** operations that affect entitlement cannot predate the effective agreement unless entered through an approved opening/import workflow.

### J2 — Deploy capital to a project

1. Management records an approved portfolio-to-project capital-deployment decision with project, purpose, approved amount/currency, date, source/evidence, and approval.
2. The system treats deployment as a management/funding fact and keeps it distinct from investor capital activity.
3. Any actual bank movement, inter-project balance, loan, equity contribution, or other accounting treatment is created only through the specific approved financial mechanism that applies.
4. Portfolio reporting can compare approved/deployed/used amounts by project without creating partner entitlement.

**Hard boundary:** this journey does not decide who economically owns the portfolio, who funds it, whether project funding is debt/equity/current-account movement, or how profits return to investors. Those rules remain open until the owner answers `docs/OPEN_BUSINESS_DECISIONS.md`.

### J3 — Call and receive investor capital

1. Manager prepares a capital call with purpose, due date, amount, currency, and allocation basis.
2. System calculates each participant share from the effective agreement and shows rounding residual handling.
3. Reviewer approves; notices become immutable versions.
4. Finance records bank receipt against a participant and call line.
5. Receipt posts cash and capital contribution/receivable effects atomically.
6. Exceptions remain visible: short payment, overpayment, unidentified receipt, FX difference, or late receipt.
7. Investor capital statement updates only from posted events.

### J4 — Procure, incur, approve, and pay a cost

1. Sector/finance user records commitment or supplier obligation with project, work/cost category, expected date, tax fields, and evidence.
2. Receipt of goods/service records quantity and links to the sector object.
3. Invoice/claim is matched to obligation and receipt when applicable.
4. Approval policy routes by amount/category/project.
5. Payment proposal validates available cash, bank account, duplicate risk, and period.
6. Approval then posting updates obligation, cash, project cost, inventory/asset/WIP as defined by posting rule.
7. Bank reconciliation later confirms settlement without recreating the payment.

### J5 — Capture a sector event

1. Operator chooses project then sector object: parcel/phase, field/cycle, herd/cohort/animal.
2. Select event template; enter time, quantity, unit, responsible person, location, notes, and evidence.
3. Offline-capable draft may be saved with device time; server receipt time is retained separately.
4. Validation checks impossible dates, negative quantities, identity/state conflicts, and required inputs.
5. Confirmed event updates operational projections and may create inventory consumption, production, or a financial draft.
6. A material or exceptional event enters review; routine events post under policy.

### J6 — Record revenue and collection

1. Create sale/contract from sector output or asset disposition.
2. Capture customer, quantity/asset, price, tax, performance/delivery date, payment terms, and evidence.
3. Approval posts receivable/revenue and removes inventory or asset cost according to policy.
4. Collection is matched to the receivable; partial, withheld, disputed, and FX amounts stay explicit.
5. Cash receipt and revenue recognition remain separate events when their dates differ.

### J7 — Close a period and report performance

1. Resolve or explain unreconciled cash, unmatched documents, negative inventory, missing rates, and overdue approvals.
2. Record accruals, allocations, inventory counts, production, impairment/valuation proposals, and reversals.
3. Run subledger controls: balanced batches, project dimensions, partner capital rollforward, asset/inventory rollforward.
4. Reviewer approves close; system stores control results and locks the period.
5. Generate project pack: cash, P&L bridge, commitments, operational KPIs, valuation status, investor capital rollforward, and exceptions.

### J8 — Allocate result and distribute cash

1. Finance selects a closed reporting period and effective agreement version.
2. System calculates allocable realized result and each participant allocation; management valuation is excluded unless policy explicitly permits and is legally reviewed.
3. Manager proposes distributable cash after reserves, obligations, and minimum cash policy.
4. Reviewer approves the calculation snapshot and distribution notice.
5. Finance prepares payment; another approver authorizes posting.
6. Paid/rejected/returned states are recorded; capital accounts and payables update from postings.
7. Investor receives a statement linking opening capital, contributions, allocated result, distributions, and closing balance.

### J9 — Correct an error

1. User opens the posted event and chooses “Correct”.
2. System creates a reversal draft linked to the original, with mandatory reason and period treatment.
3. If original period is closed, correction uses an approved late-posting/reopen policy.
4. After approval, reversal posts; replacement event is prepared separately.
5. Original, reversal, replacement, actor, approvals, and documents remain connected.

### J10 — Review portfolio performance and trace to project truth

1. Owner opens the Portfolio and sees project-by-project status, capital deployment, cash, realized result, valuation, risks, and exceptions with explicit basis and “as of” dates.
2. Every portfolio amount drills to its project composition and then to the project ledger/operational evidence.
3. Portfolio reporting never combines realized and unrealized measures without labeling them.
4. No portfolio total is writable and no roll-up creates a cross-project posting.

## 6. Exception queues

Home and project workspaces prioritize actionable exceptions, not passive charts:

- approvals waiting on me;
- unidentified/unreconciled cash;
- overdue capital calls and obligations;
- missing evidence or broken matches;
- negative/implausible stock or animal state;
- planned work overdue;
- budget/quantity/price variance over threshold;
- expired document or permit;
- period-close blockers;
- failed integration/outbox items.

Each exception has owner, severity, due date, source, and resolution outcome. Dismissing without reason is not allowed.

## 7. State-machine rules

- Draft records may be edited and deleted if they created no posted effects.
- Submitted records are versioned; edits create a new draft version.
- Approved is not posted: posting is an atomic domain action with accounting/audit effects.
- Posted records cannot be edited or deleted.
- Voided/cancelled/reversed are distinct states with different financial effects.
- A status transition requires permission, current-version check, and idempotency key.
- State history records actor, time, previous/new state, reason, and approval reference.

## 8. Notification policy

Notifications are consequences of durable events, never the source of truth. In-app is mandatory; email/WhatsApp are optional delivery channels. Every notice has a stable ID, version, recipient scope, delivery status, and link to the canonical record. Sensitive financial values are not placed in push notification bodies by default.

## 9. Operational reports

| Cadence | Report | Core audience |
|---|---|---|
| Daily | Cash/approval/exception digest | Owner, finance |
| Weekly | Project operations vs plan and budget | Manager, sector lead |
| Monthly | Project performance and capital rollforward | Owner, finance, investors |
| Cycle/exit | Crop, herd cohort, or real-estate deal closeout | Management, investor |
| Ad hoc | Audit trail and evidence package | Auditor, dispute review |

## 10. Acceptance criteria for the operating model

- portfolio roll-ups are traceable to independent project truth and never create shared economics by implication;
- portfolio capital deployment is distinguishable from investor contribution, ownership, allocation, distribution, and payment;
- Every material workflow identifies maker, approver, posting event, evidence, exception path, and reversal path.
- A user can never infer that payment equals expense, receipt equals revenue, valuation equals realized profit, or allocation equals distribution.
- Partner statements can be regenerated from posted events and effective agreement versions.
- Sector events can exist without money; financial events can reference sector objects without embedding sector business logic in the finance core.
