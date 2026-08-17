# AI Project Assessment — Terranex

**Date:** 2026-08-17
**Branch:** `arena/01a0112b-terranex` (base: `main` @ `59809c77cdb3efc6acb536b61a69f5a905b42abb`)
**Author:** autonomous product/engineering review (Arena Agent Mode)
**Basis:** repository code, 99 migrations, 108 database suites, 54 Vitest files, production build, running server smoke, GitHub CI evidence. Every claim below was re-verified on this branch, not copied from earlier reports.

## 1. What the product is

Terranex is an Arabic-first (RTL) **Investment Operations OS** for private investment operators in Egypt and MENA. It organizes data as:

`Organization → Investment Portfolio → Investment Project → sector facts / finance facts / evidence`

Projects belong to exactly one primary sector: `REAL_ESTATE`, `AGRICULTURE`, or `LIVESTOCK`. The product connects daily operations with finance and control: assets and operating cycles, suppliers and procurement, commitments and payments, cash and bank reconciliation, revenue and collections, double-entry journal, period close, evidence, risks, and decisions.

**Confirmed boundaries** (from canonical docs `AGENTS.md`, `docs/greenfield/*`, `docs/decisions/*`):

- Not a public marketplace, crowdfunding platform, bank, or custody service.
- Never moves real money; it records and approves what happened through external bank channels.
- Not a statutory/legal ledger or a general ERP.
- `Portfolio` is a management/reporting parent over independent projects — not a fund, SPV, legal entity, or investor pool.
- Investor ownership/entitlement/allocation/distribution economics are **policy-blocked** until the owner resolves business decisions `BD-001…BD-012` (all OPEN). The database registry `policy_authority` ships empty; policy-dependent writes fail closed.

## 2. Who it serves and the domain workflow

- **Users:** the operator company's staff. Actual runtime roles: `OWNER` and `MEMBER` (organization-scoped `memberships.role`). Canonical docs describe richer role names (Investment Manager, Finance Officer, Sector Manager, Reviewer, Auditor) that are not implemented as runtime roles.
- **Investors:** appear as `project_participants` (party identity/agreement transparency only). No investor login, no self-scope, no entitlement numbers (by design until R14/R15).
- **Workflow:** sign in → create organization → create portfolio(s) → create project with a sector → run the sector workspace (real estate / agriculture / livestock) → shared finance & control (budget, obligations, payments, cash, bank reconciliation, revenue, period close, corrections) → shared procurement (suppliers → PR → PO → receiving → invoice → payment proposal) → governance (risks, immutable decisions) → pilot readiness (opening import, reconciliation, UAT, rehearsals).
- **Industry expectation:** exact money (bigint minor units, no floats), double-entry journal, maker/checker segregation, append-only posted facts with reversal/repost, tenant isolation, idempotent commands, audit trail — all implemented and database-tested.

## 3. Roles, permissions, routes, journeys

- All routes except `/login` require a Supabase Auth session (`src/proxy.ts`). RLS isolates data per `organization_id` with `is_active_member` checks. Write commands are SECURITY DEFINER RPCs that take the actor from `auth.uid()`; the browser never supplies authoritative balances, approval outcomes, or identities.
- Sensitive approvals are OWNER-gated and many commands enforce maker/checker segregation. Agreement activation and capital-call issuance were raised to OWNER-only by the policy-safety migration.
- **31 routes** exist in the production build (verified). The previously-reported missing `/projects` route now exists (`src/app/(app)/projects/page.tsx`) — the old P1 is fixed.
- Critical journeys verified by the 108-suite database gate and 720 Vitest tests: project creation (idempotent, payload-bound), all three sector lifecycles, procure-to-pay, finance core, period close + correction + reopen replay-safety, backup/restore rehearsal, two-tenant RLS isolation with a hostile tenant, and the full synthetic company scenario (R13) with exact Project→Portfolio→Organization roll-up differences of zero.

## 4. Technology and operations

- **Frontend/backend:** one Next.js 16 App Router modular monolith (React 19, Server Actions, server components), Tailwind, Arabic/RTL (`lang="ar" dir="rtl"`), EGP-first exact money.
- **Backend:** one Supabase project (PostgreSQL 16) — Auth (email/password, session cookies), private Storage (`procurement-evidence`), default-deny RLS, 99 forward migrations.
- **Deployment:** Vercel (`vercel.json`), GitHub Actions CI (`greenfield-ci.yml` app + database jobs, least-privilege `contents: read`), `pilot-activation.yml` workflow for read-only Supabase inspection with optional migration apply.
- **Tests:** 54 Vitest files / 720 tests (unit, Zod, idempotency-lifecycle, contract/characterization); 108 database suites (migration replay, forward upgrades, concurrency, RLS, backup/restore rehearsal, R13 scenario).
- **Docs:** extensive and occasionally overlapping/contradictory (see §6). Runbooks exist for incidents, backup/restore, correction, migration failure.
- **Not present:** no public sign-up, password reset, MFA, org switcher, PWA/offline, email/SMS notifications, payment gateways, jobs/queues, structured logging/metrics/alerting, health endpoint, app-level error boundary, English locale. These are consistent with the pilot phase scope, except where noted in the improvement plan.

## 5. Verified current state (what is true on this branch)

| Gate | Result |
|---|---|
| `npm ci` | PASS |
| `npm run lint` | PASS |
| `npm run typecheck` | PASS |
| `npm test` | PASS — 54 files / 720 tests |
| `npm run build` | PASS — 31 routes |
| `npm audit` (full + prod-only, low level) | PASS — 0 vulnerabilities |
| `npm run db:test` **locally** | **PASS — full replay + all 108 suites on real PostgreSQL 16.14** (previous session could not run this locally: no psql/Docker; resolved by provisioning a real PostgreSQL 16 in the sandbox and building real psql/pg_dump/pg_restore 16.4) |
| GitHub CI on `main` (run `32052760708`) | success (app + database jobs) |
| Running server smoke (placeholder env) | `/login` 200 Arabic/RTL; `/`, `/projects`, `/portfolios`, `/assets` → 307 `/login` for anonymous |

## 6. Confirmed problems (with evidence)

### 6.1 Demo seed is broken on a fresh database (P1 for demo/pilot operations)
`scripts/demo/seed_real_estate_showcase.sql` still calls `attach_contribution_cash` and the six S5 allocation/distribution commands. Since migration `20260816062000_pre_owner_policy_safety.sql`, those commands fail closed unless `policy_authority` contains approved rows for the org — and the registry ships empty. The seed never activates any policy, so on a fresh schema the seed aborts mid-run (single transaction → full rollback) and the documented "permanent showcase" cannot be created or re-created. Evidence: seed lines 254–257 and 505–515 vs. `require_policy_activated` gates and the six `*_policy_gate` triggers; the R13/R10 characterization tests confirm the registry is intentionally empty. The live pilot DB still holds the old showcase data, so this only bites on reset/re-provision — which the pilot-activation workflow supports.

### 6.2 No organization switcher; `organizations[0]` everywhere (P2)
A user with memberships in more than one organization silently operates on the first one (`getOrganizations()` + `orgs[0]` in Home, `/projects`, `/portfolios`, `/portfolios/new`, `/assets`, `/intake`, `/projects/new`). Creating a project or portfolio while the wrong org is "active" is a real mis-entry risk. RLS allows multi-org memberships, so the UI gap is real, not theoretical. Project/portfolio-scoped pages resolve their org from the entity itself (correct) and are unaffected.

### 6.3 `/intake` copy contradicts the three-sector product (P2 UX)
The intake start page still says "العملة الوظيفية ثابتة: جنيه مصري. القطاع الأول: عقاري." and "أنشئ مشروعًا عقاريًا واحدًا" even though project creation supports three sectors. Users following the copy are misled about product scope.

### 6.4 Logged-in users can land on `/login` again (P3)
No redirect for authenticated users visiting `/login`; they see the sign-in form while already signed in. Confusing for expired-session recovery flows (bookmarks, password managers).

### 6.5 No app-level error boundary (P3)
Only some route groups have `error.tsx`. An unhandled server error in a page without a local boundary renders the default English Next.js error page to Arabic users.

### 6.6 No health endpoint (P3 ops)
No `/api/health` for deployment/post-deploy smoke checks.

### 6.7 CI does not run `npm audit` (P3 security hardening)
`npm audit` passes today (verified) but is not part of the workflow, so future dependency drift is not gated.

### 6.8 Historical/documented debt (kept for awareness; not scheduled)
- Action wrappers (`command-actions.ts`) transitioned inconsistently across features.
- `.env.production` is tracked (public values only) and is loaded by default builds — acceptable for a public URL/publishable key, but env separation should be documented (already is, in the file header).
- Duplicate migration timestamp `20260814001200` used by two files (the canonical runner handles it; Supabase tooling that assumes unique prefixes may not).
- Many overlapping status/history docs make "current state" hard to find — these four AI_* docs are the new canonical status entry point.

## 7. What is NOT claimed

- No authenticated browser journeys were exercised against the shared Supabase pilot project (no credentials were requested or used; the repo forbids touching shared/production Supabase without authorization).
- Local database verification uses a disposable PostgreSQL 16.14 provisioned inside the sandbox plus locally built psql/pg_dump/pg_restore 16.4; it does not touch the pilot project.
- Passing CI/tests is not production readiness: no live deployment, customer UAT, or production restore is claimed.
- `r15:admission` remains BLOCKED — correct and intended until the owner resolves BD-001…BD-012.
