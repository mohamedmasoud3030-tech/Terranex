# Terranex Greenfield — 07 UX & Information Architecture

**Status:** Product UX baseline v1  
**Design objective:** Make the next correct action obvious while preserving financial and audit depth.

## 1. Experience thesis

Terranex is not a dashboard collection. It is a set of controlled workspaces around an investment project. Users should enter through work requiring attention, act in context, and drill from every number to its composition and source evidence.

The product is Arabic/RTL first, mobile-first for field capture, and desktop-strong for finance, review, reconciliation, close, and reports.

## 2. Navigation

Primary navigation stays small:

1. **Home** — my work, exceptions, portfolio pulse;
2. **Investments** — projects and opportunities;
3. **Operations** — sector-specific work queues and plans;
4. **Money** — cash, obligations, sales, capital, reconciliation, close;
5. **Investors** — participants, calls, allocations, distributions, statements;
6. **Documents** — evidence, expiry, missing items;
7. **Reports** — project/portfolio/investor packs;
8. **Settings** — organization, roles, policies, integrations.

On mobile, show Home, Investments, Operations, Money, and More. Investor-role users receive a separate minimal portal: Overview, Investments, Activity, Documents, Profile.

## 3. Project workspace

Opening a project keeps persistent context:

- name, sector, lifecycle, manager, date range;
- data quality and close status;
- cash, realized result, committed cost, valuation, distributable cash—each explicitly labeled;
- urgent exceptions and next milestone;
- tabs: Overview, Operations, Money, Investors, Documents, Reports, Timeline.

Sector tab vocabulary changes by sector; the project shell does not.

| Real estate | Agriculture | Livestock |
|---|---|---|
| Assets, parcels, phases, milestones, valuations, disposal | Farm map, fields, cycles, activities, inputs, harvest lots | Sites, herds, cohorts, animals, health, weight, movement |

## 4. Home by role

### Owner/investment manager

- decisions/approvals due;
- projects off plan, cash pressure, overdue obligations/calls;
- stale valuations and close status;
- portfolio performance with explicit realized/valued distinction;
- recent material events.

### Finance

- unidentified cash and unreconciled lines;
- obligations/payment proposals;
- missing evidence/mappings;
- close checklist and posting/integration failures;
- capital calls, allocations, distributions requiring action.

### Sector operator

- today’s planned work;
- quick capture by project/location;
- drafts waiting to sync/confirm;
- stock/health/milestone alerts;
- recent records and correction route.

### Investor

- own contributed capital, allocated result, distributions, and current position;
- calls/notices and due dates;
- latest project update and documents;
- visible “as of,” status, valuation basis, and contact route.

## 5. Core screen patterns

### Work queue

Default list pattern for approvals/exceptions: clear title, project, amount/quantity, state, age/due date, owner, severity, and primary action. Filters are saved by user. Bulk action is forbidden for material approvals unless each subject and total impact are visible.

### Record detail

Header contains state, reference, project, date, owner, amount/quantity, and actions. Body uses:

- summary;
- linked parties/sector objects;
- financial/quantity impact;
- evidence;
- approvals;
- timeline and corrections.

### Wizard

Use only for setup or complex, infrequent actions: project activation, agreement version, opening import, allocation, distribution, close. Steps show validation and saved draft; final review summarizes changes and effects before submit.

### Quick capture

For frequent field events: project preselected, large touch targets, scan/photo optional, smart defaults, unit shown beside value, “save draft” distinct from “confirm.” Never put accounting terminology into operator capture.

### Financial review

Split view: source/evidence, business summary, posting preview, approvals and exceptions. Debits/credits are available to finance but not the only explanation; show plain-language effect first.

## 6. Number and status semantics

- Currency always includes code/symbol and organization formatting.
- Negative values use sign and color/icon; color alone is insufficient.
- Percentages disclose basis; returns show date range and cash-flow scope.
- “As of” appears on every balance/report.
- Estimated, proposed, approved, posted, reconciled, paid, reversed, and closed have distinct badges.
- Loading, empty, filtered-empty, error, no-access, offline, conflict, and stale-data states are distinct.
- Dashboard totals link to filtered ledgers; no dead KPI cards.

## 7. Arabic and localization

- Arabic is the authored source for product language; English is a translation.
- RTL is structural, not a CSS mirror afterthought; directional icons and financial signs are reviewed.
- Accept Arabic and Latin digits in entry; normalize internally.
- Store ISO dates/times; display locale/timezone explicitly around cut-off.
- Keep accounting/sector terminology consistent through a glossary, with short help text for unfamiliar terms.
- Do not translate proper identifiers, document numbers, currency codes, tags, or external reference values.

Initial glossary decisions:

| English | Arabic UI |
|---|---|
| Investment project | مشروع استثماري |
| Commitment | التزام رأسمالي |
| Capital call | طلب مساهمة رأسمالية |
| Contribution | مساهمة مستلمة |
| Allocation | تخصيص نتيجة/حصة |
| Distribution | توزيع مستحق |
| Realized result | نتيجة محققة |
| Management valuation | تقييم إداري |
| Distributable cash | نقدية قابلة للتوزيع |
| Reconciliation | مطابقة وتسوية |

## 8. Mobile and offline

- Operator actions must work at 360px width with one primary action per screen.
- Capture drafts show offline/local state and last sync attempt.
- Attachment compression preserves original where required and never removes evidence metadata silently.
- Conflict UI compares local base, server current version, and user draft; money/approval conflicts require discard or explicit recreate—not automatic merge.
- Finance-heavy tables provide responsive summary cards on mobile and full columns/export on desktop.

## 9. Accessibility baseline

- Target WCAG 2.2 AA for customer and investor interfaces.
- Keyboard access, visible focus, correct landmarks/headings, semantic controls, form labels, error summary, and focus movement.
- Minimum touch target, contrast, reduced-motion support, zoom/reflow, and screen-reader names.
- Tables retain headers/relationships; complex charts have numeric table equivalents.
- Confirmation dialogs state the object and consequence; destructive-looking corrections explain reversal behavior.

## 10. Safety and trust UX

| Risky action | Required UX |
|---|---|
| Change agreement | Effective date, impacted periods, version comparison, approval |
| Change bank instruction | Old/new masked comparison, re-auth, independent approval |
| Post payment | beneficiary, account, amount, purpose, evidence, duplicates, cash impact |
| Close/reopen period | blocker checklist, affected reports, reason, approver |
| Allocate result | source period, rule version, participant lines, rounding, comparison |
| Approve distribution | available/distributable cash bridge, obligations/reserve, lines, payment separation |
| Reverse posting | original impact, reversal date/period, reason, replacement link |
| Import opening data | totals, mapping, rejected rows, control balance, sign-off |

No dark patterns, false urgency, hidden fees, or optimistic “success” before server commit.

## 11. Empty-state onboarding

Real production accounts start empty. Onboarding uses a checklist, not fabricated portfolio data:

1. configure organization/currency;
2. invite minimum roles;
3. create first project;
4. add agreement and sector baseline;
5. import/review opening data if needed;
6. post first contribution/cost;
7. generate first project statement.

A separate clearly labeled sandbox/demo organization may contain guided sample data.

## 12. Design-system foundations

- semantic color tokens for surface/text/border/action/success/warning/danger/info and sector accents;
- typography optimized for Arabic reading and tabular numerals;
- spacing/density modes for field vs finance views without two design systems;
- primitives: button, input, money/quantity field, selection card, status badge, table, timeline, evidence viewer, approval panel, exception callout, drilldown metric;
- domain components are composed from primitives and include state/permission handling.

## 13. UX validation

Validate each workflow during its delivery slice and before production release. Do not block the first code scaffold on an eight-flow prototype. For material workflows, include:

- one owner/manager;
- one finance/accounting user;
- one operator from the first launch sector;
- one investor/partner.

Tasks: activate project, record contribution, capture sector event, post cost/payment, close period, approve distribution, understand investor statement, correct an error. Measure completion, errors, terminology confusion, and reliance on facilitator—not visual preference alone.

## 14. UX acceptance criteria

- a first-time user can identify the next action and project context;
- every total drills to composition/source;
- no material action is available outside its permission/state;
- mobile operator flow takes the minimum necessary fields and can draft offline;
- finance can see business meaning and journal effect;
- investor cannot see another investor’s data;
- Arabic layout is verified independently from English;
- reports communicate date, policy/basis, status, and data completeness.

