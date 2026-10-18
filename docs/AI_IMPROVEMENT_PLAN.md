# AI Improvement Plan — Terranex (2026-08-18)

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

### M3 — Intake copy made sector-honest (AD-05) ✅ VERIFIED COMPLETE
- **Outcome:** `/intake` describes the three supported sectors accurately; project cards link to the correct sector landing page.
- **Verification:** characterization tests, lint/typecheck/build, and PR CI passed.

### M4 — Active-organization switcher (AD-04) ✅ VERIFIED COMPLETE (code/CI)
- **Outcome:** multi-org users choose which organization they operate on from the app header; all top-level org-scoped pages respect the choice; single-org users see no change.
- **Fix:** `terranex_active_org` cookie + validated server helper + header `<select>` switcher; Home, `/projects`, `/portfolios`, `/portfolios/new`, `/assets`, `/intake`, `/projects/new`; `create_organization` sets the cookie to the new org.
- **Regression:** resolver/component coverage passes. External multi-org browser journey remains to be verified against the pilot Supabase.

## Priority 3 — auth / UX / accessibility barriers

### M5 — `/login` redirects authenticated users (AD-06) ✅ VERIFIED COMPLETE
- **Outcome:** signed-in users visiting `/login` land on the dashboard; anonymous flow unchanged.
- **Verification:** contract coverage + production-build anonymous smoke.

### M6 — Arabic app-level error boundary + health endpoint (AD-07) ✅ VERIFIED COMPLETE
- **Outcome:** unhandled errors inside the app shell show an Arabic recoverable state; `/api/health` answers `200 { status: 'ok' }` for deployment smoke.
- **Verification:** build route table, curl smoke, tests.

### M7 — Secure password recovery ✅ VERIFIED COMPLETE (code/CI)
- **Outcome:** a user can request a recovery email without exposing whether an account exists, exchange the Supabase PKCE recovery code for a session, and set a new password only from the verified recovery session.
- **Fix:** `/forgot-password`, `/auth/recovery`, protected `/reset-password`, controlled callback destination, `private, no-store` callback redirects, and explicit proxy allowlist for only the recovery entry routes.
- **Regression:** `tests/password-recovery.test.ts`, `tests/login-redirect.test.ts`, `tests/proxy-auth.test.ts`; Greenfield CI run `32067782245` passed app and database jobs before merge in PR #171.
- **External acceptance still required:** verify the Terranex Supabase Auth Redirect URL configuration and execute a real recovery email journey. This connected session did not expose the Terranex Supabase project, so that environment-level step was not performed.

## Priority 4 — deferred / not scheduled (kept visible)

- MFA / public sign-up / invitations — pilot provisioning is documented; owner decision on identity features comes with pilot feedback. NOT STARTED.
- PWA/offline/install — post-pilot. NOT STARTED.
- Email/SMS notifications, jobs/queues, payment/bank APIs — only when a real workflow proves the need. NOT STARTED.
- English/LTR locale — current product is Arabic-first by design. NOT STARTED.
- R15 investor economics — BLOCKED BY OWNER/EXTERNAL ACTION (BD-001…BD-012).
- Historical wrapper cleanup (`command-actions.ts`), doc consolidation — low-value debt; do not churn before pilot. NOT STARTED.

## Recommended sequence and why

M1–M7 are now implemented at code/CI level except M2, which remains externally blocked by GitHub workflow-write permission. The next engineering work should not expand R15 or speculative platform features. First close the two environment-level pilot checks: (1) verify the Terranex Supabase recovery redirect + real recovery email journey, and (2) verify a multi-organization browser switch against the pilot environment. Then use actual pilot feedback to decide whether MFA/invitations or PWA/offline deserves the next milestone. R15 remains fail-closed until BD-001…BD-012 are decided.
