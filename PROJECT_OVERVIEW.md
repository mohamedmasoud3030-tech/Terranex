# Terranex Project Overview

> Archaeology snapshot: 2026-08-17  
> Verified repository baseline: `main` at `9488588f0c6fd1984a1c09769af480f85905c661`  
> Discovery only: this document records the current implementation and does not create new product requirements.

## Evidence labels

- **Verified** — supported by current code, configuration, migrations, or executable checks at the baseline SHA.
- **Inference** — conservative conclusion from verified artifacts, not directly exercised end-to-end.
- **Unknown** — not established from the repository/currently connected runtime accounts.
- **Contradiction** — current documentation and executable/current implementation disagree.

## Product purpose and boundary

**Verified:** Terranex is a private investment-operations application for work across real estate, agriculture, and livestock.

Implemented hierarchy:

```text
Organization
  -> Investment Portfolio
    -> Investment Project
```

A portfolio is an operational/reporting parent, not a fund, legal entity, SPV, investor pool, or second accounting ledger. Repository instructions also explicitly exclude public crowdfunding, custody/wallets, brokerage/trading, and a statutory general ledger from the current product boundary.

## Users, roles, and tenant model

**Verified:**

- Supabase Auth establishes user identity.
- Organization membership is the tenant boundary.
- Membership roles are `OWNER` and `MEMBER`.
- Membership states are `ACTIVE` and `INACTIVE`.
- Organization onboarding grants the creator `OWNER` membership through a database RPC.
- The authenticated workspace resolves organization/project context before protected operations.

### Account lifecycle actually found

**Verified application flows:**

- Email/password login.
- Logout.
- Authenticated first-organization onboarding.
- Existing authenticated members enter the application workspace.

**Not found in current application code:**

- Self-service sign-up.
- Password reset.
- User invitation.
- Application UI/API for administrator user provisioning.

Whether those missing flows are handled operationally outside the application is **unknown** from the repository and currently connected accounts.

## Primary journeys represented by the implementation

These journeys are supported by current routes/features/actions/RPCs/migrations. Except where explicitly stated, they were not browser-exercised against a live Terranex deployment during this pass.

1. Authenticate and establish organization context.
2. Create/browse portfolios and projects.
3. Capture project intake/readiness and terms.
4. Record funding parties, commitments, and contributions without asserting unapproved economic entitlement.
5. Operate project budget, costs, cash, revenue, close, controls, integrity, governance, and pilot workflows.
6. Run procurement/receiving and vendor-finance workflows with database controls.
7. Run real-estate, agriculture, and livestock operations.
8. Inspect project statements/performance and portfolio roll-up views.
9. Work with cross-sector asset information.

## Route inventory

The production build at the baseline SHA compiled **30 application routes**. The Next.js framework also emitted `/_not-found`, which is not counted as a Terranex product route. “Build-verified” means the route compiled successfully; it does not mean the complete live journey was browser-tested.

| Route | Area | Verification |
|---|---|---|
| `/` | Authenticated workspace entry | Build-verified |
| `/assets` | Cross-sector assets | Build-verified |
| `/intake` | Organization/workspace intake | Build-verified |
| `/login` | Authentication | Build-verified; static route |
| `/onboarding` | Organization creation | Build-verified; code-inspected |
| `/portfolios` | Portfolio list/workspace | Build-verified |
| `/portfolios/[portfolioId]` | Portfolio detail/roll-up | Build-verified |
| `/portfolios/new` | Portfolio creation | Build-verified |
| `/projects/[projectId]` | Project entry | Build-verified |
| `/projects/[projectId]/agriculture` | Agriculture workspace | Build-verified |
| `/projects/[projectId]/budget` | Project budget | Build-verified |
| `/projects/[projectId]/cash` | Project cash | Build-verified |
| `/projects/[projectId]/close` | Period/project close | Build-verified |
| `/projects/[projectId]/controls` | Project controls | Build-verified |
| `/projects/[projectId]/costs` | Project costs | Build-verified |
| `/projects/[projectId]/funding` | Funding | Build-verified |
| `/projects/[projectId]/governance` | Governance | Build-verified |
| `/projects/[projectId]/intake` | Project intake/readiness | Build-verified |
| `/projects/[projectId]/integrity` | Integrity center | Build-verified |
| `/projects/[projectId]/investors` | Funding-party/investor records | Build-verified; entitlement guardrail code-inspected |
| `/projects/[projectId]/livestock` | Livestock workspace | Build-verified |
| `/projects/[projectId]/livestock/operations` | Livestock operations | Build-verified |
| `/projects/[projectId]/operations` | Sector/project operations | Build-verified |
| `/projects/[projectId]/overview` | Project overview | Build-verified |
| `/projects/[projectId]/pilot` | Pilot/UAT/reconciliation | Build-verified |
| `/projects/[projectId]/procurement` | Procurement/receiving | Build-verified |
| `/projects/[projectId]/revenue` | Project revenue | Build-verified |
| `/projects/[projectId]/statements` | Statements/performance | Build-verified |
| `/projects/[projectId]/terms` | Project terms | Build-verified |
| `/projects/new` | Project creation | Build-verified |

All application routes except `/login` were emitted as dynamic routes by the verified production build.

## Feature inventory

### Shared/core

**Verified modules and/or migrations exist for:**

- Authentication and organization membership.
- Organizations, portfolios, projects, intake/readiness, and terms.
- Funding parties, commitments, and contributions.
- Budget, costs, cash, revenue, finance/journal tracing.
- Close/correction, controls, approvals/exceptions, governance, integrity, pilot/reconciliation.
- Procurement and receiving.
- Vendor finance, contracts, credits, payment allocation, advances, and settlement controls.
- Currency/tax contract foundations.
- Project performance and portfolio roll-ups.
- Cross-sector assets/performance.
- Allocation/distribution mechanisms retained historically but economically fail-closed pending policy.

### Real estate

**Verified:** real-estate code and migrations exist for project operations and revenue/property/rental foundations.

### Agriculture

**Verified:** agriculture code/migrations cover lifecycle/foundations, activities, inputs, harvest, land, sales, profitability, and command controls.

### Livestock

**Verified:** livestock code/migrations cover foundation, lifecycle, movement, biological events, operational/commercial workflows, closeout, access control, and idempotent command handling.

## Investor/economic-entitlement safety boundary

**Verified:** current `main` deliberately fails closed for unapproved investor economics.

- The Investors page does not present ownership, profit share, or distribution entitlement as established truth.
- Current database safety controls revoke/block legacy economic mutators pending an approved owner policy.
- Funding parties, commitments, and contributions can be represented without deriving unapproved economic rights.
- `BD-012` is the current open business decision governing investor economics, distribution mechanics, and capital lifecycle policy.

Therefore, **economic ownership/profit distribution is not an enabled commercial truth on this baseline**.

## Frontend characteristics

### Rendering/state/forms

- Next.js App Router + React 19.
- Server Components and Server Actions are primary patterns.
- Zod validates action/form inputs.
- Supabase SSR clients provide authenticated server-side data access.
- No Redux/Zustand/TanStack Query/global client-state dependency is present; state is primarily server-derived with local client state where needed.

### Language/direction

- Current root HTML is `lang="ar"` and `dir="rtl"`.
- Noto Sans Arabic is configured.
- Repository instructions say English/LTR is supported, but no i18n provider/routing/dependency was found and the current root layout is fixed Arabic/RTL.
- **Verified:** Arabic/RTL. **Unverified:** implemented English/LTR switching/support.

### Responsive/accessibility patterns

**Verified in current CSS/components:**

- Responsive behavior around `960px` and `720px`.
- Horizontal overflow protection for wide tables.
- `:focus-visible` styles.
- `prefers-reduced-motion` handling.
- Testing Library coverage for parts of the UI.

**Not verified:** full WCAG 2.2 AA compliance. Current CI has no dedicated automated accessibility gate.

## PWA/offline status

**Verified absent:**

- No PWA dependency/configuration.
- No web app manifest.
- No service worker.
- No install/update/offline cache flow.

This aligns with current architecture guidance and with `BD-009` (“Browser installability”) still OPEN; absence is not treated as a regression in this discovery report.

## Explicit integrations found

- Supabase Auth/PostgreSQL through `@supabase/ssr` and `@supabase/supabase-js`.
- Repository architecture references private Supabase Storage as the intended storage boundary; live bucket/policy state is unverified.
- Vercel deployment intent/configuration and a manual pilot-activation workflow.

No application SDK/configuration was found for email delivery, payment processors, analytics, AI providers, or maps. External infrastructure not represented in the repository remains unknown.

## Documentation contradictions

1. **`README.md` status is stale.** It describes procurement pricing/invoicing/payment and several later capabilities as future work, while current code/migrations/routes contain substantially later procurement, vendor-finance, budget, approval, close, integrity, performance, agriculture, livestock, and portfolio work.
2. **Business-decision count conflicts.** `AGENTS.md` refers to 13 policy questions; current `docs/OPEN_BUSINESS_DECISIONS.md` contains 12 IDs (`BD-001` through `BD-012`).
3. **English/LTR implementation is unverified.** `AGENTS.md` states support, while the current root runtime is fixed Arabic/RTL and no i18n mechanism was found.

## Discovery limits

- No live Terranex project was visible through the currently connected Supabase account.
- No live Terranex project was visible through the currently connected Vercel team.
- Production URL behavior, live database state, storage, Auth population, logs, monitoring, deployment history, backups, and rollback readiness therefore remain **unknown**.
- The GitHub connector exposes the remote repository, not a local checkout; no claim is made about any developer's local uncommitted worktree state.
