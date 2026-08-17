# AI Improvement Plan — Terranex (2026-08-17)

Deduplicated, prioritized milestones. Recommended sequence below; each milestone defines the outcome, acceptance criteria, and verification. Status is maintained in `AI_PROJECT_STATUS.md`.

## Priority 1 — data integrity, security, outage risks

### M1 — Demo showcase seed: policy-safety compatible (AD-03) ✅ VERIFIED COMPLETE
- **Outcome:** the permanent Real Estate showcase can be seeded and re-seeded on a fresh current-schema database; real-org policy boundaries remain untouched.
- **Fix:** activate the two demo policy scopes inside the seed for the demo org only (synthetic labels); no migration changes. Additionally repaired the R4 payment-boundary break (legacy `pay_cost_obligation` is a tombstone) by routing the seed's three supplier payments through `prepare_cost_payment` (maker) + `approve_cost_payment` (OWNER checker).
- **Regression:** new DB suite `supabase/tests/zz_demo_seed_replay.sql` (runs the real seed end-to-end on the disposable database: fresh run = `DEMO_CREATED`, second run = `DEMO_ALREADY_EXISTS`, policy rows exist only for the demo org, pre-existing test-tenant rows unaffected) + Vitest contract test `tests/demo-seed-policy.test.ts`.
- **Verification:** local `npm run db:test` PASS on real PostgreSQL 16 (109 suites) + `npm test` (745), lint, typecheck, build — all PASS.

### M2 — CI dependency audit (AD-08) ⛔ BLOCKED BY OWNER/EXTERNAL ACTION
- **Outcome:** dependency vulnerabilities fail CI before merge.
- **Fix:** one line — `npm audit --audit-level=low` in the `app` job of `greenfield-ci.yml`. The GitHub App connected to this session lacks the `workflows` permission, so the push was refused; the file was left untouched.
- **Verification:** local `npm audit` green (0 vulnerabilities). Owner action: add the line, or reconnect GitHub with workflow write access.

## Priority 2 — business logic / core user outcomes

### M3 — Intake copy made sector-honest (AD-05)
- **Outcome:** `/intake` describes the three supported sectors accurately; project cards link to the correct sector landing page.
- **Verification:** page renders in the running app (smoke), lint/typecheck/build, Vitest coverage of the copy change via an existing/added characterization test.

### M4 — Active-organization switcher (AD-04)
- **Outcome:** multi-org users choose which organization they operate on from the app header; all top-level org-scoped pages respect the choice; single-org users see no change.
- **Fix:** `terranex_active_org` cookie + validated server helper + header `<select>` switcher; update Home, `/projects`, `/portfolios`, `/portfolios/new`, `/assets`, `/intake`, `/projects/new`; `create_organization` sets the cookie to the new org.
- **Regression:** unit tests for the resolver (pure function), a component test for the switcher (cookie set + refresh), and form tests confirming the active org flows into portfolio/project creation.
- **Verification:** `npm test`, lint, typecheck, build, running-app smoke.

## Priority 3 — auth / UX / accessibility barriers

### M5 — `/login` redirects authenticated users (AD-06)
- **Outcome:** signed-in users visiting `/login` land on the dashboard; anonymous flow unchanged.
- **Regression:** component/server-wrapper test where possible; existing auth tests keep passing.
- **Verification:** running-app smoke (anonymous 200, redirect logic unit-tested).

### M6 — Arabic app-level error boundary + health endpoint (AD-07)
- **Outcome:** unhandled errors inside the app shell show an Arabic recoverable state; `/api/health` answers `200 { status: 'ok' }` for deployment smoke.
- **Verification:** build route table contains `/api/health`; curl smoke; `npm test`.

## Priority 4 — deferred / not scheduled (kept visible)

- Password reset / MFA / public sign-up / invitations — pilot provisioning is documented; owner decision on identity features comes with pilot feedback. NOT STARTED.
- PWA/offline/install — post-pilot. NOT STARTED.
- Email/SMS notifications, jobs/queues, payment/bank APIs — only when a real workflow proves the need. NOT STARTED.
- English/LTR locale — current product is Arabic-first by design. NOT STARTED.
- R15 investor economics — BLOCKED BY OWNER/EXTERNAL ACTION (BD-001…BD-012).
- Historical wrapper cleanup (`command-actions.ts`), doc consolidation — low-value debt; do not churn before pilot. NOT STARTED.

## Recommended sequence and why

M1 first: it restores the product's primary demo/presentation vehicle and its failure mode (broken seed on fresh schema) is the only confirmed P1 left. M2 is a one-line CI hardening. M3–M4 then fix the two highest-impact user-facing correctness gaps (misleading copy, wrong-org data entry). M5–M6 are small UX/ops polish that complete the "finished product" experience for the pilot. Everything is safe, reversible, and verified against the existing gates without touching the shared Supabase project or production.
