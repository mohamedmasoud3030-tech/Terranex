---
name: terranex-database
description: Use when a Terranex task touches PostgreSQL schema, SQL, migrations, RLS, views, functions, indexes, concurrency, database performance, tenant isolation, or financial/reporting data grain. Do not use for TypeScript-only changes with no database contract impact.
---

# Terranex Database

Engineer PostgreSQL changes as database-enforced product invariants, not application conventions.

## Grounding

Before editing:
1. Read AGENTS.md and docs/DB_DEVELOPMENT.md.
2. Read the relevant ADR/domain/finance documents.
3. Inspect the latest migrations that own the same objects.
4. Inspect existing SQL gates for the same invariant.
5. Verify PostgreSQL/Supabase behavior from official current documentation when version-specific.

Do not import Supabase-specific examples blindly. Preserve Terranex's existing auth/RLS model and adapt only the PostgreSQL principle that applies.

## Core rules

- Never edit an applied migration. Add an ordered forward migration.
- Tenant-owned records carry organization_id and tenant isolation is database-enforced.
- Application filtering is not a substitute for RLS.
- Cross-tenant references require database-enforced integrity.
- SECURITY DEFINER code must be treated as a privileged boundary.
- Money uses exact integer/minor-unit or other approved exact representations; never floating point.
- Every financial aggregate must preserve its qualifying grain. Currency, basis, project/portfolio scope, and status cannot be silently collapsed.
- No cross-currency sum without an explicit approved FX contract.
- Posted facts are append-only; corrections follow the approved reversal/repost chain.
- Material command writes are atomic, idempotent, authorized, version-aware, and auditable.
- Add indexes/constraints for real access and integrity paths, not speculative future scale.

Use references/database-checklist.md.

## Workflow

### 1. Define the invariant and grain

State:
- row grain;
- tenant key;
- money/currency grain if present;
- authoritative source tables;
- allowed state transitions;
- authorization boundary.

If the result cannot be described precisely, do not write the view/function yet.

### 2. Search existing ownership

Find:
- current table/view/function/policy;
- existing helper functions;
- existing unique/FK/check constraints;
- existing RLS idiom;
- existing test fixture patterns.

Do not create a second ledger, authorization path, money helper, or overlapping read model unless an ADR explicitly requires it.

### 3. Design the forward migration

Include:
- additive/forward DDL;
- data migration/backfill only when required;
- constraints and indexes;
- RLS/policy changes;
- privileges and function hardening;
- compatibility/recovery notes.

For destructive changes, define the safe transition and recovery path.

### 4. Prove the dangerous path

Add a targeted SQL gate.

When fixing a defect, include a negative control that demonstrates the prior dangerous behavior when feasible.

Database tests should cover applicable:
- two-tenant isolation;
- invalid cross-tenant references;
- idempotency/retry;
- concurrency;
- reversal/repost;
- period lock;
- security-definer exposure;
- currency/grain mixing;
- upgrade/replay.

### 5. Run canonical verification

Use npm run db:test / scripts/db-test.sh. Do not substitute an embedded database as authoritative.

If neither psql nor Docker is available, report the database gate unresolved and rely on the repository CI database job.

### 6. Inspect for cleanup

Remove only obsolete objects/tests/helpers made redundant by this migration when their consumers are migrated in the same bounded slice. Do not leave a competing "temporary" view or policy without a live consumer/recovery reason.

## Exit criteria

The database change is complete when the invariant is database-enforced, migration ordering is safe, tenant isolation and grain are explicit, targeted SQL proof exists, canonical database verification is truthfully reported, and no duplicate database contract remains.
