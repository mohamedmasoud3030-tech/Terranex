# ADR-0007: S6 Period Close and Controlled Correction

## Status

Accepted for GF-007 / S6 on 2026-08-12.

## Context

S0–S4 established tenant isolation, immutable investment terms, a balanced project subledger, Real Estate operational state, and realized sale/collection results. S6 adds the period boundary that makes those facts governable: accounting periods, close controls, immutable close snapshots, controlled reopen, and linked correction/reversal without rewriting historical economics.

## Decision

### Period lifecycle

- `accounting_periods` is the authoritative period model once period management is introduced for a project/currency.
- At most one OPEN period may exist for the same organization/project/currency scope.
- A CLOSED period is immutable. Reopen creates a successor row with a higher version and `supersedes_period_id`; it never edits the closed row back to OPEN.
- Normal financial postings are checked at the database boundary and, once authoritative period management exists for that project, must fall inside an OPEN period.

### Close run and immutable snapshot

- `close_runs` is versioned; at most one PREPARED run may exist for the same period.
- Close preparation evaluates nine concrete controls plus the composite `CLOSE_REPORT_AND_EXCEPTIONS` gate.
- `close_run_snapshots` is append-only and content-hashed. An approved snapshot is never regenerated in place; later work creates a new version.
- Material close approval remains OWNER-only using the existing MEMBER/OWNER maker-checker model. No generic approval engine is introduced.

### Truthful close controls

- `BANK_RECONCILIATION_COVERAGE` is `FAIL` when unreconciled statement lines exist inside the closing period. It may become `APPROVED_EXCEPTION` only through the documented exception request/approval workflow. A PASS is never fabricated.
- `SECTOR_CUT_OFF` is scoped to the period being closed. Valid prior- or future-period batches do not block the current close. Header/line project or date mismatches that straddle the closing boundary do.
- `ASSET_SECTOR_ROLLFORWARDS` verifies reproducibility from authoritative append-only S3 state history. A legitimate CANDIDATE, DUE_DILIGENCE, or ACQUIRING asset does not fail close merely because it has not reached HELD.
- `CLOSE_REPORT_AND_EXCEPTIONS` is recomputed from the concrete gates and excludes itself from its own fail count, preventing a stale/self-perpetuating FAIL.

### Approved exception integrity

- `close_run_exceptions` is linked to the exact `(close_run_id, organization_id)` pair.
- A decided exception is immutable except for the controlled approval transition.
- An `APPROVED_EXCEPTION` gate must point to an APPROVED exception on the same run and gate code.
- Any remaining concrete FAIL blocks close approval.

### Controlled correction

- `correction_requests` is a forward-only request/approval/execution chain against an existing posted batch.
- Execution posts an exact linked reversal through the existing S2 journal layer. S6 adds no parallel ledger.
- The original journal batch, journal lines, S4 amounts, source references, and carrying-cost provenance remain immutable.
- S6-added correction metadata may move an S4 recognition/collection/carrying-source status from ACTIVE to REVERSED/SUPERSEDED only when linked to the matching APPROVED/EXECUTED correction request.
- Replacement economics, when required, are a new posting. Historical facts are not overwritten.

### Concurrency and idempotency

- Concurrent prepare commands cannot create two PREPARED close runs.
- Approval uses database serialization/idempotency so retries produce one material approved close and one immutable snapshot.
- Posting into a CLOSED period is rejected without leaving a partial batch.
- Correction execution is idempotent and cannot produce duplicate reversal effects.

### Historical regression boundaries

- S3 and S4 forward-upgrade suites are pinned to their historical migration families so later migrations cannot leak into an earlier-stage baseline.
- Legacy S2/S4 concurrency fixtures use real OPEN-period dates/windows when S6 is installed. Production period-lock triggers are never disabled to make historical tests pass.

## Accounting and integrity invariants

- S2 remains authoritative for balanced, single-currency, project-scoped immutable journal batches.
- S6 does not duplicate or replace S2 mixed-currency/balance validation.
- Cash, revenue, cost, valuation, allocation, payable, distribution approval, and cash payment remain separate facts.
- Cross-organization and cross-project references remain database-rejected.
- Close snapshots preserve exact inputs and results for downstream allocation.

## Verification

PR #98 was verified on canonical PostgreSQL 16 Greenfield CI before merge:

- application job — PASS;
- database fresh replay and two-tenant isolation — PASS;
- S0–S4 SQL and concurrency regressions — PASS;
- S3 forward-upgrade — PASS;
- S4 forward-upgrade — PASS;
- S6 period-close/correction SQL — PASS;
- S6 real two-session prepare/approve/closed-period concurrency — PASS;
- S6 forward-upgrade — PASS;
- SonarQube Cloud Quality Gate — PASS;
- Sonar security hotspots — 0;
- new-code duplication — 1.7%.

Merged PR: **#98**  
Merge commit: `d26a3bbbc9a8e29b61bb0a4ecfd2a21bf9e0a0c6`

## Deferred

S5 owns allocation and distribution. Also deferred: preferred return, hurdle tiers, GP catch-up, carried interest, waterfall/clawback rules, tax/withholding/FX engines, external/statutory GL adapters, bank APIs, generic workflow engines, PWA/offline, Agriculture/Livestock runtime modules, and microservice/CQRS/event-sourcing architecture.

## Consequences

- Period close is now a database-enforced, versioned and auditable boundary.
- Approved close snapshots are stable inputs for S5; S5 must consume them rather than re-derive live S1–S4 results.
- Correction preserves historical economics while providing a controlled forward correction chain.
- The financial architecture remains one modular monolith and one authoritative subledger.
