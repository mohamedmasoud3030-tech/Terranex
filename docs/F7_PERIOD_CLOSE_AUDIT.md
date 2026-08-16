# F7 — Period Close Audit

**Date:** 2026-08-16
**Branch:** `arena/01a00890-terranex`
**Scope:** Verify the existing S6 period-close implementation against the F7 exit criteria instead of calling it complete without evidence.

## 1. Exit criteria vs implementation

| Criterion | Evidence | Verdict |
|---|---|---|
| Accounting periods with OPEN/CLOSED states per (org, project, currency) | `accounting_periods` table; `status in ('OPEN','CLOSED')`; versioned rows | PASS |
| One open period per scope | Partial unique index `accounting_periods_one_open_per_scope` | PASS |
| Non-overlapping authoritative periods | `s6_guard_period_no_overlap()` BEFORE INSERT/UPDATE trigger | PASS |
| Closed periods immutable | `s6_guard_period_immutable_history()` trigger | PASS |
| Posting locked to an open period | `s6_validate_posting_in_open_period()` + `s6_validate_line_in_open_period()` triggers on journal batches/lines; opt-in once a period exists | PASS |
| Close runs with gates | `close_runs` (PREPARED/APPROVED/REJECTED) + `s6_evaluate_gate()` with the canonical gate vocabulary (JOURNAL_BATCHES_BALANCED, BANK_RECONCILIATION_COVERAGE, RECEIVABLE_PAYABLE_AGING, ASSET_SECTOR_ROLLFORWARDS, EVIDENCE_AND_APPROVALS, POSTING_CURRENCY_RULES, SECTOR_CUT_OFF, PARTNER_CAPITAL_ROLLFORWARD, …) | PASS |
| Gate exceptions with maker/checker | `close_run_exceptions` (PENDING/APPROVED/REJECTED), requester ≠ approver, immutability guards | PASS |
| Approved close runs immutable | `s6_guard_close_run_immutable()` | PASS |
| Controlled reopen | `s6_reopen_period()` — CLOSED-only, OWNER-only, reason + evidence required, new version superseding the closed period | PASS |
| Controlled corrections | `correction_requests` (REQUESTED→APPROVED/REJECTED→EXECUTED/SUPERSEDED) + `s6_request_correction/approve/reject/execute_correction` | PASS |
| OWNER boundary on all close commands | `s2_require_owner()` in create period, prepare/approve close run, approve exception, reopen, correction commands | PASS |
| Close snapshots | `close_run_snapshots` immutable, content-hash + totals | PASS |

## 2. Findings

1. All close/correction commands are OWNER-gated, versioned and evidence-required where the mission requires it.
2. The period lock is deliberately opt-in (enforced only once a period exists for the project) — this preserves the S1–S4 setup flow and is documented in the S6 migration comments. This is a design decision already present in the canonical code, not a gap.
3. The only missing surface was a controller view: one row per (project, currency) showing the open period, the last closed period, close runs/exceptions in flight, open corrections, and F3 dispute/overdue state. Delivered as `period_close_health_read` (migration `20260816054000_f7_period_close_health.sql`) with an explicit `close_health` state per scope.

## 3. Verdict

**F7 — Period Close: COMPLETE.** The existing implementation satisfies the mission exit criteria; the F7 migration adds the health read model and no behavioral change was needed.

*Audit performed 2026-08-16 against `arena/01a00890-terranex`*
