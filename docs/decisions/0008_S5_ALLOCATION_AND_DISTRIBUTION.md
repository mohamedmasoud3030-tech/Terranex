# ADR 0008 — S5 Allocation & Distribution

**Status:** Implemented · **Date:** 2026-08-12

## Decision

S5 is the investor allocation and distribution layer over the existing S1–S6 investment subledger. It does not create a second ledger and it does not accept authoritative profit, capital, payable, or cash balances from the browser.

A closed S6 period is the **source provenance** for an allocation. A new S5 journal is a new accounting event and therefore must post to a date covered by exactly one `OPEN` accounting period. Reopening/correcting a period never rewrites an earlier allocation source: every run stores the source period, close run, close snapshot, snapshot content hash, snapshot capture timestamp, exact governing agreement version, exact frozen rule set, algorithm version, source category, source amount, actors, timestamps, and content hash.

## Authoritative allocation source

S5 v1 allocates `REALIZED_RESULT` only. The amount is derived inside PostgreSQL from the canonical S2/S4 journal as it existed at `close_run_snapshots.captured_at`, limited to the closed source period and reporting currency:

- recognized real-estate sale revenue,
- less derecognized real-estate cost of sale,
- less posted selling costs.

The application never sends the amount. Later S6 reversal/correction postings therefore cannot silently rewrite the economic input captured by an already prepared allocation.

## Governing rules

Each governing agreement version can have one immutable S5 rule set. Changed economics require a new agreement version and a new rule set; historical rows are not edited.

Supported S5 v1 policies are:

- `PRO_RATA` — database-enforced to equal the exact commitment ratios in the governing agreement by integer cross-product checks.
- `FIXED_SHARES` — owner-specified positive integer weights whose numerators sum exactly to the common denominator.

Every eligible investor in the governing version must appear exactly once. Rule rows use integer numerator/denominator values only.

## Deterministic allocation

Money remains PostgreSQL `bigint` minor units. Allocation uses exact rational arithmetic:

1. compute each investor's exact entitlement,
2. take the integer floor of the absolute amount,
3. calculate each exact remainder,
4. award residual minor units by largest remainder,
5. break equal remainders by stable participant UUID ordering,
6. reapply the source sign for profit or loss.

The database rejects a run unless allocation lines sum exactly to the source amount.

## Journal semantics

S5 extends the locked semantic-account registry with:

- `PROJECT_RESULT_CLEARING`,
- `PARTNER_CAPITAL`,
- `DISTRIBUTION_PAYABLE`.

It extends the existing journal source registry with:

- `S5_ALLOCATION`,
- `S5_DISTRIBUTION_APPROVAL`,
- `S5_DISTRIBUTION_PAYMENT`.

Posting semantics are deliberately separate:

- positive allocation: **Dr Project Result Clearing / Cr Partner Capital** per investor;
- loss allocation: reverse direction;
- distribution approval: **Dr Partner Capital / Cr Distribution Payable**;
- distribution payment: **Dr Distribution Payable / Cr Bank Cash**.

An allocation is not a payment. A distribution request is not an approved payable. An approved payable is not paid cash. These states remain separately auditable.

## Distribution capacity and concurrency

A distribution can only be prepared from an approved positive allocation for that investor. Approval recomputes authoritative capacity after a project-scoped transaction lock. Payment locks the distribution, recomputes outstanding payable and cash-account balance, and rejects overpayment.

S5 v1 exposes a conservative recorded-liability cash bridge:

`Distributable cash = max(0, Bank cash − positive supplier payables − positive distribution payables)`

Explicit reserve policies, advanced waterfalls, preferred returns, tax withholding, FX allocation, bank execution, and external payment rails remain outside S5 v1 and require later governed stages rather than hidden assumptions.

## Partner-capital statement

The investor statement is derived from active, non-reversed canonical journal facts and exposes separately:

`Closing capital = Opening capital + Contributions + Allocated income − Allocated loss − Approved distributions`

Paid distributions are displayed separately from approved distributions so cash settlement never changes the meaning of the capital rollforward.

## Security and immutability

All S5 tables are RLS-enabled and forced RLS. Authenticated browser access is read-only. Material commands are `SECURITY DEFINER` with a locked `search_path`, organization membership checks, owner approval where required, deterministic idempotency, advisory/row locking, append-only facts, and audit events.

The proven S2 source-posting concurrency guard is left unchanged. S5 journal sources have their own source-scoped advisory guard so later-stage hardening cannot regress S2 semantics.

## Verification contract

The canonical gate includes:

- PostgreSQL 16 full migration replay,
- S0–S6 regression suites,
- exact S5 allocation/journal/idempotency/RLS/rollforward verification,
- a real two-session distribution-payment concurrency race,
- S5 forward upgrade from the merged S6 boundary,
- application lint, tests, production build, and typecheck,
- Sonar Quality Gate on the PR head.

The stage is not considered delivered when any required gate on the final head is red or missing.
