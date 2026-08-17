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
- Status: Fix implemented; PR verification pending.
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
- Verification method:
  1. Run `Greenfield CI` from a pull request.
  2. Confirm app/database jobs still pass.
  3. Inspect job logs and confirm the `GITHUB_TOKEN Permissions` section no longer grants repository write permissions.

## Unverified areas (not defect entries)

- Authenticated browser journeys cannot be honestly exercised from the current GitHub-only execution environment.
- Pilot/staging activation is intentionally not triggered during this recovery mission because it targets an external Supabase project and can optionally apply migrations.
- Production deployment and production database state are not touched.

## Change log

- 2026-08-17: register created from baseline `fbd63dee8e7d4cdad808986b08e53ba154e3ae66`.
- 2026-08-17: DEF-001 minimal fix implemented on `stabilize/project-recovery-20260817`; verification pending PR CI.
