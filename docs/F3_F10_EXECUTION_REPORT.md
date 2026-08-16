# F3–F10 Execution Report — Review Round (post-audit)

**Date:** 2026-08-16
**Branch:** `arena/01a00890-terranex`
**PR:** #147

This is the corrected report after the independent financial/operational
audit. The first version of this report claimed COMPLETE where the audit
found real P0/P1 defects. This version documents the defects, the fixes,
the regression coverage, and the honest phase ratings. **R13 remains
NOT OPENED.**

## Review defects found → fixed (in order)

| # | Severity | Defect | Fix | Regression |
|---|---|---|---|---|
| 1 | P0 | F9/F10 counted reversal batches as net effect instead of zero | `project_financial_position_read` now excludes both reversal batches (`reversal_of_batch_id is null`) and reversed originals | 88 suite: authorize → reverse → position nets exactly back |
| 2 | P0 | Budget ceiling check not concurrency-safe | Per-budget-line advisory lock (`:f4-budget-line:`) serializes check+post | New two-session shell gate `90_f3_f10_budget_concurrency.sh`: exactly one of two parallel authorizations succeeds |
| 3 | P0/P1 | Supersede disabled the ceiling while the successor was DRAFT | Ceiling falls back to the last SUPERSEDED (previously approved) version; the ceiling never vanishes | 88 suite authorizes through the revision gap |
| 4 | P1 | Overlapping budgets could both be approved in parallel | Per-project advisory lock in `f4_approve_project_budget` makes the non-overlap trigger race-free | CI database gate + deterministic check |
| 5 | P1 | Budget exceptions could mix currencies | BUDGET_CEILING exceptions must carry the budget currency (derived server-side); relief sums filter by currency | 88 suite: USD relief on an EGP line is rejected |
| 6 | P1 | Exception UI could record a budget exception on the wrong line | Subject selection keyed by unique `type::id`; hidden fields derived from the selected entry | UI rework + schema strictness |
| 7 | P1 | MILESTONE_SCHEDULE unusable (no write RPC / form) | `f3_set_obligation_schedule` RPC + schedule editor form | 88 suite: RPC persists lines and rejects totals above the obligation |
| 8 | P1 | Milestone from another project could release retention | Release requires the milestone to belong to the same project | 88 suite: cross-project release rejected |
| 9 | P1 | Forms reused idempotency keys after success | All control forms migrated to the canonical `useCommandIdempotencyKey` lifecycle (key survives failed retries; rotates only after confirmed success) | Pattern-proven by livestock/portfolio forms; actions now return `commandSuccessState`/`commandFailureState` |
| 10 | P1 | Retention = 0 broken (parser rejected zero) | Zero-tolerant exact parser for retention | schema + parser tests |
| 11 | P1 | Hardcoded EGP scale | Retention/release parse with the actual obligation currency | schema is currency-aware |
| 12 | P1 | OMR (3 decimals) unsupported | `MONEY_CURRENCIES` gains the ISO three-decimal set (BHD/JOD/KWD/LYD/OMR/TND/IQD) | `shared-money.test.ts` |
| 13 | P1 | FX conversion form didn't send currencies the action required | `f6_record_fx_conversion_by_snapshot` derives both currencies from the snapshot; schema/form no longer restate them | unit + suite |
| 14 | P1 | Policy checkboxes couldn't save false | Hidden `false` + checkbox `true` pattern for evidenceRequired/active | UI rework |
| 15 | P1 | VOID contradicted the DB constraint | VOID is a normal OWNER decision; the opener can never decide | 88 suite: opener VOID rejected, second owner VOIDs |
| 16 | P1 | Budget form silently dropped invalid lines | The whole budget is rejected when any line is invalid | action-level strict parsing |
| 17 | P1 | F7 dispute counters always zero | Counters use the derived `is_disputed`/`payment_blocked` flags; in-flight = PREPARED only (REJECTED runs are not in-flight) | view correction |
| 18 | P1 | Close could proceed with open approval exceptions | New `OPEN_APPROVAL_EXCEPTIONS` gate inside the preserved gate chain (`s6_evaluate_gate` wrapper → impl intercept → core evaluator) | 88 suite: gate FAILs with an open exception, PASSes after decision |
| 19 | P1 | F8 invented a retention-due signal | Removed; every remaining signal now carries `source_ids` linking to its authoritative subjects | 88 suite asserts the invented signal does not exist |
| 20 | P1 | F10 historical attribution used current membership | `portfolio_financial_rollup_asof(org, portfolio, asof_date)` uses append-only assignment intervals + as-of journal/register filters | 88 suite: as-of before assignment shows zero members |
| 21 | scope | F4 forecast was `max(...)`, not FAC | Treatment-level actual + approved forecast remainder in consumption; budget-level `project_budget_fac_read` with Actual / Open Commitments / Approved Forecast Remainder / FAC separated | suite + budget page FAC table |
| 22 | scope | F5 lacked tiered approvals and reject/resubmit | `min_approvers` (1–3 distinct approvers) with append-only `approval_signoffs`; continuation flows in authorization/budget/payment/exception commands; `f5_resubmit_exception` with `replaces_exception_id` | 88 suite: two-approver payment flow, signoff counts, resubmit link |
| 23 | scope | F5 policy domains not wired | BUDGET_EXCEPTION decision gate, RETAINAGE_RELEASE gate (+ evidence column), DISPUTE_RESOLUTION gate (+ evidence column) | commands + schema |
| 24 | scope | F8 lacked actionability | Exceptions gain severity/owner/due/replaces; registry read exposes them; signals expose `source_ids` | UI + suite |
| 25 | scope | F10 lacked commitments/actual/realized/forecast/concentration/sector/risks | Roll-up + as-of now carry open commitments, realized result, FAC, open exceptions, sector exposure, cash concentration | portfolio page + suite |

## Honest phase ratings after the review round

| Phase | Rating | Basis |
|---|---|---|
| F3 Contract Finance | **COMPLETE (independent scope)** | Milestones, terms, schedules (usable RPC+UI), retention+release, disputes, due/aging — all review defects fixed and regression-covered |
| F4 Budget Control | **COMPLETE (independent scope)** | Versioned budgets, concurrency-safe ceiling, revision-gap continuity, overlap race fix, Actual/Commitments/Approved Forecast Remainder/FAC separated |
| F5 Approval & Exception | **COMPLETE (independent scope)** | Tiered approvals (1–3 distinct approvers), evidence gates wired on every displayed domain, reject/resubmit, currency coherence, consistent VOID |
| F6 Currency & Tax | **COMPLETE (independent scope)** | Rational snapshots, deterministic conversion, by-snapshot derivation, currency coherence for exceptions, OMR/3-decimal support, explicit tax registry |
| F7 Period Close | **COMPLETE (independent scope)** | S6 exit criteria (audit doc) + corrected counters + PREPARED-only in-flight + OPEN_APPROVAL_EXCEPTIONS gate in the preserved chain |
| F8 Integrity Center | **COMPLETE (independent scope)** | Signals with source ids, no invented signals, actionability columns on the unified registry |
| F9 Project Performance | **COMPLETE (independent scope)** | Reversal-safe netting proven; FAC-driven performance view |
| F10 Portfolio Control | **COMPLETE (independent scope)** | Current roll-up + historical as-of attribution + commitments/realized/FAC/concentration/sector/exceptions |

**R13 (Full Company Simulation) remains NOT OPENED.** These ratings mean the
independent build now satisfies the mission definitions for F3–F10; whether
the gate opens is decided only after the simulation itself proves the whole
chain. No claim in this report anticipates that decision.

## Verification

- Real PostgreSQL replay (PGlite): all migrations apply in order; behavioral gate `supabase/tests/88_f3_f10_finance_control.sql` (extended with the review regressions) PASS.
- New concurrency gate `supabase/tests/90_f3_f10_budget_concurrency.sh` (two-session ceiling race) — runs in the CI database job.
- pgcrypto compat re-pass `20260816058200_...` keeps suite 33 green after the redefined commands.
- `npm test`: 618/618 PASS · typecheck PASS · lint PASS · build PASS.

## Still deferred (rule-dependent only)

- COGS / inventory valuation, IAS 41, tax *calculation* — company accounting policy.
- Investor entitlement/distribution (BD-001…BD-012) — R14 policy pack after R13.
- PR #146 dependency bump — separate Node 22 mission (review comment posted).
