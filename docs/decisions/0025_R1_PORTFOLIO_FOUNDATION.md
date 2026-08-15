# ADR 0025 — R1 Portfolio Foundation

**Status:** Accepted for R1  
**Date:** 2026-08-15

## Decision

R1 implements the first safe runtime slice of the canonical management
hierarchy **Organization → Investment Portfolio → Investment Project**
established by R0. The slice is management/reporting-only.

### Portfolio meaning

`InvestmentPortfolio` is an organization-scoped management and reporting
parent. It is **not** a fund, SPV, legal entity, partnership, investor pool,
pooled cash account, accounting entity, second ledger, ownership object,
entitlement scope, capital-call scope, or distribution scope. Its stored
facts are exactly: identity (`name`), management purpose (`description`),
lifecycle `status`, an optional descriptive `responsible_manager_id`
(an ACTIVE organization member; grants no permission), provenance
(`created_by`, `created_at`, `updated_at`), and the command
idempotency/hash columns required by the repository command pattern.
No currency, NAV, capital, fee, reserve, or investor column exists because
R1 has no reporting or economic semantics requiring them.

### Project boundary preservation

An Investment Project remains the authoritative operational, sector,
financial-attribution, execution, and close boundary. Portfolio membership
never rewrites project identity, sector, agreements, ledger sources, or
lifecycle, and is proven so by database tests asserting project truth is
byte-identical before and after assignment, removal, move, and portfolio
archiving.

### Membership / cardinality

One current parent Portfolio per Project, per the canonical ERD
(`INVESTMENT_PORTFOLIO ||--o{ INVESTMENT_PROJECT : groups`) and the R0 rule
that membership must not invent many-to-many economic semantics. Membership
is stored in `portfolio_project_assignments` rows that are only ever
soft-closed (`removed_at`/`removed_by`/`removal_reason`), never deleted or
rewritten, so historical membership remains explainable. Organization
coherence is database-enforced through composite foreign keys
(`portfolio_id, organization_id`) and (`investment_project_id,
organization_id`) against one `organization_id` column: cross-tenant
assignment is structurally impossible. Projects never silently acquire a
parent: the migration is additive and backfills nothing.

### Lifecycle

`DRAFT → ACTIVE`, `ACTIVE → ARCHIVED`, and `DRAFT → ARCHIVED` are the only
transitions. There is no backward or re-asserting transition. Every
transition is an explicit, reason-carrying, idempotent, expected-status-aware
command that appends to an append-only causal state-history chain
(`investment_portfolio_state_history`, S3/GF-013 pattern) and updates the
authoritative `status` column in one transaction, with a coherence trigger
guaranteeing chain/column agreement. Activation creates no rights, capital,
contributions, postings, ownership, allocations, or distributions. Archiving
never closes, archives, settles, or mutates member Projects. Archived
portfolios are read-only.

### Authorization, audit, idempotency

Commands are the security-definer RPCs
`create_investment_portfolio`, `update_investment_portfolio_metadata`,
`transition_investment_portfolio`, `assign_project_to_portfolio`,
`remove_project_from_portfolio`, and `move_project_to_portfolio`, all
granted to `authenticated` only and guarded by `is_active_member`. All three
tables are default-deny RLS with `force row level security`, a single
`select` policy per table, and `security_invoker` read views for the
application read path. Every material command writes `audit_events` in the
same transaction. Creation, transitions, assignment, removal, and move use
the GF-013 stored idempotency-key + sha256 request-hash + advisory-lock
pattern; metadata update is a convergent last-write command (identical
payload re-application yields identical state) with no economic effect.
Client forms follow the AGENTS idempotency-key lifecycle: one key per
logical submission, rotation only after confirmed success (shared
implementation in `src/shared/idempotency`, regression-tested for
successive successful submissions).

### Economic non-scope

R1 implements nothing from `docs/OPEN_BUSINESS_DECISIONS.md`. BD-001 …
BD-012 remain OPEN and unneeded by this slice: no portfolio investors,
balances, ownership, capital calls, contributions, capital accounts,
cross-project allocation/netting/transfer, distributable cash, reserves,
fees/carry, distributions, reinvestment, investor lifecycle, pooled cash, or
automatic Capital Deployment accounting. No UI metric requiring any of those
rules is displayed.

## Deferred

R2 — Portfolio Workspace & Project Drill-Down: derived project roll-ups
(lifecycle, sector, cash, realized result, committed cost, valuation, close
state, exceptions) with honest currency/as-of/completeness semantics and
drill-down to project composition and source truth. R3+ remains as defined
by the roadmap. A future decision may give Portfolio legal/fund meaning only
through an explicit recorded owner decision resolving the relevant OPEN
items.
