# Terranex Project Commands

> Archaeology snapshot: 2026-08-17  
> Verified repository baseline: `main` at `9488588f0c6fd1984a1c09769af480f85905c661`  
> Commands below come from the current repository. No secret values are included.

## 1. Package manager and runtime

### Verified

- Package manager: **npm** (`package-lock.json` is committed).
- CI Node runtime: **Node 20**.
- CI database runtime: **PostgreSQL 15**.

### Important runtime unknown

`package.json` does not declare an `engines.node` version. Node 20 is the version verified in CI; it should not be silently generalized to every deployment runtime until the actual Terranex deployment is inspected.

## 2. Install

```bash
npm ci
```

This is the installation command used by current CI and is preferred for a lockfile-exact verification install.

### Baseline result

**PASS** on the verified baseline SHA.

Observed during CI:

- 594 packages installed.
- 595 packages audited.
- npm reported 4 moderate severity vulnerabilities.

The vulnerability warning is not currently a failing CI gate.

## 3. Environment variables

Application variable names represented by the repository:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
NEXT_PUBLIC_SUPABASE_ANON_KEY
```

The application accepts `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` with `NEXT_PUBLIC_SUPABASE_ANON_KEY` as the compatibility fallback for the public client key.

Do not copy secrets or privileged database credentials into documentation or source control.

For local development, use an ignored local environment file supported by Next.js, for example `.env.local`, populated from the authorized environment/configuration source.

The DB test/operator scripts also consume PostgreSQL connection environment variables or a database URL. Their values are credentials and are intentionally not documented here.

## 4. Development server

Repository command:

```bash
npm run dev
```

Equivalent script:

```bash
next dev
```

**Archaeology status:** repository-defined, but not started in this pass because no verified live Terranex Supabase target was available through the connected account. No browser-runtime claim is based on this command.

## 5. Production build and start

Build:

```bash
npm run build
```

Equivalent script:

```bash
next build
```

**Baseline:** PASS in current CI; 29 application routes compiled.

Start a previously built application:

```bash
npm run start
```

Equivalent script:

```bash
next start
```

**Archaeology status for `start`:** repository-defined, not exercised against a live Terranex backend in this pass.

## 6. Application validation

### Lint

```bash
npm run lint
```

Equivalent:

```bash
eslint .
```

**Baseline:** PASS.

### Unit/component/integration-style Vitest suite

```bash
npm run test
```

Equivalent configured command:

```bash
vitest run --pool=threads --maxWorkers=1 --minWorkers=1
```

**Baseline:** PASS — 52 test files, 714 tests.

Watch mode:

```bash
npm run test:watch
```

### Type checking

```bash
npm run typecheck
```

Equivalent:

```bash
tsc --noEmit
```

**Baseline:** PASS.

### Repository convenience validation

```bash
npm run validate
```

Current definition:

```text
npm run lint && npm run test && npm run build
```

Important: `validate` currently **does not include** `typecheck` or database tests. To reproduce the full current CI quality surface, run them separately.

## 7. Database verification

Current npm command:

```bash
npm run test:db
```

Equivalent script:

```bash
bash scripts/db-test.sh
```

**Baseline:** PASS in GitHub Actions using PostgreSQL 15.

The runner:

1. creates/prepares its isolated test database context;
2. applies all `supabase/migrations/*.sql` in order;
3. runs the SQL verification files;
4. runs database concurrency/race/replay/upgrade/backup/restore/smoke/isolation scripts;
5. fails on migration/test errors.

Final observed baseline message:

```text
Database migration replay and all SQL/concurrency verification suites passed.
```

### DB shell

A repository shell helper exists at:

```bash
bash scripts/db-shell.sh
```

There is **no current `npm run db:shell` script**.

### Documentation correction note

`AGENTS.md` currently mentions `npm run db:test` and `npm run db:shell`. Those names are stale relative to `package.json`.

The current executable sources of truth are:

```bash
npm run test:db
bash scripts/db-shell.sh
```

## 8. R15 admission check

Repository command:

```bash
npm run check:r15
```

Equivalent:

```bash
node scripts/check-r15-admission.mjs
```

**Archaeology status:** command exists in the repository but was not required to establish the baseline lint/test/build/DB status and was not independently exercised in this pass. Its result must not be inferred from general CI success unless it is explicitly run.

## 9. Current CI command sequence

`.github/workflows/greenfield-ci.yml` currently verifies the application with:

```bash
npm ci
npm run lint
npm run test
npm run build
npm run typecheck
```

and verifies the database independently with PostgreSQL 15 using:

```bash
npm run test:db
```

At the archaeology baseline SHA, `Greenfield CI` run #454 (`32030212661`) completed successfully.

## 10. Pilot/staging activation

`.github/workflows/pilot-activation.yml` is a **manual** workflow. Its safe defaults matter:

- inspection-first;
- `apply_migrations` defaults to false;
- smoke verification defaults on;
- database changes require explicit operator selection;
- secrets are read from GitHub Actions secrets rather than committed as privileged values.

Do not treat the pilot workflow as an instruction to modify production during normal development/discovery.

This archaeology pass did not trigger pilot activation or any production migration.

## 11. Recommended exact local/full validation sequence

When a correctly configured isolated development/test database is available, the current repository's full baseline-equivalent verification is:

```bash
npm ci
npm run lint
npm run test
npm run build
npm run typecheck
npm run test:db
```

This sequence mirrors the actual current CI surface more accurately than `npm run validate` alone.

## 12. Commands not verified against live Terranex in this pass

The following are valid repository commands/scripts, but their live-runtime behavior was not asserted here:

```bash
npm run dev
npm run start
npm run test:watch
npm run check:r15
bash scripts/db-shell.sh
```

Reason: the currently connected Supabase/Vercel accounts do not expose a Terranex deployment/project, and discovery must not guess or write to an unidentified environment.

## 13. Safe-command rule

Before any future command that can write data or deploy:

1. identify the target environment explicitly;
2. prove it is the intended non-production or approved target;
3. preserve existing Git/local work;
4. use read-only/validation commands first;
5. never expose credentials in logs, documentation, commits, or reports.
