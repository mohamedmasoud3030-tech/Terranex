# ADR 0004 — S2 Cost & Cash shape

**Status:** Accepted for GF-004
**Date:** 2026-08-11

## Context

S2 proves the smallest Real Estate cost-and-cash workflow: record a supplier
cost obligation, authorize it through the current membership model, pay it
from a project cash/bank account, import the matching bank-statement fact,
reconcile them one-to-one, and show exact book/cost/cash status with an audit
trail. This introduces Terranex's first balanced project subledger. The
finance contract (05_FINANCE_AND_ACCOUNTING.md) requires balanced immutable
postings, database-enforced invariants, exact money, tenant-safe references,
and reversal-based correction.

## Decision

- **Project cash accounts** are tenant- and project-scoped rows whose balance
  is never stored: `project_cash_position_read` derives it from journal
  lines. Account currency must equal the project reporting currency; S2 is
  single-currency by construction (FX is deferred).
- **Book cash from S1 contributions** uses a controlled attribution command
  (`attach_contribution_cash`) that posts `Debit Bank/Project Cash / Credit
  Contributed Capital` and links the contribution. A contribution posts at
  most once while its posting is active; after an explicit linked reversal it
  may be posted again. No free-form opening-balance shortcut exists.
- **Suppliers reuse the S1 `parties` table.** An obligation references a
  party as its counterparty; no second supplier identity system and no
  generic party-role framework are introduced.
- **Cost obligations** are drafts prepared by any active member with an
  explicit `cost_treatment` (`EXPENSE` or `CAPITALIZABLE_WIP` — never
  guessed). Drafts may be updated/deleted; authorization is OWNER-only and
  atomically posts the balanced batch:
  - `EXPENSE`: Debit Project Expense / Credit Supplier Payable;
  - `CAPITALIZABLE_WIP`: Debit Development WIP / Credit Supplier Payable.
- **Authorization boundary** is the smallest real one in the current model:
  active members prepare drafts and import statements; the organization
  OWNER authorizes obligations, posts payments, reconciles, voids
  reconciliations, and reverses batches. Actors and timestamps are recorded
  on rows and in `audit_events`; approval is never a UI-only flag.
- **Subledger**: `journal_batches` + `journal_lines` under five locked
  semantic account roles (`semantic_accounts` table, immutable for every
  writer). Batches carry organization, project, source type/id, transaction
  date, actor, idempotency key + request hash, and reversal link. Lines carry
  account role, debit/credit minor units, currency, cash account / obligation
  / party dimensions, and dates. The database enforces balance (debits =
  credits, ≥1 debit and ≥1 credit line, one currency, lines in the batch
  project) via a statement-level trigger on `journal_lines`, and immutability
  via update/delete guards — no posted batch can exist unbalanced even from
  privileged writers.
- **Payments** are OWNER-only, append-only, bound to one obligation, one cash
  account, one currency, and one project. The obligation row is locked
  (`FOR UPDATE`) before the paid total is computed — the serialization
  boundary for concurrent payments. Retries are payload-bound idempotent
  (same key + same payload returns the original payment; same key + different
  payload is rejected). Posting: Debit Supplier Payable / Credit Bank Cash.
- **Bank statement import** uses a deterministic CSV contract
  (`date,amount,currency,description,provider_reference`) with signed decimal
  amounts (negative = money out). Fingerprints are server-computed SHA-256
  over account/date/amount/currency/description/reference; duplicate
  fingerprints are rejected by a unique index. Import is idempotent per
  command key and creates statement lines only — never journal economics.
- **Reconciliation** is exact one-to-one (one payment ↔ one statement line),
  OWNER-only, with no journal effect. Matching requires the same project cash
  account, same currency, and amount/sign semantics
  (`statement = -payment`). Active matches are unique per payment and per
  line; the only correction is a controlled, audited, idempotent void
  (`void_reconciliation`) that never touches economics.
- **Reversal** (`reverse_journal_batch`) is the only correction for posted
  facts: it creates an exact inverse batch linked to the original, leaves the
  original immutable, and rejects invalid order — an obligation with active
  payments cannot be reversed, a payment with an active reconciliation cannot
  be reversed, and a reversal cannot itself be reversed. Reversals are
  idempotent and audited. Period close/reopen is deferred to the Close &
  Correction slice.
- **Money** has one canonical implementation in `src/shared/money`
  (promoted from S1; S1 and S2 are its two consumers). PostgreSQL bigint
  storage, exact decimal-text parsing (including signed amounts), text
  transport through `*_read` views, no JavaScript floating-point financial
  arithmetic, explicit currency, int64 range protection.
- **Database access** remains the canonical `npm run db:test` gate: fresh
  replay S0→S1→S2 plus the SQL behavioral suite and a real two-session
  concurrency suite (payments racing an obligation ceiling, duplicate posting
  with one idempotency key, duplicate statement fingerprint, reconciliation
  racing one statement line).
- **UI** stays project-centered and Arabic/RTL-first with two shallow
  surfaces: `/projects/[id]/costs` and `/projects/[id]/cash`. Every number
  drills to its journal source; loading/empty/error/forbidden states are
  truthful; tables wrap for mobile.

## Verification contract

GF-004 is not complete from unit tests alone. The database gate must prove:
fresh S0→S1→S2 replay; two-organization isolation; same-tenant cross-project
reference rejection; MEMBER vs OWNER authorization boundary; browser
financial DML denial; exact balanced postings for expense, WIP, payment, and
attribution; unbalanced/partial/mixed-currency batch rejection by the
database; posted batch/line immutability; exact derived balances from journal
lines; partial payments and exact outstanding; overpayment rejection; real
concurrent overpayment protection; idempotent retries and mismatched-payload
rejection; duplicate fingerprint rejection; import-without-economics;
reconciliation success and wrong-account/amount/double-match failures;
reconciliation race safety; exact inverse reversals; double-reversal
rejection; dependency-order rules; and exact int64 money round-trips.

## Consequences

- S2 introduces the subledger while deliberately excluding statutory/general
  ledger, chart-of-accounts editing, tax/VAT, consolidation, external
  accounting adapters, bank APIs, fuzzy/split reconciliation, multi-currency
  FX, period close/reopen, allocation/distribution, and a generic approvals
  engine — all remain later bounded slices.
- The OWNER/MEMBER boundary is the current membership model's smallest
  honest maker-checker split; a role framework or approvals engine is only
  considered when a workflow genuinely needs it.
- S1 contributions remain the only source of opening book cash; the
  attribution command keeps S1's contribution records untouched and audited.
