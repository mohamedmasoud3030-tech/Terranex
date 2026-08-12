# ADR-0007: S6 Period Close and Controlled Correction

## Status

Accepted for GF-007 / S6.

## Context

The merged S0–S4 foundation produced authoritative financial facts
(S1 capital, S2 journal batches/lines, S3 property lifecycle, S4 sale
recognition and collection) but had no period close and no controlled
correction. The S2 generic `reverse_journal_batch` command is the only
existing mutation path; it is intentionally closed-loop, so reversing
S4 sale/collection batches was blocked at the S4 deferred-reversal
trigger until S6 provided a controlled correction model. Operators had
no way to freeze a period, gate the work that landed inside it, or
correct a posted batch without touching a closed period.

## Decision

S6 introduces the period close, immutable close snapshots, a database-
enforced period lock on every financial posting, controlled correction
through a documented reversal+replacement chain, and approved reopen
as the only way to mutate a closed period's data.

### Period lifecycle

- `accounting_periods` is a forward-versioned authoritative table.
  Each row is one OPEN or CLOSED window for a `(organization, project,
  currency)` scope. A unique partial index on `status = 'OPEN'`
  enforces at most one open period per scope at the database. A
  `daterange &&` non-overlap guard rejects overlapping rows from
  direct DML.
- A CLOSED period is immutable. Columns, status, currency, dates,
  version, and supersedes back-pointer cannot drift. The closed row
  remains in place forever; reopen does not delete or rewrite it.
- `s6_reopen_period` creates a new authoritative OPEN row with
  `version = old.version + 1`, `start_date = old.end_date + 1`,
  `supersedes_period_id = old.id`, and an audit event. The audit
  event records `accounting_effect = 'NONE_HISTORICAL'` so the reopen
  itself is auditable as a no-op against the prior snapshot.

### Close run and versioned snapshot

- `close_runs` is one row per prepare/approve cycle. Every run has a
  monotonically increasing `version` per `period_id`. A partial unique
  index on `status = 'PREPARED'` makes duplicate prepare calls a
  hard database error so the race rolls back cleanly. The `APPROVED`
  status triggers an `s6_guard_close_run_immutable` after-state guard
  so approved runs never drift.
- `close_run_gates` carries the ten close gates (nine concrete plus
  the composite `CLOSE_REPORT_AND_EXCEPTIONS`). Gate results are
  `PASS`, `FAIL`, `APPROVED_EXCEPTION`, or `NOT_APPLICABLE`. Only
  `NOT_APPLICABLE` is allowed without operator review and only with
  an objective reason recorded in the gate detail (for example
  `SUSPENSE_CONTROL_ACCOUNTS` is structurally absent in S1–S4).
- `close_run_exceptions` is an append-only review log. An exception
  must be `REQUESTED` then `APPROVED`; the `s6_guard_close_run_
  exception_immutable` trigger prevents a decided exception from
  silently flipping. The gate.exception_id back-pointer guard
  (`s6_guard_gate_exception_link`) makes sure an `APPROVED_EXCEPTION`
  gate result only points at an `APPROVED` exception on the same run.
- `close_run_snapshots` is the frozen output of an approved close.
  The `content_hash` is `encode(digest(totals::text, 'sha256'),
  'hex')`. The snapshot is append-only — `s6_guard_immutable_snapshot`
  rejects any update or delete with a precise message. The old
  snapshot remains forever; a re-prepare/approve cycle produces a new
  version, a new snapshot, and never rewrites history.

### Close gates

The ten gates, evaluated server-side by `s6_evaluate_gate`:

- `JOURNAL_BATCHES_BALANCED`: every batch in the period has matching
  debit/credit totals (defensive check; the S2 balanced trigger
  already enforces it at insert).
- `BANK_RECONCILIATION_COVERAGE`: every bank statement line in the
  period has at least one reconciliation allocation.
- `SUSPENSE_CONTROL_ACCOUNTS`: `NOT_APPLICABLE` with an objective
  reason (no suspense/control account structure exists in S1–S4).
- `RECEIVABLE_PAYABLE_AGING`: counts open payables and open
  receivables at cut-off; reports them for review, defaulting to PASS
  because aging is an operational review, not a precondition.
- `ASSET_SECTOR_ROLLFORWARDS`: no property in `CANDIDATE`,
  `DUE_DILIGENCE`, or `ACQUIRING` at cut-off.
- `EVIDENCE_AND_APPROVALS`: every `EXITING` / `DISPOSED` property
  has an `APPROVED` or `CONTROL_TRANSFERRED` disposition with an
  evidence reference.
- `POSTING_CURRENCY_RULES`: every line in the period uses the
  project reporting currency.
- `SECTOR_CUT_OFF`: every batch in the project lies inside the
  period date range.
- `PARTNER_CAPITAL_ROLLFORWARD`: derived from the S1
  `project_capital_position_read` view — checks `contributed <=
  called`, no negative receivable.
- `CLOSE_REPORT_AND_EXCEPTIONS`: composite — `s6_prepare_close_run`
  re-counts FAIL gates after the others and stores
  `PASS` (zero FAIL) or `FAIL` (any FAIL) as its own result.

### Hard failure vs approved exception

A `FAIL` gate is a hard block on approval. `s6_approve_close_run`
re-checks gate results at approval time and raises if any `FAIL`
remains. Operators can convert a `FAIL` to `APPROVED_EXCEPTION` by
`REQUESTED` then `APPROVED` an exception on the same gate code. The
approval command is idempotent through a unique partial index on
`approval_idempotency_key` plus an advisory lock keyed on the
organization and the idempotency key; a retry with the same key
returns the existing run id, a retry with a different payload raises
`idempotency key payload mismatch`.

### Database-enforced period lock

- `journal_batches_period_lock_guard` fires on every
  `journal_batches` insert. A normal posting whose `transaction_date`
  is not inside any OPEN `accounting_period` row for the same project
  fails at the database, including via direct DML.
- `journal_lines_period_lock_guard` is the same gate for direct
  `journal_lines` inserts, plus a project-currency check.
- Both guards fire even on superuser/owner paths because the trigger
  has no role-conditional bypass. Period lock is a database invariant
  the application can never relax.

### Controlled correction

- `correction_requests` is a forward-versioned document of an intent
  to correct a posted batch. Required fields: `target_batch_id`,
  `source_period_id` (CLOSED), `correction_period_id` (OPEN, same
  currency), `reason`, `evidence_reference`. Status transitions
  `REQUESTED → APPROVED → EXECUTED` or `REJECTED`.
- A reversal of a `PROPERTY_SALE_RECOGNITION` or
  `PROPERTY_SALE_COLLECTION` target is the only allowed path to undo
  a S4 fact, and it is only allowed when the correction request is
  `APPROVED` (or already `EXECUTED`). The S4 deferred-reversal guard
  widens to permit the reversal under the approved correction; the
  S6 `s6_resolve_s4_correction` guard checks the request status
  before the S4 guard runs.
- `s6_execute_correction` posts the exact inverse of the original
  batch into the correction period: a new `journal_batches` row
  with `source_type = 'REVERSAL'`, `reversal_of_batch_id =
  target.id`, and `journal_lines` with debit/credit swapped from
  the original. The correction is idempotent on the same
  idempotency key through a unique partial index plus an advisory
  lock.
- The reversal marks the underlying S4 fact (`property_sale_
  recognitions`, `property_sale_collections`,
  `property_sale_carrying_cost_sources`) as `REVERSED` and links it
  to the correction request. The S4 immutable triggers were widened
  to allow the controlled status-only transition; the recognition
  economics stay immutable, only the status changes.
- A reversal of a `COST_OBLIGATION` against a `CONTROL_TRANSFERRED`
  disposition is rejected with `reopen the period`. The frozen
  carrying-cost snapshot at control transfer cannot be undone by a
  generic correction; that path requires an explicit reopen, a new
  period, and a fresh recognition. There is no `APPROVED_EXCEPTION`
  for that case.

### S4 correction integration

- `s4_guard_deferred_reversal` is widened to allow a reversal when
  the correction request is `APPROVED` / `EXECUTED`. The earlier S4
  hard block is replaced with a documented `correction_request`
  chain.
- `s4_guard_recognition_status_transition` (replaces the S4
  recognition immutability trigger) permits
  `ACTIVE → REVERSED | SUPERSEDED` only and only with a
  `reversal_correction_request_id`. The economics columns stay
  immutable.
- `s4_guard_collection_status_or_link` (replaces the S4 collection
  link-only trigger) combines the link-only transition with a
  controlled status transition. A collection reversal marks the
  collection `REVERSED` and links the correction request.

### Concurrency

- A partial unique index on `(period_id) where status = 'PREPARED'`
  serializes two `s6_prepare_close_run` calls to one success + one
  failure. The loser sees `an open close run already exists`.
- `s6_approve_close_run` uses an advisory lock keyed on
  `(organization, idempotency_key)` plus the partial unique index on
  `close_runs.approval_idempotency_key`. Two concurrent approves
  with the same key produce one snapshot, one APPROVED run, and one
  CLOSED period.
- `s6_execute_correction` uses the same pattern; one reversal batch
  per source batch is the only allowed outcome. A re-execute call
  fails with `correction already executed`.
- All S6 write paths use `security definer` + explicit OWNER checks
  via `s2_require_owner` and `is_active_member`. The S2/S4 write
  layer is not bypassed; correction posts through the same journal
  path with a REVERSAL `source_type` so the existing audit and
  reconciliation surfaces see the correction.

### Read models

- `accounting_periods_read`, `close_runs_read`, `close_run_gates_read`,
  `close_run_exceptions_read`, `close_run_snapshots_read`,
  `correction_requests_read` are all `security_invoker=on` views.
  Money is transported as text (read-only surface, no client-side
  arithmetic).

## Non-goals (deferred to S5 or later)

- No allocation, distribution, payable, waterfall, preferred return,
  hurdle, carry, clawback, tax, withholding, FX engine, or external
  GL adapter.
- No generic workflow engine.
- No chart-of-accounts editor.
- No Agriculture or Livestock sectors.
- No CQRS, no event sourcing, no microservices, no message broker.
- No automated decision on whether an aging item is material; the
  gate reports and the operator reviews. The composite close gate is
  computed server-side but never auto-approves.

## Consequences

- Periods are now a database-enforced, versioned, auditable concept.
  Closed periods are immutable facts; reopen is a documented
  supersede, not a rewrite.
- The S2 journal layer is still the only financial write path. S6
  adds no parallel ledger.
- The S4 deferred-reversal guard is no longer a hard block; the
  block is now a documented, OWNER-approved correction chain that
  preserves the recognition/collection/carrying-cost provenance.
- Close snapshots are content-hashed and append-only, suitable for
  the future S5 allocation slice to consume without re-deriving
  the S1–S4 state at allocation time.
