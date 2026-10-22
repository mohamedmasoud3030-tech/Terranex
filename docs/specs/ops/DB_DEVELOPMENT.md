# Terranex Database Development Access

This repository must be able to verify database changes without depending on a shared Supabase environment or committed credentials.

## Required commands

Run the complete database gate with:

```bash
bash ./scripts/db-test.sh
```

The runner uses an existing `psql` client when available. If `psql` is unavailable but Docker exists, it automatically starts an isolated PostgreSQL 16 container, replays every migration, then executes every SQL test in `supabase/tests/` except the bootstrap shim.

A missing local PostgreSQL client is therefore not a reason to skip database verification.

If neither `psql` nor Docker exists, the command fails with a non-zero exit status. The database gate remains unresolved until it is executed in another capable environment or CI. Never mark it passed, simulated, or skipped.

## Interactive database shell

Use:

```bash
bash ./scripts/db-shell.sh
```

or provide a database name:

```bash
bash ./scripts/db-shell.sh terranex_test
```

The shell uses the same local-first / Docker-fallback strategy. The Docker shell container is named `terranex-db-shell` and is intentionally local and disposable.

## Local defaults

For local disposable PostgreSQL only:

```text
PGUSER=postgres
PGPASSWORD=postgres
PGHOST=127.0.0.1
PGPORT=5432
```

These are development defaults, not production credentials.

## Shared / production Supabase

Do not commit database passwords, service-role keys, access tokens, connection strings, or production secrets to this repository. Application runtime uses only the public Supabase URL and publishable key from environment variables; privileged database administration is outside browser/application code.

GF development and verification should use disposable PostgreSQL and CI. Applying migrations to any shared, staging, demo, or production Supabase project requires explicit environment authorization and credentials supplied through that environment's secret mechanism, never repository files.

## Test discovery contract

- migrations: every `supabase/migrations/*.sql`, in lexical order;
- bootstrap shim: `supabase/tests/00_supabase_shim.sql`;
- verification suites: every other `supabase/tests/*.sql`, in lexical order.

New GF slices must add their database assertions under `supabase/tests/`; `scripts/db-test.sh` discovers them automatically. Do not hard-code a new test into CI while omitting it from the local database gate.
