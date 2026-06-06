# Terranex Agent Workflows

Choose one workflow before editing. Keep each task bounded to one approved stage.

## Repository audit

1. Read `AGENTS.md`, `IMPLEMENTATION_GUIDE.md`, and `docs/ai/data-safety.md`.
2. Inspect the repository with `rg --files` and `rg`.
3. Map active routes, stores, migrations, domain types, tests, documents, and open PRs.
4. Classify findings as blocker, safe cleanup, restore candidate, deferred item, or verified healthy area.
5. Do not add features or delete risky files.

## Safe bug fix

1. Trace the defect from actual code.
2. Identify the smallest root cause.
3. Modify the narrowest safe surface.
4. Add or update a focused regression test.
5. Run targeted checks, then the full release gate.
6. Review the final diff for unrelated changes.

## Domain engine change

1. Confirm the approved roadmap stage.
2. Read the relevant domain, storage, migration, and test files.
3. Preserve traceability, deletion guards, audit history, and local-first behavior.
4. Add business-rule tests for the affected path.
5. Keep each PR limited to one coherent engine increment.

## Storage or migration change

1. Read `src/core/storage/localStorageStore.ts` and `src/core/storage/migrations.ts`.
2. Identify existing stored-record versions and recovery behavior.
3. Keep migrations deterministic and backward-aware.
4. Preserve unmappable legacy records for audit without inventing links.
5. Add tests for migration, restore, and rollback-sensitive behavior.

## External reference study

1. Treat external ERP code as behavioral reference only.
2. Read only the approved reference paths for the current stage.
3. Rebuild useful rules as Terranex-native TypeScript.
4. Do not add external ERP runtime dependencies or commit local reference caches.

## Release check

1. Read `docs/ai/release-policy.md`.
2. Run the full gate.
3. Review affected RTL, responsive, domain, storage, migration, and audit behavior.
4. Return exact results, blockers, changed files, and commit SHA.