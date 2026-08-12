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

## Governing allocation basis

S1 deliberately established that **commitment, contribution, ownership, and ledger balances are different concepts**. Therefore S5 never infers profit/loss entitlement from committed or contributed cash.

An S5 rule set is an independent, immutable allocation basis linked to one activated governing agreement version. It stores:

- every eligible investor exactly once,
- positive integer numerator/denominator weights,
- policy (`PRO_RATA` or `FIXED_SHARES`),
- an evidence reference identifying the governing schedule/document from which the weights were transcribed,
- an effective-from date and optional effective-to date,
- a content hash and full audit provenance.

`PRO_RATA` means pro-rata by the independently documented ownership units/percentage basis supplied in the frozen rule set. `FIXED_SHARES` means explicit fixed participant shares. In both policies the numerators must sum exactly to the common denominator. Commitment terms are used only to identify the governing version's eligible investor population; commitment amounts are not weights.

The current S1 slice does not implement a general amendment/supersession command workflow. GF-008 therefore does not guess historical ownership changes. A source period must sit wholly inside the frozen rule basis's effective range; otherwise preparation is rejected. A later governed amendment stage may segment one reporting period across multiple effective agreement/rule versions, but that behavior is not silently invented here.

## Deterministic allocation

Money remains PostgreSQL `bigint` minor units. Allocation uses exact rational arithmetic:

1. compute each investor's exact entitlement,
2. take the integer floor of the absolute amount,
3. calculate each exact remainder,
4. award residual minor units by largest remainder,
5. break equal remainders by stable participant UUID ordering,
6. reapply the source sign for profit or loss.

The database re-computes the canonical allocation at approval. Approval is rejected if any stored participant, weight, floor, remainder, rounding award, sign, currency, or allocated amount differs from the expected deterministic result. A correct total with incorrect investor shares is therefore not approvable.

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

A distribution can only be prepared from an active approved positive allocation for that investor. Approval recomputes authoritative capacity after a project-scoped transaction lock. Payment locks the distribution, recomputes outstanding payable and cash-account balance, and rejects overpayment.

S5 v1 exposes a conservative recorded-liability cash bridge:

`Distributable cash = max(0, Bank cash − positive supplier payables − positive distribution payables)`

Explicit reserve policies, advanced waterfalls, preferred returns, tax withholding, FX allocation, bank execution, and external payment rails remain outside S5 v1 and require later governed stages rather than hidden assumptions.

## Partner-capital statement

The investor statement is derived from active, non-reversed canonical journal facts and exposes separately:

`Closing capital = Opening capital + Contributions + Allocated income − Allocated loss − Approved distributions`

Paid distributions are displayed separately from approved distributions so cash settlement never changes the meaning of the capital rollforward.

## Reversal and correction order

S5 remains append-only and uses the shared journal reversal/correction path. Dependency order is enforced at database level:

- an allocation journal cannot be reversed while an active approved distribution depends on it;
- a distribution-approval journal cannot be reversed while an active payment depends on it;
- payment rows must reference their exact canonical S5 payment journal, active approved payable, participant, currency, project, and cash account.

Downstream effects are reversed first. Read models are reversal-aware and never present a reversed payable as an outstanding liability.

## Security and immutability

All S5 tables are RLS-enabled and forced RLS. Authenticated browser access is read-only. Material commands are `SECURITY DEFINER` with a locked `search_path`, organization membership checks, owner approval where required, deterministic idempotency, advisory/row locking, append-only facts, and audit events.

The proven S2 source-posting concurrency guard is left unchanged. S5 journal sources have their own source-scoped advisory guard so later-stage hardening cannot regress S2 semantics.

## Verification contract

The canonical gate includes:

- PostgreSQL 16 full migration replay,
- S0–S6 regression suites,
- exact S5 allocation-basis provenance, deterministic largest-remainder lines, journals, idempotency, RLS, reversal dependencies, and rollforward verification,
- a real two-session distribution-payment concurrency race,
- S5 forward upgrade from the merged S6 boundary,
- application lint, tests, production build, and typecheck,
- Sonar Quality Gate on the PR head.

The stage is not considered delivered when any required gate on the final head is red or missing.
