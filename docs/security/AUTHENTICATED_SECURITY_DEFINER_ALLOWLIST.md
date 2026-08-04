# Authenticated `SECURITY DEFINER` Allowlist

**Last verified:** 2026-08-04  
**Production project:** `nwpyeobuxzbdnnzyfyqw`

Supabase Security Advisor warns whenever `authenticated` can execute a `SECURITY DEFINER` function. In Terranex, this is intentional only for the reviewed business RPC boundary below. The warning is not permission to add more functions implicitly.

## Required invariants

Every allowlisted function must:

- deny `PUBLIC` and `anon` execution;
- pin `search_path` explicitly;
- derive or validate the current owner and reject cross-owner references;
- keep financially material writes atomic and idempotent where applicable;
- write append-only audit evidence for financial lifecycle operations;
- remain covered by PostgreSQL and source-contract tests.

Trigger functions, locking helpers, audit helpers, worker claim/complete/fail functions, and other implementation details must not be directly executable by `authenticated`.

## Exact allowlist

### Ownership, capital, and distributions

- `approve_distribution_atomic`
- `change_ownership_atomic`
- `get_ownership_as_of`
- `pay_distribution_allocation_atomic`
- `record_distribution_atomic`
- `record_partner_capital_movement_atomic`
- `record_partner_ledger_entry_atomic`
- `reverse_partner_ledger_entry_atomic`

### Sales, purchases, banking, and journals

- `create_journal_entry_atomic`
- `create_purchase_invoice_atomic`
- `create_sales_invoice_atomic`
- `pay_purchase_invoice`
- `pay_sales_invoice`
- `post_journal_entry`
- `receive_purchase_invoice_with_stock`
- `set_bank_transaction_reviewed`
- `void_journal_entry`

### Transactions, settlements, and stock

- `delete_transaction_atomic`
- `record_settlement_atomic`
- `record_stock_adjustment_atomic`
- `record_transaction_atomic`
- `reverse_settlement_atomic`
- `update_transaction_atomic`

### Support boundary

- `terranex_assert_owner` — fail-closed owner assertion required by reviewed `SECURITY INVOKER` and `SECURITY DEFINER` RPCs; denied to anonymous roles.
- `enqueue_odoo_sync` — explicit user-requested resync; resolves the entity owner and rejects records not owned by `auth.uid()` before queueing.

## Explicitly forbidden from the allowlist

- `terranex_lock_financial_request`
- `terranex_audit_check_idempotent`
- `terranex_audit_log`
- every function returning `trigger`
- Odoo worker claim, complete, and fail helpers

## Change control

A pull request that adds or changes an authenticated-executable `SECURITY DEFINER` function must include all of the following:

1. An update to this exact allowlist and the reason the browser needs the elevated RPC.
2. Anonymous-deny and authenticated-allow privilege tests.
3. Two-owner isolation and ownership-spoofing tests.
4. Idempotency and append-only reversal tests for financial writes.
5. A production migration and a rollback that never reopens anonymous execution.

The CI contract fails when the reviewed list changes without an explicit update.