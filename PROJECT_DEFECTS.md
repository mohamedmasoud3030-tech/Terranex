# Project Defect Register

This register contains confirmed defects only. Unverified areas are listed separately and are not defects until evidence confirms them.

## Baseline — 2026-08-17

- Source branch: `main`
- Baseline SHA: `fbd63dee8e7d4cdad808986b08e53ba154e3ae66`
- GitHub Actions run: `32037852218` (`Greenfield CI`)
- Baseline result: `success`
- App job: install, lint, 53 Vitest files / 718 tests, production build, and typecheck all passed.
- Database job: PostgreSQL migration replay, migration-history immutability check, and two-tenant isolation passed.
- Sonar job: passed.
- Local working-tree/runtime verification: unavailable from the GitHub connector; no claim is made about an uncommitted local worktree.

## Confirmed defects

### DEF-001 — Greenfield CI receives unnecessary repository write permissions

- Severity: High (security / CI supply-chain hardening)
- Status: Closed on recovery branch; pending owner-authorized merge.
- User-visible symptom: none expected during normal use; compromise or malicious execution inside the workflow would have had a larger repository mutation blast radius than required.
- Evidence / reproduction:
  - `.github/workflows/greenfield-ci.yml` on the baseline SHA had no explicit top-level `permissions` block.
  - Baseline job logs for app job `95411706938` reported broad `GITHUB_TOKEN` write permissions, including `Contents`, `Issues`, `PullRequests`, and `Deployments`.
  - The workflow itself only checks out source and runs install/lint/tests/build/typecheck/database checks; it performs no GitHub repository write operation.
  - `.github/workflows/pilot-activation.yml` already uses `permissions: contents: read` and is not affected.
- Affected scope: GitHub Actions executions of `Greenfield CI`.
- Confirmed root cause: missing explicit least-privilege `permissions` declaration in `.github/workflows/greenfield-ci.yml`.
- Regression area: checkout and CI execution on pull requests / `main` pushes.
- Smallest safe fix: add top-level `permissions: contents: read` without changing jobs, commands, triggers, application code, database code, secrets, or deployment behavior.
- Verification observed:
  - Pull-request run `32041349679` completed successfully.
  - `app` job `95421096203` passed install, lint, all 53 Vitest files / 718 tests, production build, and typecheck.
  - `database` job `95421096081` passed PostgreSQL replay and two-tenant isolation.
  - The repaired app-job log reports only `Contents: read` and `Metadata: read` under `GITHUB_TOKEN Permissions`; the previous repository write grants are absent.
  - The original over-privileged behavior therefore no longer reproduces in the affected workflow.

### DEF-002 — Project creation aliases distinct commands by project name

- Severity: High (data integrity / project identity)
- Status: Closed on recovery branch; pending owner-authorized merge.
- User-visible symptom: creating a project with the same organization, sector, and normalized name as an existing project can return and open the older project even when the new internal reference or description is different.
- Evidence / reproduction:
  - `src/app/(app)/projects/new/project-form.tsx` on the baseline has no command idempotency key.
  - `src/features/projects/actions.ts` calls the 5-argument `create_investment_project` RPC without a command key.
  - The latest baseline definition in `20260814001700_livestock_foundation.sql` locks and searches by organization + sector + normalized name, then returns the first matching row without comparing internal reference or description.
  - `investment_projects` has no uniqueness invariant making name + sector the project identity; distinct same-name projects are structurally allowed.
  - Existing sector-aware tests do not cover changed payloads sharing a project name.
- Affected scope: `/projects/new`, direct authenticated callers of project-creation compatibility RPCs, project identity, and downstream navigation after creation.
- Confirmed root cause: descriptive project metadata was incorrectly reused as implicit idempotency identity instead of an explicit logical-command key with payload binding.
- Regression area: project creation, legacy 2/3/4/5-argument compatibility, sector routing, tenant authorization, audit-event cardinality, and retry behavior.
- Smallest safe fix:
  - Add nullable creation command key/hash columns for backward-compatible existing rows plus an organization-scoped unique command-key index.
  - Add a 6-argument command-aware RPC that binds each key to a SHA-256 request hash and rejects payload mismatch.
  - Keep the legacy 5-argument RPC but derive a deterministic key from its full payload so changed payloads no longer alias by name; the historical Real-Estate wrapper continues to delegate through it.
  - Pass a server-generated nonce through the existing shared `commandIdempotencyKey` lifecycle in `/projects/new`.
- Verification observed:
  - Greenfield CI run `32051550041` passed the application gate: install, lint, all 54 Vitest files / 720 tests, production build, and typecheck.
  - Greenfield CI run `32051820262` re-ran the final documentation-only head and passed both the complete application gate and PostgreSQL migration replay/two-tenant isolation.
  - Greenfield CI run `32052125263` re-ran the final branch head after the defect register update and passed both application and database jobs.
  - SQL regression coverage confirms exact-key replay returns one project with one audit event; changed payload with the same key is rejected; a fresh key may create a distinct same-name project; legacy exact payload replay remains compatible; changed legacy payload no longer aliases; cross-tenant creation is rejected.
  - Form regression coverage confirms a failed retry preserves the same command key.
  - Historical GF-013 forward-upgrade verification was corrected to use its actual chronological migration boundary, preventing later recovery migrations from contaminating a pre-GF-013 fixture.
  - The original same-name command-alias behavior therefore no longer reproduces under the command-aware creation contract.

## Unverified areas (not defect entries)

- Authenticated browser journeys cannot be honestly exercised from the current GitHub-only execution environment.
- Pilot/staging activation is intentionally not triggered during this recovery mission because it targets an external Supabase project and can optionally apply migrations.
- Production deployment and production database state are not touched.
- Dependabot alerts are disabled for this repository; code-scanning alerts are not accessible to the current GitHub integration; secret-scanning alert retrieval returned an upstream error. These are coverage limits, not confirmed application defects.

## Change log

- 2026-08-17: register created from baseline `fbd63dee8e7d4cdad808986b08e53ba154e3ae66`.
- 2026-08-17: DEF-001 minimal fix implemented on `stabilize/project-recovery-20260817`.
- 2026-08-17: DEF-001 closed after PR run `32041349679` passed and job logs confirmed least-privilege token scope.
- 2026-08-17: DEF-002 confirmed from the current form/action/schema and latest project-creation RPC; minimal command-identity fix implemented with regression coverage.
- 2026-08-17: DEF-002 closed after Greenfield CI run `32051550041` passed app and PostgreSQL gates with 720/720 tests and the dedicated project-creation regression suite; final branch head re-verified in run `32052125263`.
