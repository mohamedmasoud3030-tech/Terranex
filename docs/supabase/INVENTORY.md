# Terranex — Phase 2A Supabase Inventory (proven from code, not assumed)

**Method:** every entry below is derived from a grep over `src/`, not from documentation.
**Source commit:** `0846378` (`main`, after PR #45 was squash-merged).
**Status:** implemented in `supabase/migrations/` — every item below is covered by
a migration and proven by `scripts/db-test.sh` against a real Postgres.

---

## 1. Tables — the count is **15**, not 13

Proven by every `createSupabaseStore<T>(TABLE, ...)` call site and its table constant.
There are exactly 11 such calls across 9 files.

| # | Table | Entity type | Declared in | Order column |
|---|---|---|---|---|
| 1 | `projects` | `Project` | `features/projects/storage.ts:5` | `created_at` (default) |
| 2 | `partners` | `Partner` | `features/partners/storage.ts:5` | `created_at` (default) |
| 3 | `project_partners` | `ProjectPartner` | `features/partners/storage.ts:6` | **`id`** |
| 4 | `assets` | `Asset` | `features/assets/storage.ts:5` | `created_at` (default) |
| 5 | `documents` | `Document` | `features/documents/storage.ts:6` | `created_at` (default) |
| 6 | `transactions` | `Transaction` | `features/transactions/storage.ts:9` | **`transaction_date`** |
| 7 | `obligations` | `Obligation` | `features/obligations/storage.ts:8` | `created_at` (default) |
| 8 | `settlements` | `Settlement` | `features/settlements/storage.ts:8` | **`settlement_date`** |
| 9 | `settlement_allocations` | `SettlementAllocation` | `features/settlement-allocations/storage.ts:6` | `created_at` (default) |
| 10 | `operational_events` | `OperationalEvent` | `features/events/storage.ts:4` | **`event_date`** |
| 11 | `stock_adjustments` | `StockAdjustment` | `features/events/storage.ts:5` | **`adjustment_date`** |
| 12 | `equity_change_events` | `EquityChangeEvent` | `features/ownership/storage.ts` | `created_at` (default) |
| 13 | `partner_ledger_entries` | `PartnerLedgerEntry` | `features/ownership/storage.ts` | **`posting_date`** |
| 14 | `distributions` | `Distribution` | `features/ownership/storage.ts` | **`distribution_date`** |
| 15 | `distribution_allocations` | `DistributionAllocation` | `features/ownership/storage.ts` | `created_at` (default) |

### Explicitly NOT tables (would be wrong to migrate)

| Candidate | Evidence it is not a DB table |
|---|---|
| `Sector` | No store, no table constant. Static domain union `SectorId`. |
| `ExchangeRate` | `features/settings/ExchangeRateSection.tsx:17` → `localStorage` key `terranex.exchangeRates.v1`. |
| `ProjectProfitability`, `PartnerProfitSplit`, `DashboardKpi`, `AssetBalance` | Computed view models from `profitability.ts`. Never persisted. |
| `DateRange`, `Currency`, `Locale`, `Direction`, `PeriodFilter` | Type aliases / value objects. |

**Every order column must be indexed**, since `hydrate()` issues
`.select('*').order(<col>, { ascending: false })` on every load. Note `project_partners`
orders by `id` — a UUID — which is a correctness smell to flag, not silently "fix", in 2A.

---

## 2. RPCs — the count is **9**

Only one `.rpc(` call site exists in the entire codebase:
`src/core/lib/deletionGuards.ts:14` → `requireClient().rpc(fn, { [param]: id })`.
The ownership-domain RPCs (`change_ownership_atomic`, `record_distribution_atomic`,
`record_partner_ledger_entry_atomic`, `get_ownership_as_of`) are called server-side
via Supabase client RPC.

| # | Function | Parameter | Caller |
|---|---|---|---|
| 1 | `guard_project_deletion` | `p_project_id` | `guardProjectDeletion()` |
| 2 | `guard_partner_deletion` | `p_partner_id` | `guardPartnerDeletion()` |
| 3 | `guard_asset_deletion` | `p_asset_id` | `guardAssetDeletion()` |
| 4 | `guard_document_deletion` | `p_document_id` | `guardDocumentDeletion()` |
| 5 | `guard_transaction_deletion` | `p_transaction_id` | `guardTransactionDeletion()` |
| 6 | `change_ownership_atomic` | `p_request_id, p_project_id, ...` | Ownership RPC boundary |
| 7 | `record_distribution_atomic` | `p_request_id, p_project_id, ...` | Ownership RPC boundary |
| 8 | `record_partner_ledger_entry_atomic` | `p_request_id, p_project_id, ...` | Ownership RPC boundary |
| 9 | `get_ownership_as_of` | `p_project_id, p_as_of_date` | Ownership RPC boundary |

**Return contract** (from `callGuard`): a set-returning function whose first row is
`{ can_delete: boolean, message_ar: text }`. Anything else — error, null, non-array,
empty array — makes the client fall back to `FAILSAFE` (`canDelete: false`).

**Behavioural spec for the SQL:** `tests/helpers/fakeSupabase.cjs` → `RPC_HANDLERS`,
which encodes the exact blocker labels and Arabic message format carried over from the
pre-migration localStorage guards.

### Blocker matrix to reimplement in SQL

| Guard | Blocking relations (label) |
|---|---|
| project | transactions(معاملات), obligations(التزامات), assets(أصول), documents(مستندات), project_partners(شركاء), operational_events(أحداث تشغيلية), stock_adjustments(تسويات مخزون) |
| partner | transactions(معاملات), obligations(التزامات), documents(مستندات), project_partners(مشاريع ملكية) |
| asset | transactions(معاملات), documents(مستندات), operational_events(أحداث تشغيلية), stock_adjustments(تسويات مخزون) |
| document | transactions(معاملات), obligations(التزامات), settlements via `receipt_document_id`(تسويات), operational_events(أحداث تشغيلية) |
| transaction | obligations via `source_transaction_id`(التزامات), operational_events via `linked_transaction_id`(أحداث تشغيلية) |

Message formats (must match exactly):
- allowed: `يمكن حذف {entity} بعد التأكيد. لا توجد روابط تشغيلية تمنع الحذف.`
- blocked: `لا يمكن حذف {entity} لأنه مرتبط بسجلات مالية أو تشغيلية. افصل أو عالج الروابط أولاً: {label: n، label: n}.`

---

## 3. Data-access surface

`grep -rn "\.from(" src/` returns **zero** direct table reads outside the store factory.
All 11 tables are reached only through `createSupabaseStore`, and the only other Supabase
surface is Auth:

- `src/core/auth/AuthProvider.tsx` → `auth.getSession`, `auth.onAuthStateChange`,
  `auth.signInWithPassword`, `auth.signOut`.
- No `supabase.storage` (file bucket) usage — document files live in IndexedDB.

**Implication for RLS:** there is exactly one write path per table, so a single
`owner_id = auth.uid()` policy set per table covers the whole application.

---

## 4. `owner_id` — ownership model (decided, implemented)

No entity in `domain.ts` declares `owner_id` and no store writes one, so the column
default is what populates it.

**Owner decision (2026-07-25), implemented in migrations 0002 / 0004 / 0007:**

- all 11 tables carry `owner_id uuid NOT NULL DEFAULT auth.uid()`
- every table exposes `UNIQUE (id, owner_id)` so composite FKs are possible
- `settlements (obligation_id, owner_id)` → `obligations (id, owner_id)`
- `settlement_allocations (settlement_id, owner_id)` → `settlements (id, owner_id)`
- `settlement_allocations (obligation_id, owner_id)` → `obligations (id, owner_id)`
- **no trigger**, and **no join inside any RLS policy**

The tenant travels inside the foreign key, so a cross-tenant reference is rejected by the
FK itself even if RLS were misconfigured. Settlement ownership needed no derivation: it is
carried explicitly and verified structurally.

RLS policy form on every table:

```sql
USING      ((select auth.uid()) = owner_id)
WITH CHECK ((select auth.uid()) = owner_id)
```

`(select auth.uid())` rather than bare `auth.uid()` so the scalar is evaluated once per
statement instead of once per row.

---

## 5. Notable schema constraints implied by code

- `transactions.document_id` is effectively **UNIQUE** — `referenceValidation.ts` rejects a
  document already used by another transaction. Enforce with a partial unique index.
- `documents.transaction_id` is the reverse link, maintained by
  `transactionDocumentIntegrity.ts`. Both sides must stay consistent.
- `settlement_allocations` — `(settlement_id, obligation_id)` must be **UNIQUE**
  (`storage.ts` `createMany` rejects duplicate pairs).
- `obligations.amount_settled_egp` must never exceed `amount_egp` (enforced in app; belongs
  in a CHECK constraint).
- `project_partners.equity_pct` is 0–100 and must sum to ≤100 per project (documented in
  `domain.ts:126`; app does not currently enforce the sum).
- `settlements.status ∈ {active, reversed}`, `origin ∈ {user, legacy_balance_migration}`.
- All monetary `*_egp` columns should be `numeric`, never float.

---

## 6. Deliverables produced

| File | Purpose |
|---|---|
| `supabase/migrations/…000100_enums_and_helpers.sql` | 17 enum types mirroring `domain.ts` unions |
| `supabase/migrations/…000200_core_tables.sql` | the 11 tables, `owner_id`, composite keys, CHECKs |
| `supabase/migrations/…000300_deferred_fks_and_indexes.sql` | 2 circular FKs + 47 indexes |
| `supabase/migrations/…000400_rls_policies.sql` | RLS enabled + forced, 44 policies (4 × 11) |
| `supabase/migrations/…000500_deletion_guard_rpcs.sql` | the 5 `guard_*_deletion` functions |
| `supabase/migrations/…000600_grants_and_revokes.sql` | REVOKE public/anon, GRANT authenticated |
| `supabase/migrations/…000700_owner_backfill_preflight.sql` | safe backfill + preflight gate |
| `supabase/migrations/…20260801000100_ownership_domain_tables.sql` | 4 ownership tables + enums + indexes |
| `supabase/migrations/…20260801000200_ownership_domain_rls.sql` | RLS policies for ownership tables |
| `supabase/migrations/…20260801000300_ownership_domain_grants.sql` | grants for ownership tables |
| `supabase/migrations/…20260801000400_ownership_domain_rpcs.sql` | atomic ownership RPCs |
| `supabase/migrations/…20260801000500_ownership_data_migration.sql` | non-destructive data migration |
| `supabase/migrations/…20260801000600_fix_p1c_idempotency_ordering.sql` | restore idempotent replay before validation in `record_transaction_atomic` |
| `supabase/rollback/*.down.sql` | one rollback per migration, reversibility documented |
| `supabase/tests/00–04` | shim + 4 behavioural suites against real Postgres |
| `scripts/db-test.sh` | 6-stage runner incl. forward → rollback → reapply |

## 7. Known issues recorded, deliberately NOT fixed in 1A

- **`project_partners` hydrates with `.order('id')`** (`features/partners/storage.ts:21`) —
  a UUID sort, so the order is arbitrary rather than chronological. Changing the client's
  order column is out of scope for 1A; the index matches current behaviour.
- **`equity_pct` must sum to ≤100 per project** (`domain.ts:126`) — a cross-row invariant a
  CHECK cannot express, and the app does not enforce it today. Deferred to P1B.
- **`transaction_category` is `text`, not an enum** — `domain.ts:147` is a long,
  sector-specific and still-evolving union; pinning it would force a migration per new
  category. Validated by Zod client-side.

## 8. What Phase 2A must NOT do

- No atomic financial write RPCs (that is P1B).
- No Supabase-aware backup/restore.
- No UI changes.
- No modification of the production Supabase project; no `execute_sql` against it.
- `tests/helpers/fakeSupabase.cjs` stays a **client-side** test double only. Database
  behaviour must be proven against a real ephemeral Postgres/Supabase in CI.
