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

## Launch blockers (Phase 2 scope — not addressed in this branch)

- **No versioned Supabase migrations.** The Postgres schema is not defined in the repo.
  There is no reproducible way to stand up a new environment.
- **No RLS policies and no `guard_*_deletion` RPCs deployed.** `deletionGuards.ts` calls
  them and fails closed, so in production every guarded delete is currently blocked with
  "تعذر التحقق من الروابط التشغيلية". The tests exercise the intended behaviour against a
  fake — that proves the client contract, never the server.
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
