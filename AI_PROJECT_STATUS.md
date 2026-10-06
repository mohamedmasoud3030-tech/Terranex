# AI Project Status — Terranex (historical snapshot)

> **⚠️ Superseded — this is not the current status.**
>
> This file records the state of `main` at `59809c7` on **2026-08-18**. It
> predates R14, ADR 0034 (qualified management operating result), the H1
> per-currency contracts, the interface/design-system layer, and the recovery
> merge. Its measurements are preserved as history and have **not** been
> rewritten.
>
> Current verified baseline (2026-10-06, working branch
> `arena/4c002d8d-terranex`, base `main` @ `5156a51`):
> `tsc --noEmit` clean · `eslint .` clean · **76 Vitest files / 1095 tests
> passing** · `npm run build` clean, **37 app routes** · the five design
> generators `--check`-current.
>
> The database suites (`npm run db:test`) still **cannot** be executed here — no
> `psql`, `pg_dump` or `docker` is available in this sandbox — so **no claim in
> this repository about database behaviour is verified by execution**. The DB
> figures below are historical and must not be read as current evidence. The SQL
> statements made in this round are reasoned from `supabase/migrations/*.sql`
> source and are labelled as such in the recovery report.
>
> For present status read `README.md` and `docs/ROADMAP_R0_R17.md`.

**Recorded:** 2026-08-18
**Branch:** `main` (at the time)
**Evidence labels:** VERIFIED COMPLETE · IMPLEMENTED BUT NOT VERIFIED · BLOCKED BY OWNER/EXTERNAL ACTION · NOT STARTED

## Baseline verification (run on this branch, before any change)

| Check | Result | Evidence |
|---|---|---|
| Git state | working tree clean; branch == `main` head `59809c7` | `git status`, `git rev-parse` |
| `npm ci` | PASS | local run |
| `npm run lint` | PASS | local run |
| `npm run typecheck` | PASS | local run |
| `npm test` | PASS — 54 files / 720 tests | local run |
| `npm run build` | PASS — 31 routes | local run |
| `npm audit` (dev+prod, `--audit-level=low`) | PASS — 0 vulnerabilities | local run |
| `npm run db:test` | **PASS — 99 migrations replayed + all 108 SQL/shell suites** on a real PostgreSQL 16.14 server with real psql/pg_dump/pg_restore 16.4 (sandbox-provisioned, `/tmp` only) | local run |
| GitHub CI on `main` | success (run `32052760708`) | `gh run list` |
| Running app (placeholder Supabase env) | `/login` 200 Arabic/RTL; `/`, `/projects`, `/portfolios`, `/assets` → 307 `/login` | local `next start` smoke |

## Previous defects — re-verified closed on this branch

- DEF-001 (CI least-privilege permissions) — closed; `permissions: contents: read` in place; CI green.
- DEF-002 (project-creation name aliasing) — closed; command-aware RPC + payload hash + regression suites pass.
- `/projects` 404 — closed; route exists in the build.
- S6 close-command replay safety — closed; migration + suite 97 pass.
- Unknown-currency decimals guess — closed; `currencyDecimals()` fails closed.

## Milestones — this cycle

**GitHub CI on PR #170** (`arena/01a0112b-terranex`): run `32065958563` — `app` job (install, lint, 60 Vitest files / 745 tests, production build, typecheck) and `database` job (migration replay + suites) both **success**. VERIFIED COMPLETE.

### M1 — Demo showcase seed: policy-safety + R4 payment boundary compatible
Status: **VERIFIED COMPLETE**
- Fixed two real defects found by executing the seed on a fresh schema: (1) policy-gated commands (`attach_contribution_cash`, S5 allocation/distribution) failed because the demo org had no `policy_authority` rows; (2) the legacy direct `pay_cost_obligation` is now a fail-closed tombstone. The seed now activates synthetic demo policy **for the demo org only** and posts its three supplier payments through the production maker/checker surface (`prepare_cost_payment` maker + `approve_cost_payment` OWNER checker). Journal/cash effects identical.
- Evidence: `supabase/tests/zz_demo_seed_replay.sql` runs the real seed twice end-to-end (`DEMO_CREATED`, then `DEMO_ALREADY_EXISTS`) and asserts policy rows exist only for the demo org; `tests/demo-seed-policy.test.ts` pins the contract. Full `npm run db:test` passed locally on real PostgreSQL 16 (109 SQL/shell suites now) and app gates (56 Vitest files / 745 tests, lint, typecheck, build) all green.

### M2 — CI dependency audit
Status: **BLOCKED BY OWNER/EXTERNAL ACTION** — the GitHub App connected to this session lacks the `workflows` permission, so the one-line `npm audit --audit-level=low` step cannot be added to `.github/workflows/greenfield-ci.yml` from here. Local `npm audit` is green (0 vulnerabilities). Recommended action for the owner: add that single line to the `app` job, or authorize a GitHub connection with workflow write access.

### M3 — Intake copy + readiness made sector-honest
Status: **VERIFIED COMPLETE**
- `/intake` start page now describes the three supported sectors (عقارات، زراعة، ثروة حيوانية), links project cards with sector labels, and no longer claims a real-estate-only narrative.
- The project intake readiness now evaluates the Real-Estate property sections (DS11–DS13) only for `REAL_ESTATE` projects; Agriculture/Livestock projects get a link to their sector workspace instead of property forms; the readiness navigation omits sector-inapplicable groups.
- Evidence: `tests/intake-sector-copy.test.ts` + 4 sector-aware cases in `tests/intake-readiness.test.ts`; full app gates green; build contains the updated routes.

### M4 — Active-organization switcher
Status: **VERIFIED COMPLETE** (unit/component level) — browser-level multi-org switching is IMPLEMENTED BUT NOT VERIFIED against the shared pilot Supabase (no credentials used).
- New `terranex_active_org` cookie + pure resolver (`resolveActiveOrganization`: validates against actual memberships, falls back to first org), server context `getActiveOrganization()`, header `<select>` switcher (single-org users see nothing), and the seven top-level org-scoped pages (Home, Projects, Portfolios, Portfolios/new, Assets, Intake, Projects/new) now use the active org. `createOrganization` sets the cookie to the new org.
- Evidence: `tests/active-organization.test.ts` (5), `tests/organization-switcher.test.tsx` (3); full app gates green; runtime build contains the switcher layout.

### M5 — `/login` redirects authenticated users
Status: **VERIFIED COMPLETE** (anonymous path runtime-verified: `/login` 200 with the Arabic form; contract test pins the redirect branch).
- `/login` is now a server wrapper: session → redirect `/`; otherwise renders the unchanged client form (`login-form.tsx`).
- Evidence: `tests/login-redirect.test.ts`; runtime smoke on the production build.

### M6 — Arabic app-level error boundary + `/api/health`
Status: **VERIFIED COMPLETE**
- `src/app/(app)/error.tsx`: Arabic recoverable state, no raw error exposure. `/api/health` returns `200 {"status":"ok"}`, excluded from the session proxy.
- Evidence: runtime smoke `curl /api/health` → 200 without session; security headers intact; `tests/app-error-boundary.test.tsx` + `tests/login-redirect.test.ts` pass; build route table contains `/api/health`.

### M7 — Secure password recovery
Status: **VERIFIED COMPLETE** at code/CI level; **external Supabase redirect configuration and real-email journey are not yet verified**.
- `/login` now links to `/forgot-password`; the request path uses `resetPasswordForEmail` with a controlled recovery callback and account-enumeration-safe success copy.
- `/auth/recovery` exchanges the one-time PKCE code for a cookie-backed session, sets `Cache-Control: private, no-store`, and redirects only to `/reset-password`; invalid/expired callbacks return to the request page.
- `/reset-password` stays private, re-verifies the authenticated user, validates password confirmation, and updates only the current user via `auth.updateUser`.
- Proxy public routes are explicitly limited to `/login`, `/forgot-password`, and `/auth/recovery`; no DB/RLS/finance/R15 behavior changed.
- Evidence: PR #171 merged to `main` as `8c9fd998a78b7d7fbf1f78e2ed8c1d0808bcff8d`; Greenfield CI run `32067782245` on the final PR head passed app gates and PostgreSQL replay/two-tenant isolation. Regression coverage: `tests/password-recovery.test.ts`, `tests/login-redirect.test.ts`, `tests/proxy-auth.test.ts`.

## Deferred items
MFA/sign-up/invites, PWA/offline, notifications, jobs/queues, payment APIs, English locale: **NOT STARTED** (see plan).
R15 investor economics: **BLOCKED BY OWNER/EXTERNAL ACTION** — BD-001…BD-012 OPEN; `r15:admission` exit 1 (correct).

## Honest limits

- No authenticated browser journeys were run against the shared/pilot Supabase project (no credentials used; repo policy forbids unauthorized access). Multi-org switching, login redirect, and password recovery email delivery remain unverified against that external environment.
- The Terranex Supabase project was not available through the connected Supabase account in this execution, so Auth Redirect URLs could not be inspected or changed. A production recovery journey must not be claimed until that external configuration is verified.
- All database verification ran on disposable CI/local PostgreSQL; nothing was written to the pilot project.
- Vercel's connected Terranex project did not expose a deployment for PR #171 or merge SHA `8c9fd998...` during post-merge verification; production deployment and customer UAT are therefore not claimed.
