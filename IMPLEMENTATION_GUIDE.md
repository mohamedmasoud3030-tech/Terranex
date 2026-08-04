# Terranex — Investment Operating System

## Runtime status

**Last verified:** 2026-08-04  
**Production application:** [https://terranex.vercel.app](https://terranex.vercel.app)  
**Production revision at verification:** `41b12db824356458216021eadeff483549717499`

Terranex uses Supabase Postgres and Supabase Auth as its production runtime. Domain data no longer uses `localStorage`; browser storage is limited to preferences and legacy migration bookkeeping.

### Current release decision

- Client demo and guided walkthrough: **GO**.
- Live-money operations: **CONDITIONAL NO-GO** until leaked-password protection, tested database recovery, and the real Odoo target are verified.

The authoritative gate record is [`docs/release/LAUNCH_READINESS_2026-08-04.md`](docs/release/LAUNCH_READINESS_2026-08-04.md).

---

## Responsibility split

### Terranex owns

- Projects, assets, sectors, counterparties, documents, and operational events.
- Sales and purchase operational workflows.
- Bank/cash movement context and operational obligations/settlements.
- Inventory items, movements, and stock position.
- Investors, effective-dated ownership, partner capital, partner ledger, and distributions.
- Arabic-first operating UI, audit context, and project analytics.

### Odoo owns

- The official double-entry accounting ledger.
- Egyptian localization and chart of accounts.
- Official customer/vendor accounting, tax, period close, and statutory reports.
- Bank journals and accounting reconciliation.

Terranex financial tables are auditable operational subledgers. Odoo is the accounting source of truth once the bridge is enabled against a verified target.

---

## Core runtime

- `src/core/storage/supabaseClient.ts` creates the browser Supabase client from `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
- `src/core/storage/supabaseBootstrap.ts` registers the client before feature stores load.
- `src/core/storage/supabaseClientRegistry.ts` isolates consumers from environment access and allows controlled test injection.
- `src/core/storage/supabaseStore.ts` provides hydrated, owner-scoped stores over Supabase tables.
- `src/core/auth/AuthProvider.tsx` owns the persisted Supabase session.
- `src/core/lib/profitability.ts` computes operational profitability and cash exposure.
- `src/features/finance/financeWriteBoundary.ts` calls atomic financial RPCs and rehydrates authoritative state after success or failure.
- `src/features/ownership/service.ts` is the typed boundary for ownership, capital, distribution, payment, and reversal lifecycles.
- `src/features/banking/storage.ts` owns bank/cash account reads and reviewed atomic movement RPCs.
- `src/features/invoicing/` owns sales and purchase invoice lifecycles.
- `src/features/finance/journalStorage.ts` owns manual journal creation, posting, and append-only reversal.

---

## Hydrated store contract

`createSupabaseStore` exposes synchronous reads over an asynchronously hydrated cache.

1. Await `store.ready` before treating an empty result as authoritative.
2. Optimistic writes are not confirmed until `await store.flush()` resolves.
3. A rejected write rehydrates from the server so a false local success does not survive.
4. Screens must distinguish loading, load failure, write failure, and genuinely empty data.
5. Financial workflows that span more than one table must not use client-side multi-step writes; they use atomic RPCs.

Diagnostics such as `isLoaded()`, reads-before-hydration counters, and last load/write errors exist to keep these states observable.

---

## Production database

The production Supabase project is deployed and active. At the last verification it contained 45 applied migrations.

The reproducible schema covers:

- projects, assets, partners, documents, transactions, obligations, and settlements;
- operational events and stock adjustments;
- bank accounts and bank transactions;
- sales invoices, lines, and immutable payment records;
- purchase invoices, lines, receipts, and immutable payment records;
- inventory items, movements, and stock views;
- journal entries, journal lines, posting, and reversal operations;
- effective-dated project ownership and equity events;
- partner ledger, capital movements, distributions, and allocation snapshots;
- Odoo outbox, entity mappings, company settings, and worker support tables;
- financial audit and idempotency operation records.

Every operational relationship carries owner scope. RLS is enabled and forced where required, and composite keys prevent cross-owner references independently of UI validation.

---

## Financial write model

Financially material writes are server-side transactions.

### Transactions and settlements

- `record_transaction_atomic`
- `update_transaction_atomic`
- `delete_transaction_atomic`
- `record_settlement_atomic`
- `reverse_settlement_atomic`
- `record_stock_adjustment_atomic`

### Sales

1. `create_sales_invoice_atomic` validates ownership and computes totals on the server.
2. `issue_sales_invoice` moves a draft to issued.
3. `pay_sales_invoice` rejects overpayment, records immutable payment evidence, updates invoice status, posts the bank movement, and queues Odoo work atomically.

### Purchases and inventory

1. `create_purchase_invoice_atomic` validates supplier/project/bank/item ownership and computes totals.
2. `receive_purchase_invoice_with_stock` changes the invoice lifecycle and creates inventory purchase movements in the same transaction.
3. `pay_purchase_invoice` records payment evidence, invoice balance, bank movement, and Odoo event atomically.

### Journals

1. `create_journal_entry_atomic` accepts at least two lines and rejects an unbalanced entry.
2. `post_journal_entry` posts an explicit draft.
3. `void_journal_entry` creates an independent posted reversal and marks the original `reversed`; history is never deleted.

### Ownership and distributions

- Ownership is project-specific and effective-dated.
- A distribution starts as a draft snapshot.
- `approve_distribution_atomic` creates partner entitlements.
- `pay_distribution_allocation_atomic` creates the bank withdrawal and partner-ledger payment atomically.
- `reverse_partner_ledger_entry_atomic` creates opposite bank/ledger rows and reopens the allocation append-only.
- Capital contributions and withdrawals require a selected bank/cash account.
- Draft distributions do not reduce undistributed profit or create partner entitlement.

Every retry-sensitive operation carries a request ID and rejects reuse with different payloads.

---

## Profitability and ownership definitions

- Accounting profit = income − expenses.
- Open receivables and open payables remain separate from accounting profit.
- Cash exposure = open receivables − open payables.
- Distribution payments are equity/partner-liability movements, not operating expenses.
- Partner entitlement for historical transactions uses ownership effective on the transaction date.
- Distribution allocation uses the frozen `ownership_as_of_date`, not current ownership.
- Reversal rows and reversed originals remain visible for audit but have zero active financial effect in balances.

---

## Security boundary

### RLS and ownership

- Anonymous roles hold no operational table privileges.
- Operational rows are owner-scoped and protected by forced RLS.
- RPCs derive or assert the current owner and reject cross-owner references.
- Server functions pin `search_path`.

### Elevated RPCs

PostgreSQL grants must match the exact list in [`docs/security/AUTHENTICATED_SECURITY_DEFINER_ALLOWLIST.md`](docs/security/AUTHENTICATED_SECURITY_DEFINER_ALLOWLIST.md).

At the last production verification:

- anonymous-executable `SECURITY DEFINER` functions: 0;
- externally executable trigger functions: 0;
- authenticated-executable `SECURITY DEFINER` functions: exactly 25 reviewed RPCs;
- internal lock/audit helpers were not executable by authenticated callers.

`supabase/tests/13_authenticated_security_definer_allowlist.sql` reconstructs the schema and fails when that exact boundary changes.

### Remaining Auth control

Supabase leaked-password protection is not yet enabled. This is a live-money blocker, not an application-code defect.

Reference: [Supabase password security](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

---

## Odoo bridge

The browser never receives Odoo credentials.

```text
Terranex browser
  -> Supabase table/RPC transaction
  -> PostgreSQL transactional outbox
  -> Supabase Edge Function
  -> Odoo 18 JSON-RPC
```

Active server functions:

- `odoo-sync` for partners, projects, invoices, payments, bank journals, and manual journal events.
- `odoo-investor-sync` for capital, distribution approval, distribution payment, and reversal events.

Required secrets belong only to the Edge Function environment, including Odoo URL, database, integration user, API key, company/journal identifiers, and reviewed Egyptian control-account codes.

The bridge fails closed when mappings, journals, or account codes are missing or ambiguous. Failed outbox rows remain retryable.

ETA e-invoicing, Odoo-to-Terranex reverse synchronization, and bank-statement reconciliation are not claimed as complete.

---

## Demo data policy

Fresh production accounts start empty by design. A dedicated demo account may contain connected records labelled `ديمو / DEMO` to explain the product.

Demo data must:

- stay isolated to its owner;
- remain visibly marked;
- never be treated as real accounting evidence;
- never be synchronized to a real Odoo production target.

---

## Deployment verification

At the last check:

- Vercel production deployment was `READY` at the documented SHA.
- `https://terranex.vercel.app` returned HTTP 200.
- CSP, HSTS, frame denial, MIME protection, referrer policy, and permissions policy were present.
- No Vercel runtime errors were reported for the previous 24 hours.
- Twenty-seven production read paths succeeded under the real demo owner and RLS.
- Rolled-back production smoke operations proved sales payment, purchase payment, journal post/reversal, and distribution payment/reversal without retaining test rows.

---

## Testing

### Node and UI/source contracts

```bash
npm ci
npm run typecheck
npm run lint
npm run test
npm run build
```

The Quality Gate also runs each test file in an isolated process to catch state bleed.

Key contracts include:

- store hydration and rollback behavior;
- financial arithmetic and idempotency;
- ownership and distribution models;
- responsive workspace/navigation contracts;
- Odoo source and secret hygiene;
- runtime relation/order/RPC schema drift;
- authenticated `SECURITY DEFINER` documentation consistency.

### Real PostgreSQL database gate

```bash
scripts/db-test.sh
```

The 16-stage suite proves:

1. migration replay from empty;
2. exact schema contract;
3. RLS with two identities;
4. deletion guards;
5. owner backfill;
6. P1B atomic finance;
7. ownership domain;
8. invoices, banking, and inventory;
9. purchase and voucher security;
10. Egypt Odoo outbox;
11. Odoo payments/banking;
12. Odoo manual journals;
13. investor lifecycle;
14. authenticated elevated-RPC allowlist;
15. full rollback and reapply;
16. idempotent replay over the existing schema.

CI database tests use ephemeral PostgreSQL. Production smoke checks are deliberate, separately recorded, and rolled back.

---

## Remaining live-money gates

1. Enable leaked-password protection and clear the advisor warning.
2. Enable and prove managed backup/PITR with a restore drill and documented RPO/RTO.
3. Validate the real Odoo Egypt target, unique control accounts, journals, secrets, and end-to-end reconciliation.

Do not replace these operational proofs with unit-test claims.