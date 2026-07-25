# Terranex — Investment Operating System

## Runtime status

**Last verified: 2026-07-25. Launch status: NO-GO** — see "Launch blockers" below.

Terranex uses the production runtime only. Fresh accounts start empty by design.

**Storage is Supabase (Postgres); Supabase Auth is in use.** The migration away from
localStorage is complete for all domain data. `localStorage` now only holds UI
preferences (locale, theme, exchange rates), plus the legacy migration bookkeeping
described under "Data policy".

## Core runtime

- `src/core/storage/supabaseClient.ts` creates the real Supabase client from
  `VITE_SUPABASE_URL` / `VITE_SUPABASE_PUBLISHABLE_KEY`, with a persisted auth session.
- `src/core/storage/supabaseBootstrap.ts` injects that client into the store registry.
  It must be imported first in `main.tsx`, before any feature `storage.ts`.
- `src/core/storage/supabaseClientRegistry.ts` holds the injected client so no consumer
  imports `import.meta.env` directly — this is what lets the Node test suite inject a fake.
- `src/core/storage/supabaseStore.ts` is the generic store factory: a synchronous in-memory
  cache hydrated from Postgres, kept live over Realtime, with diffed writes back.
- `src/core/auth/AuthProvider.tsx` provides the Supabase Auth session to the app.
- `src/core/storage/localStorageStore.ts` remains only for UI preferences and as the type
  source for the store `Listener` contract. It is no longer a domain data store.
- `src/core/storage/migrations.ts` drains pre-Supabase localStorage data. It does **not**
  write to Supabase; moving that data server-side is Phase 2.
- `src/core/lib/profitability.ts` calculates profitability from transactions and obligations.
- `src/core/lib/deletionGuards.ts` calls the `guard_*_deletion` Supabase RPCs and **fails
  closed** — see "Launch blockers".
- `src/core/lib/referenceValidation.ts` validates transaction references against the
  hydrated Supabase stores, and refuses to validate before hydration completes.
- `src/core/lib/validation.ts` provides runtime validation helpers.

## Store contract

`createSupabaseStore` returns a synchronous reader over an asynchronously hydrated cache.
Callers must respect three rules:

- **Never read before `await store.ready`.** `get()` returns `[]` before hydration, which is
  indistinguishable from a genuinely empty table. `isLoaded()` and
  `getReadsBeforeHydration()` exist to make that window detectable.
- **Writes are optimistic, not confirmed.** `set()` / `update()` apply to the cache
  immediately and persist in the background. `await store.flush()` to get the real result:
  it rejects with the Supabase error if any write failed.
- **A failed write rolls back.** On rejection the store re-hydrates from the server, so the
  cache never shows a row Postgres refused. `getLoadError()` / `getWriteError()` expose the
  last failures.

## Database schema (Phase 1A — complete, not yet deployed)

The Postgres schema is now defined in the repo and reproducible from scratch.

- `supabase/migrations/` — 7 ordered migrations: enum types, the 11 operational tables,
  circular FKs and indexes, RLS, the 5 deletion-guard RPCs, privileges, and the
  `owner_id` backfill with its preflight gate.
- `supabase/rollback/` — one `.down.sql` per migration. Each states plainly what is
  reversible and what is not (`0002` drops tables and is destructive by nature; `0007`
  keeps the assigned `owner_id` values because they cannot be recomputed).
- `supabase/tests/` + `scripts/db-test.sh` — six stages against a real Postgres:
  replay from empty, schema contract, RLS with two identities, deletion-guard RPCs,
  backfill scenarios, and forward → rollback → reapply.

**Ownership model.** Every table carries `owner_id uuid NOT NULL DEFAULT auth.uid()`, and
every table exposes `UNIQUE (id, owner_id)` so financial links can use composite foreign
keys that carry the tenant:

```
settlements            (obligation_id, owner_id) -> obligations (id, owner_id)
settlement_allocations (settlement_id, owner_id) -> settlements (id, owner_id)
settlement_allocations (obligation_id, owner_id) -> obligations (id, owner_id)
```

A cross-tenant reference is therefore impossible at the schema level, independent of RLS.
No trigger is used, and no RLS policy performs a join.

RLS is `enable` + **`force`** on all 11 tables, with four policies each:

```sql
USING      ((select auth.uid()) = owner_id)
WITH CHECK ((select auth.uid()) = owner_id)
```

`WITH CHECK` is what blocks `owner_id` spoofing, on INSERT and on UPDATE in both
directions. `anon` holds no privileges; `authenticated` holds only SELECT/INSERT/UPDATE/
DELETE. Every function pins `search_path = ''`.

The guards are `SECURITY INVOKER` on purpose: their counts run under the caller's RLS, so
a guard can never leak another tenant's row counts through its blocker numbers.

## Launch blockers (still open)

- **The schema is not deployed.** Migrations exist and are proven in CI against an
  ephemeral Postgres, but no production Supabase project has been migrated. Until then
  `deletionGuards.ts` still receives PGRST202 and fails closed, blocking every guarded
  delete with "تعذر التحقق من الروابط التشغيلية".
- **Financial writes are not atomic.** Recording a settlement writes the settlement, then
  the allocations, then the obligation totals as separate round trips. Application-level
  rollback exists, but a crash or network loss mid-sequence leaves inconsistent data.
  This needs a transactional RPC.
- **Backup/restore does not cover Supabase.** `backup.ts` and `archiveBackup.ts` read
  `localStorage`, which no longer holds domain data.

## Main features

- Projects
- Assets
- Partners
- Documents
- Transactions
- Obligations
- Operational events and stock adjustments
- Sector views for real estate, agriculture, and livestock
- Arabic-first RTL interface

## Data policy

The production runtime does not create demo projects, fixture assets, sample transactions, or sample obligations automatically.

Recoverable legacy finance records migrate into the supported ledger stores. Records that cannot be mapped safely remain preserved for audit without invented project or partner links.

## Profitability definitions

- Accounting profit equals income minus expenses.
- Open receivables and open payables are displayed separately.
- Cash exposure equals open receivables minus open payables.

## Testing

The Node suite compiles a subset of `src/` via `tsconfig.test.json` and runs
`tests/*.test.cjs`. It never touches a real Supabase project.

- `tests/helpers/fakeSupabase.cjs` — in-memory fake mirroring the real client's call
  shapes: `from().select().order()`, `insert`, `update().eq()`, `delete().in()`,
  and `client.rpc()` (on the client, not the query builder). It rejects duplicate
  primary keys and unfiltered update/delete the way Postgres does, and can inject
  failures so the fail-closed and rollback paths are testable.
- `tests/helpers/setup.cjs` — must be required **first** by every suite that touches a
  store, because stores hydrate at module load and need the client injected before then.
  Provides `resetWorkspace()`, which truncates the fake DB **and** re-hydrates every store
  so no cached row survives between tests.
- `tests/supabase-store-contract.test.cjs` — regression guards for reads-before-hydration,
  cross-test data bleed, and fake local success on a rejected Supabase write.

## Local verification

```bash
npm ci
npm run typecheck   # 0 errors
npm run lint        # source hygiene
npm run test        # 96 / 96 pass
npm run build       # success
```

All five gates run on every PR via `.github/workflows/quality-gate.yml`, which also runs
each test file in its own process to catch order dependence and leaked state.
