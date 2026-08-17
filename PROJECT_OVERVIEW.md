# Terranex Project Overview

> Archaeology snapshot: 2026-08-17  
> Verified repository baseline: `main` at `9488588f0c6fd1984a1c09769af480f85905c661`  
> Scope: discovery only. This document does not define new product requirements.

## How to read this document

- **Verified**: supported by current code, configuration, migrations, or executable checks at the baseline SHA.
- **Inference**: a conservative conclusion from multiple verified artifacts, but not directly exercised end-to-end.
- **Unknown**: cannot be established from the repository or currently connected runtime accounts.
- **Contradiction**: two current artifacts disagree; the executable/current implementation is identified explicitly.

## Product purpose and boundaries

**Verified:** Terranex is a private investment-operations application for managing work across three sectors: real estate, agriculture, and livestock.

The implemented hierarchy is:

```text
Organization
  -> Investment Portfolio
    -> Investment Project
```

A portfolio is an operational/reporting parent. Repository instructions explicitly reject treating it as a fund, legal entity, SPV, investor pool, or second accounting ledger.

The current repository is also explicit about what Terranex is **not**: it is not a public crowdfunding marketplace, custody/wallet platform, brokerage/trading system, or statutory general ledger.

## Target users and roles

### Verified user model

- The application is private and authentication-gated.
- Supabase Auth supplies the authenticated user identity.
- Organization membership is the tenant boundary.
- Database membership roles are `OWNER` and `MEMBER`.
- Membership status is `ACTIVE` or `INACTIVE`.
- Creating an organization through onboarding grants its creator `OWNER` membership through a database RPC.
- The authenticated application shell labels the active user context as owner/member.

### Account lifecycle actually found

**Verified:**

- Login with email/password.
- Logout.
- First authenticated-user onboarding to create an organization.
- Existing members are routed into the authenticated workspace.

**Not found in the current application code:**

- Self-service sign-up flow.
- Password-reset flow.
- User invitation flow.
- Application UI/API for an administrator to provision users.

The absence of these flows is consistent with open business decision `BD-012`; it must not be interpreted as an approved product policy.

## Primary journeys found in the current application

The following journeys are represented by current routes, feature modules, Server Actions, database RPCs, and migrations. A journey listed here is not claimed to have been browser-tested unless explicitly stated.

1. Authenticate and establish organization context.
2. Create and browse investment portfolios.
3. Create and browse projects within the organization/portfolio hierarchy.
4. Capture project intake/readiness information and project terms.
5. Record funding parties, commitments, and contributions without asserting unapproved economic entitlement.
6. Operate project cost, cash, revenue, close, controls, integrity, governance, and pilot workflows.
7. Run sector-specific real-estate, agriculture, and livestock operations.
8. Run procurement/receiving and vendor-finance workflows backed by database controls.
9. Inspect project statements/performance and portfolio roll-up views.

## Route inventory

The production build at the baseline SHA compiled the following **29 routes**. “Build-verified” means Next.js included and compiled the route successfully; it does **not** mean the route was exercised against a live Terranex deployment during this archaeology pass.

| Route | Area | Verification |
|---|---|---|
| `/` | Authenticated workspace entry | Build-verified |
| `/assets` | Cross-project/organization assets | Build-verified |
| `/intake` | Organization/workspace intake | Build-verified |
| `/login` | Authentication | Build-verified; only static route in build graph |
| `/onboarding` | Organization creation | Build-verified; code-inspected |
| `/portfolios` | Portfolio list/workspace | Build-verified |
| `/portfolios/[portfolioId]` | Portfolio detail/roll-up | Build-verified |
| `/portfolios/new` | Portfolio creation | Build-verified |
| `/projects/[projectId]` | Project entry | Build-verified |
| `/projects/[projectId]/agriculture` | Agriculture workspace | Build-verified |
| `/projects/[projectId]/cash` | Project cash | Build-verified |
| `/projects/[projectId]/close` | Period/project close | Build-verified |
| `/projects/[projectId]/controls` | Project controls | Build-verified |
| `/projects/[projectId]/costs` | Project costs | Build-verified |
| `/projects/[projectId]/funding` | Funding | Build-verified |
| `/projects/[projectId]/governance` | Governance | Build-verified |
| `/projects/[projectId]/integrity` | Integrity center | Build-verified |
| `/projects/[projectId]/intake` | Project intake/readiness | Build-verified |
| `/projects/[projectId]/investors` | Funding-party/investor record view | Build-verified; entitlement guardrail code-inspected |
| `/projects/[projectId]/livestock` | Livestock workspace | Build-verified |
| `/projects/[projectId]/livestock/operations` | Livestock operations | Build-verified |
| `/projects/[projectId]/operations` | Sector/project operations | Build-verified |
| `/projects/[projectId]/overview` | Project overview | Build-verified |
| `/projects/[projectId]/pilot` | Pilot/UAT/reconciliation workspace | Build-verified |
| `/projects/[projectId]/procurement` | Procurement and receiving | Build-verified |
| `/projects/[projectId]/revenue` | Project revenue | Build-verified |
| `/projects/[projectId]/statements` | Project statements/performance | Build-verified |
| `/projects/[projectId]/terms` | Project terms | Build-verified |
| `/projects/new` | Project creation | Build-verified |

## Feature inventory

### Shared/core

**Verified feature modules and/or migrations exist for:**

- Authentication and organization membership.
- Organizations, portfolios, and projects.
- Intake/readiness and project terms.
- Funding and contribution records.
- Cost and cash operations.
- Revenue.
- Finance/journal tracing.
- Allocation mechanisms retained in the codebase but economically fail-closed pending policy.
- Close/correction workflows.
- Controls and approval/exception handling.
- Governance.
- Integrity checks.
- Pilot/reconciliation workflows.
- Procurement and receiving.
- Vendor finance, contracts, credits, payment allocation, advances, and settlement controls.
- Budget control.
- Currency/tax contract foundations.
- Project performance and portfolio roll-ups.
- Cross-sector assets.

### Real estate

**Verified:** real-estate feature code and migrations exist, including project operations and basic property/rental-income foundations.

### Agriculture

**Verified:** agriculture modules and migrations cover foundations, activities, inputs, harvest, land, sales, profitability, and command/lifecycle controls.

### Livestock

**Verified:** livestock modules and migrations cover foundation, lifecycle, movement, biological events, operational/commercial workflows, closeout, access control, and idempotent command handling.

## Investor/economic-entitlement safety boundary

**Verified:** historical allocation/distribution mechanisms exist in repository history and schema evolution, but current `main` deliberately fails closed for unapproved investor economics.

- The Investors page explicitly avoids presenting ownership, profit-share, or distribution entitlement as established truth.
- The current database safety migration revokes/blocks legacy economic mutators pending an approved owner policy.
- Funding parties, commitments, and contributions can be represented without deriving unapproved economic rights.

Therefore, **economic ownership/profit distribution is not an enabled commercial feature on this baseline**.

## Frontend characteristics

### Rendering and state

- Next.js App Router with React 19.
- Server Components and Server Actions are the primary application pattern.
- Zod validates action/form inputs.
- Supabase SSR clients provide authenticated server-side data access.
- No global client-state library is present in `package.json`; client state is local where needed.

### Language and direction

- Root HTML is currently `lang="ar"` and `dir="rtl"`.
- Noto Sans Arabic is configured.
- Repository instructions mention English/LTR support, but no implemented i18n routing/provider/dependency was found and the root layout is fixed Arabic/RTL.
- **Status:** Arabic/RTL is verified; English/LTR support is unverified and the instruction currently conflicts with the observed implementation.

### Responsive and accessibility patterns

**Verified in CSS/components:**

- Responsive layout behavior around `960px` and `720px` breakpoints.
- Horizontal overflow handling for tables on smaller screens.
- `:focus-visible` styling.
- `prefers-reduced-motion` handling.
- Semantic/application accessibility patterns are covered by some component tests.

**Not verified:** full WCAG 2.2 AA compliance. The CI pipeline has no dedicated automated accessibility gate.

## PWA/offline status

**Verified absent from this baseline:**

- No PWA dependency/configuration.
- No web app manifest.
- No service worker.
- No app icons/public PWA asset set.
- No offline cache/update/install flow.

This is consistent with the current repository architecture instruction to avoid PWA/offline-sync complexity until a proven workflow requires it.

## Explicit integrations found

- Supabase Auth/PostgreSQL through `@supabase/ssr` and `@supabase/supabase-js`.
- Vercel deployment intent/configuration and a manual pilot-activation workflow.

No application SDK/configuration was found for email delivery, payment processors, analytics, AI providers, or maps. This statement is limited to the current repository; live infrastructure that is not represented in the repository remains unknown.

## Current documentation contradictions

1. **README status is stale.** It describes procurement pricing/invoicing/payment work as future work, while current code/migrations contain later procurement, vendor-finance, contract, payment-allocation, budget, approval, close, integrity, and performance work.
2. **Database command names in `AGENTS.md` are stale.** It mentions `npm run db:test` and `npm run db:shell`; current `package.json` exposes `npm run test:db`, and the DB shell is a script (`scripts/db-shell.sh`) rather than an npm script.
3. **Business-decision count conflicts.** `AGENTS.md` refers to 13 policy questions, while `docs/OPEN_BUSINESS_DECISIONS.md` currently contains 12 open IDs (`BD-001` through `BD-012`).
4. **English/LTR claim is unverified.** Repository instructions state support, but the current root runtime layout is fixed Arabic/RTL and no i18n mechanism was found.

## Discovery limits

- No live Terranex Supabase project was visible through the currently connected Supabase account.
- No live Terranex Vercel project was visible through the currently connected Vercel team.
- Therefore production URL behavior, live database state, storage buckets, auth-user population, runtime logs, monitoring, deployment history, live backups, and rollback readiness were **not verified**.
- The GitHub connector exposes the remote repository, not a local checkout; local uncommitted changes/worktrees cannot be asserted clean or dirty from this discovery session.
