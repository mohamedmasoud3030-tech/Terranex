# Terranex Project Status

> Archaeology snapshot: 2026-08-17  
> Verified repository baseline: `main` at `9488588f0c6fd1984a1c09769af480f85905c661`  
> Baseline GitHub Actions run: `Greenfield CI` #454 (`32030212661`) — **success**.

## Executive status

The repository baseline is **green on its current automated quality gates**, but this archaeology pass does **not** establish production readiness.

Strongest verified result: the exact baseline SHA installs, lints, passes 714 Vitest tests, builds successfully, passes TypeScript checking, and passes complete PostgreSQL migration replay/database verification in CI.

Largest unresolved gap: no Terranex project is visible through the currently connected Supabase or Vercel accounts, so live production behavior and operational controls could not be verified.

Separate governance facts requiring owner review: GitHub currently reports the repository as **public** and `main` as **not branch-protected**. Public source visibility may be intentional; intent cannot be inferred from code.

## Baseline checks observed on the exact SHA

| Check | Result | Observed outcome |
|---|---|---|
| `npm ci --no-audit --no-fund` | PASS | 482 packages added |
| `npm run lint` | PASS | ESLint completed without failure |
| `npm test` | PASS | 52 test files; 714 tests passed; Vitest 3.2.7 |
| `npm run build` | PASS | Next.js 16.3.0 production build completed; 30 application routes compiled (+ framework `/_not-found`) |
| `npx tsc --noEmit` | PASS | TypeScript check completed without failure |
| `npm run db:test` | PASS | PostgreSQL 16; full migration replay and all SQL/concurrency verification suites passed |

There were **no failing baseline CI commands** on this exact SHA.

### Dependency-audit qualification

Current CI intentionally installs with `--no-audit`, so this discovery pass has **no verified npm vulnerability count**. A green baseline must not be interpreted as a completed dependency-security audit.

## Verified working areas

### Repository/build system

- Single npm/Next.js application; not a monorepo.
- Committed lockfile and deterministic CI install.
- Current automated gates cover lint, Vitest, production build, TypeScript, migration replay, SQL tests, and DB concurrency/replay/restore/smoke/isolation suites.
- CI triggers on `main` pushes, pull requests targeting `main`, and manual dispatch.

### Application shell/authentication

- Supabase email/password login.
- Logout.
- Authenticated-route gating in `src/proxy.ts`.
- Authenticated first-organization onboarding.
- Arabic/RTL root layout.
- Organization/portfolio/project workspace navigation.

### Tenant/database foundation

- Organization membership tenant boundary.
- `OWNER` / `MEMBER` roles and active/inactive membership state.
- RLS plus forced RLS on foundation tenant tables.
- Explicit database functions/RPCs for important mutations.
- Audit-event foundation.
- Foreign-key/index controls.

### Business/domain implementation present and migration-replay verified

- Portfolios/projects/intake/terms/funding.
- Budget/costs/cash/revenue/finance foundations.
- Real-estate operations.
- Agriculture operations/lifecycle.
- Livestock operations/lifecycle.
- Procurement/receiving.
- Vendor finance/contracts/credits/payment allocation/advances.
- Approval/exception controls.
- Close/integrity/performance/portfolio roll-up/governance foundations.
- Idempotency/concurrency protections covered by DB verification suites.

### Investor-policy safety

- Unapproved ownership/profit/distribution economics are fail-closed.
- The current Investors UI does not present economic entitlement as established fact.
- Legacy economic mutation mechanisms are blocked pending approved `BD-012` policy.

### Database verification

The DB runner applies all current migrations in order and runs SQL plus shell/concurrency suites covering policy races, close, allocation, lifecycle, opening placement, livestock monetary/operational behavior, portfolio behavior, procurement receipt concurrency, vendor payment allocation, data-preservation replay, forward upgrade, backup/restore, backup-failure safety, smoke, and S2 isolation.

## Existing failures and incomplete areas

### Baseline command failures

**None observed** in current `Greenfield CI` #454.

### Production runtime

**UNKNOWN:** no Terranex project is visible through the currently connected Supabase or Vercel accounts. This pass therefore did not verify:

- deployed production URL behavior;
- production migration/data state;
- production Auth configuration/user population;
- live RLS behavior against production data;
- Storage buckets/object policies;
- runtime logs/errors;
- monitoring/alerts;
- scheduled backups/retention;
- restore/rollback readiness.

### Repository visibility/credential-search scope

**VERIFIED:** GitHub reports `mohamedmasoud3030-tech/Terranex` as **public**.

**UNKNOWN:** whether that visibility is intentional.

Inspected env/config files expose public `NEXT_PUBLIC_*` application settings only; values are intentionally omitted here. Indexed repository searches for `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL`, and `DATABASE_URL` returned no matches. This is **not** equivalent to GitHub secret-scanning history or a forensic scan of every historical commit, so no claim is made that a secret never existed historically.

### Account lifecycle

**INCOMPLETE/UNKNOWN:** login/logout/onboarding exist, but no self-sign-up, password reset, invitation, or application admin-provisioning flow was found. Whether user provisioning is intentionally handled outside the application is not established.

### Investor economics

**OPEN by design:** `BD-012` leaves investor economics, distribution mechanics, and capital lifecycle policy undecided. Current fail-closed behavior is the correct verified safety posture, not a defect to bypass.

### English/LTR

**UNVERIFIED/CONTRADICTION:** `AGENTS.md` says English/LTR is supported, while current root runtime is fixed Arabic/RTL and no i18n system was found. `BD-008` keeps rollout scope OPEN.

### Browser E2E coverage

**RISK:** no Playwright/Cypress-style browser E2E framework/configuration is present. Successful compilation/component tests do not prove all live user journeys in a real browser/backend combination.

### Accessibility coverage

**RISK:** focus/reduced-motion/responsive patterns exist, but current CI has no dedicated automated accessibility gate. Full WCAG 2.2 AA compliance was not established.

### PWA/installability

**OPEN/not implemented:** no manifest/service worker/install/update/offline flow is present. `BD-009` (“Browser installability”) remains OPEN, so this is not classified as a regression.

### Operational observability

**UNKNOWN:** no dedicated application observability SDK/configuration was found, and the live platform project is unavailable for inspection. Production monitoring/alerting cannot be claimed.

### Dependency security

**UNKNOWN in this pass:** current CI uses `npm ci --no-audit --no-fund`; no verified npm-audit result was produced by the baseline workflow.

## Current open business decisions

`docs/OPEN_BUSINESS_DECISIONS.md` currently records **12 OPEN decisions**:

1. `BD-001` — Reporting calendar / time-zone convention.
2. `BD-002` — Pilot environment.
3. `BD-003` — Backup / restore drill target.
4. `BD-004` — Evidence retention and deletion policy.
5. `BD-005` — RPO / RTO.
6. `BD-006` — Pilot user cohort.
7. `BD-007` — UAT exit signatory.
8. `BD-008` — English / LTR rollout scope.
9. `BD-009` — Browser installability.
10. `BD-010` — External security assessment.
11. `BD-011` — Accounting export / reconciliation package.
12. `BD-012` — Investor economics, distribution mechanics, and capital lifecycle policy.

`BD-012` explicitly leaves undecided investor instrument/type, ownership/profit-share/allocation basis, legal structure, contribution/capital-call/refund/withdrawal/transfer states, waterfall/remainder rules, accrual/payment basis, and distribution reversal/recall/clawback/correction mechanics. Engineering must not invent those semantics before an owner decision is recorded.

## Documentation contradictions/staleness

| Artifact | Contradiction/staleness | Current verified source of truth |
|---|---|---|
| `README.md` | Describes the system as the first Greenfield slice and several now-present capabilities as future work | Current routes/features/migrations and successful full migration replay show substantially later implementation |
| `AGENTS.md` | Refers to 13 policy questions | Current `docs/OPEN_BUSINESS_DECISIONS.md` contains 12 IDs |
| `AGENTS.md` | States English/LTR support | Current runtime is fixed Arabic/RTL; no i18n mechanism found; `BD-008` remains OPEN |

The current `AGENTS.md` command names **do match** `package.json`: `db:test`, `db:shell`, and `r15:admission`.

## TODOs, dead code, duplication, legacy behavior

- GitHub indexed searches returned no `TODO` or `FIXME` hits on this baseline. This is not equivalent to a local raw-file grep.
- No dead-code analysis tool is configured, so absence of dead code cannot be claimed.
- No broad duplication scanner was verified in the current quality gates, so absence of duplication cannot be claimed.
- Historical allocation/distribution mechanisms remain represented, but current safety controls deliberately block unapproved economic mutation. This is intentional preservation plus fail-close, not proof that economic entitlement is enabled.

## Git/repository governance

### Verified remote state

- Repository visibility: **public**.
- Default branch: `main`.
- Baseline SHA: `9488588f0c6fd1984a1c09769af480f85905c661`.
- GitHub reports `main` as **not branch-protected** at this snapshot.

### Local state limitation

The available GitHub connector does not expose a developer local checkout/worktree. This report therefore does **not** claim any local worktree is clean, dirty, ahead, or behind.

The four archaeology documents are isolated on `codex/project-archaeology-2026-08-17` and are not merged by this task.

## Risk register

| Priority | Risk | Status |
|---|---|---|
| High | Live Terranex environment cannot be independently verified | Supabase/Vercel connected accounts expose no Terranex project |
| High | `main` is not branch-protected | Verified GitHub branch metadata |
| Review now | Source repository is public; owner intent unknown | Verified GitHub repository metadata |
| High | Investor economics/capital lifecycle policy is unresolved | `BD-012` OPEN; mutators fail closed |
| Medium | No real-browser E2E gate | No Playwright/Cypress framework/config found |
| Medium | No dedicated automated accessibility gate | Current CI/package config |
| Medium | Account provisioning/recovery flows not found | Repository search/code inspection |
| Medium | Monitoring/backups/rollback unverified in live environment | Live platform project unavailable |
| Medium | README is materially stale | Current implementation exceeds described “first slice” |
| Unknown | Dependency vulnerability state | Baseline CI deliberately skips npm audit |

## Explicit non-claims

This report does **not** claim:

- production is healthy or unhealthy;
- all 30 application routes were exercised in a live browser;
- test coverage is complete;
- WCAG compliance is complete;
- no dead/duplicate code exists;
- no external integration exists outside the repository;
- no secret ever existed in repository history;
- investor economics have been decided;
- a developer local worktree is clean.

No broad repair, migration, deployment, production write, or policy implementation was performed during this archaeology pass.
