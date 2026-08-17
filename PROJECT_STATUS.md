# Terranex Project Status

> Archaeology snapshot: 2026-08-17  
> Verified repository baseline: `main` at `9488588f0c6fd1984a1c09769af480f85905c661`  
> Baseline GitHub Actions run: `Greenfield CI` #454 (`32030212661`) — **success**.

## Executive status

The repository baseline is **build/test green**, but this archaeology pass does **not** establish production readiness.

The strongest verified result is that the current source compiles, all current Vitest tests pass, and the complete PostgreSQL migration/test replay passes in CI. The largest unresolved gap is operational: the currently connected Supabase and Vercel accounts do not expose a Terranex project, so live production behavior and operational controls could not be verified.

## Verification vocabulary

- **PASS** — executed successfully on the exact baseline SHA.
- **OPEN** — intentionally unresolved product/business policy.
- **UNKNOWN** — not verifiable with the repository/current connected accounts.
- **RISK** — a verified condition that deserves follow-up but is not necessarily a current functional failure.
- **CONTRADICTION** — current documentation and executable/current implementation disagree.

## Baseline checks executed by current CI

| Check | Result | Observed baseline |
|---|---|---|
| `npm ci` | PASS with warning | 594 packages installed; 595 audited; npm reported 4 moderate severity vulnerabilities |
| `npm run lint` | PASS | No lint failure |
| `npm run test` | PASS | 52 test files; 714 tests passed |
| `npm run build` | PASS | Next.js production build completed; 29 routes compiled |
| `npm run typecheck` | PASS | TypeScript check completed without failure |
| `npm run test:db` | PASS | Full migration replay and all SQL/concurrency verification suites passed |

No source/test/build failure is present in this baseline CI run.

### Important qualification

The four npm dependency vulnerabilities are a **pre-existing dependency risk**, not a failing CI gate. `npm audit` is not a current required quality gate, so a green workflow does not mean the dependency graph is vulnerability-free.

## Verified working areas

### Repository/build system

- Single npm/Next.js application, not a monorepo.
- Lockfile-based deterministic CI install.
- Lint, unit/component tests, production build, typecheck, and database replay are automated.
- `codex/**`, `main`, pull-request and manual CI entry points are configured.

### Application shell and authentication

- Login action using Supabase Auth.
- Logout action.
- Authenticated-route gating in `src/proxy.ts`.
- Authenticated onboarding for first organization creation.
- Arabic/RTL root layout.
- Organization/project workspace navigation.

### Tenant and database foundation

- Organization membership boundary.
- `OWNER` / `MEMBER` roles and active/inactive membership state.
- RLS and forced RLS on foundation tenant tables.
- Explicit database command/RPC paths for important mutations.
- Audit-event foundation.
- Foreign-key and index controls.

### Business/domain implementation present and migration-replay verified

- Portfolios/projects/intake/terms/funding.
- Costs/cash/revenue/finance foundations.
- Real-estate operations.
- Agriculture operations and lifecycle.
- Livestock operations and lifecycle.
- Procurement/receiving.
- Vendor finance/contracts/credits/payment allocation/advances.
- Budget and approval/exception controls.
- Close/integrity/performance/portfolio roll-up/governance foundations.
- Idempotency/concurrency protections covered by database verification suites.

### Investor-policy safety

- Unapproved ownership/profit/distribution economics are currently fail-closed.
- Current UI does not present economic entitlement as established fact.
- Legacy economic mutation mechanisms are blocked pending approved policy.

### Database verification

The current DB test runner verifies ordered migration replay and runs SQL plus shell/concurrency suites including policy race, close, allocation, lifecycle, opening placement, livestock monetary/operational, portfolio, procurement receiving, vendor payment allocation, data-preservation replay, forward upgrade, backup/restore, backup-failure safety, smoke, and S2 isolation checks.

## Existing failures and incomplete areas

### No baseline command failures

There are no failing lint/test/build/typecheck/database-replay checks on the exact verified SHA.

### Dependency security risk

**RISK:** npm reports **4 moderate severity vulnerabilities** during `npm ci`. They were not investigated or repaired in this discovery-only pass.

### Production runtime not verified

**UNKNOWN:** No Terranex project was visible through the currently connected Supabase or Vercel accounts. Consequently this pass did not verify:

- deployed production URL behavior;
- production database migration level/data state;
- production Auth users/settings;
- live RLS behavior against production data;
- storage buckets/object policies;
- runtime logs/errors;
- monitoring/alerts;
- scheduled backups/retention;
- production restore/rollback behavior.

### Account lifecycle is incomplete as an application flow

**OPEN/INCOMPLETE:** current code contains login/logout/onboarding, but no self-sign-up, password-reset, invitation, or administrator user-provisioning application flow was found. `BD-012` keeps the policy unresolved.

### Investor/economic policy is intentionally incomplete

**OPEN:** business decisions governing investor/economic participation are not approved. The system correctly remains fail-closed rather than inventing ownership/profit rights.

### English/LTR support is unverified

**CONTRADICTION:** repository instructions state Arabic/RTL and English/LTR support, while current root runtime is fixed Arabic/RTL and no i18n mechanism was found.

### Browser E2E coverage

**RISK:** no Playwright/Cypress-style browser E2E framework/configuration is present. Route compilation and component tests do not prove the complete deployed user journeys work in a real browser against a live backend.

### Accessibility coverage

**RISK:** focus/reduced-motion/responsive patterns exist, but there is no dedicated automated accessibility gate. Full WCAG 2.2 AA compliance was not established.

### PWA/offline

**Not implemented by design on this baseline:** no manifest/service worker/offline cache/install/update flow. This aligns with current architecture guidance rather than constituting a discovered regression.

### Operational observability

**UNKNOWN:** no dedicated application observability SDK/configuration was found in the repository, and the live platform project is unavailable for inspection. Production monitoring/alerting therefore cannot be claimed.

## Open business decisions

`docs/OPEN_BUSINESS_DECISIONS.md` currently records **12 OPEN decisions**, `BD-001` through `BD-012`:

1. `BD-001` — investor/economic participation.
2. `BD-002` — ownership/allocation basis.
3. `BD-003` — profit/distribution waterfall.
4. `BD-004` — capital calls/funding states.
5. `BD-005` — tax policy.
6. `BD-006` — base/reporting currency and FX policy.
7. `BD-007` — approval thresholds, segregation of duties, exceptions.
8. `BD-008` — evidence retention/legal hold.
9. `BD-009` — variance policy.
10. `BD-010` — project onboarding gates.
11. `BD-011` — sector-specific accounting policy.
12. `BD-012` — platform policy including account lifecycle, deletion/retention, and payment/AI advisory boundaries.

These are policy unknowns, not implementation facts to be guessed by engineering.

## Documentation contradictions/staleness

| Artifact | Contradiction | Current verified source of truth |
|---|---|---|
| `README.md` | Describes procurement pricing/invoicing/payment as future work | Current migrations/features contain later procurement/vendor-finance/contracts/payment/budget/approval/close/integrity/performance work |
| `AGENTS.md` | Says `npm run db:test` | Current `package.json` command is `npm run test:db` |
| `AGENTS.md` | Says `npm run db:shell` | No npm script exists; `scripts/db-shell.sh` exists |
| `AGENTS.md` | Refers to 13 policy questions | Current `docs/OPEN_BUSINESS_DECISIONS.md` contains 12 IDs |
| `AGENTS.md` | States English/LTR support | Current root runtime is fixed Arabic/RTL; no i18n system found |

## TODOs, dead code, duplication, and legacy behavior

- GitHub indexed code searches returned no `TODO` or `FIXME` hits on this baseline. This is not equivalent to a local raw-file grep and should not be treated as proof that no informal unfinished marker exists.
- No dead-code analysis tool is configured, so dead code absence cannot be claimed.
- Legacy allocation/distribution mechanisms remain represented historically/in code paths, but the current safety layer deliberately blocks unapproved economic mutation. That is **intentional legacy preservation plus fail-close**, not evidence that entitlement is enabled.
- No broad code duplication audit was performed beyond the existing lint/test/CI gates; duplication absence cannot be claimed.

## Git/repository governance state

### Verified remote state

- Default branch: `main`.
- Verified baseline SHA: `9488588f0c6fd1984a1c09769af480f85905c661`.
- GitHub reports `main` as **not branch-protected** at the time of this snapshot.

### Unknown local state

The available GitHub connector reads/writes the remote repository and does not expose a local checkout/worktree. Therefore this archaeology pass does **not** claim that any developer's local working tree is clean, dirty, ahead, or behind.

The discovery documents are intentionally isolated on a documentation-only branch and are not merged by this task.

## Risk register

| Priority | Risk | Evidence/status |
|---|---|---|
| High | Production environment cannot be independently verified | Terranex absent from currently connected Supabase/Vercel accounts |
| High | Core economic/business policy is still open | 12 OPEN business decisions; economic mutators fail closed |
| High | `main` is not branch-protected | GitHub branch metadata |
| Medium | 4 moderate npm dependency vulnerabilities | Observed during baseline `npm ci` |
| Medium | No real-browser E2E quality gate | No browser E2E framework/config found |
| Medium | No dedicated automated accessibility gate | Current CI/package config |
| Medium | Account lifecycle beyond login/logout/onboarding unresolved | Application search + `BD-012` |
| Medium | Production monitoring/backups/rollback unverified | Live platform project unavailable |
| Medium | Current repository documentation contains stale commands/status | Verified contradictions listed above |

## Explicit non-claims

This report does **not** claim:

- that production is healthy or unhealthy;
- that all 29 routes were exercised in a browser;
- that test coverage is complete;
- that WCAG compliance is complete;
- that no dead/duplicate code exists;
- that no external integration exists outside the repository;
- that unapproved investor economics have been decided;
- that a local developer worktree is clean.

No broad repair, migration, deployment, production write, or policy implementation was performed during this archaeology pass.
