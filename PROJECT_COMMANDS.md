# Terranex Project Commands

> Archaeology snapshot: 2026-08-17  
> Verified repository baseline: `main` at `9488588f0c6fd1984a1c09769af480f85905c661`  
> Commands below are taken from current `package.json`, `AGENTS.md`, and CI. No secret values are included.

## 1. Runtime/package manager

**Verified:**

- Package manager: npm (`package-lock.json` committed).
- `package.json` Node engine: `>=20.9.0`.
- Current CI Node: 20.
- Current CI database: PostgreSQL 16.

## 2. Setup/install

Repository setup command in `AGENTS.md`:

```bash
npm install
```

Exact CI install command:

```bash
npm ci --no-audit --no-fund
```

**Baseline CI result:** PASS — 482 packages added.

Important: because CI uses `--no-audit`, the baseline run did **not** produce a verified npm vulnerability count.

## 3. Environment variables

Application variable names represented by current source/configuration:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
NEXT_PUBLIC_SUPABASE_ANON_KEY
```

The app prefers `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` and accepts `NEXT_PUBLIC_SUPABASE_ANON_KEY` as a compatibility fallback. Values are intentionally omitted.

Database test/operator scripts consume PostgreSQL connection values from their execution environment. Never place privileged credentials in docs, commits, or command examples.

## 4. Development server

```bash
npm run dev
```

Equivalent script:

```bash
next dev
```

**Discovery status:** defined by the repository but not started against a live Terranex backend in this pass because the currently connected Supabase account exposes no Terranex project.

## 5. Production build/start

Build:

```bash
npm run build
```

Equivalent:

```bash
next build
```

**Baseline:** PASS. CI resolved Next.js 16.3.0 and compiled **30 Terranex application routes** plus framework `/_not-found`.

Start a built app:

```bash
npm run start
```

Equivalent:

```bash
next start
```

**Discovery status for `start`:** defined but not exercised against a live Terranex backend.

## 6. Application validation

### Lint

```bash
npm run lint
```

Current script:

```bash
eslint
```

**Baseline:** PASS.

### Vitest

```bash
npm test
```

or equivalently:

```bash
npm run test
```

Current script:

```bash
vitest run
```

**Baseline:** PASS — Vitest 3.2.7; 52 test files; 714 tests.

Watch mode:

```bash
npm run test:watch
```

Current script:

```bash
vitest watch
```

### TypeScript

Current CI executes TypeScript directly; there is no `typecheck` npm script:

```bash
npx tsc --noEmit
```

**Baseline:** PASS.

## 7. Database verification

Current npm command:

```bash
npm run db:test
```

Current script:

```bash
bash scripts/db-test.sh
```

**Baseline:** PASS in GitHub Actions with PostgreSQL 16.

The runner applies current migrations in order and executes SQL plus concurrency/replay/upgrade/backup-restore/smoke/isolation checks. Final observed baseline result:

```text
Database migration replay and all SQL/concurrency verification suites passed.
```

### Database shell helper

```bash
npm run db:shell
```

Current script:

```bash
bash scripts/db-shell.sh
```

This is operator tooling, not a baseline CI check.

## 8. R15 admission

Repository command:

```bash
npm run r15:admission
```

Current script:

```bash
node scripts/check-r15-admission.mjs
```

**Discovery status:** command is present but is not part of current `Greenfield CI` and was not independently executed during this archaeology pass. No result is inferred.

## 9. Exact current CI sequence

`.github/workflows/greenfield-ci.yml` triggers on push to `main`, pull requests targeting `main`, and manual dispatch.

Application job:

```bash
npm ci --no-audit --no-fund
npm run lint
npm test
npm run build
npx tsc --noEmit
```

Database job uses PostgreSQL 16 and runs:

```bash
npm run db:test
```

Verified baseline run:

```text
Greenfield CI #454
Run ID: 32030212661
SHA: 9488588f0c6fd1984a1c09769af480f85905c661
Conclusion: success
```

## 10. Full baseline-equivalent validation sequence

With an authorized isolated/test database target available, the current CI-equivalent checks are:

```bash
npm ci --no-audit --no-fund
npm run lint
npm test
npm run build
npx tsc --noEmit
npm run db:test
```

There is no current `validate` npm script.

## 11. Pilot/staging activation

`.github/workflows/pilot-activation.yml` is manual and intentionally conservative:

- inspection-first;
- migration application defaults to false;
- explicit operator selection is required before migrations;
- smoke verification defaults on;
- privileged credentials come from GitHub Actions secrets;
- backup/checksum safeguards exist before explicit migration application.

This archaeology pass did not invoke pilot activation, apply migrations, or write to production.

## 12. Commands defined but not live-runtime verified in this pass

```bash
npm run dev
npm run start
npm run test:watch
npm run db:shell
npm run r15:admission
```

Reason: no identified Terranex Supabase/Vercel live project was available through the currently connected accounts, and discovery must not guess a target environment.

## 13. Safety rule for future write/deploy commands

Before any command that can alter data or deploy:

1. identify the exact target environment;
2. prove it is the intended approved target;
3. preserve existing Git/local work;
4. run read-only/validation checks first;
5. never expose credentials in logs, documentation, commits, or reports.
