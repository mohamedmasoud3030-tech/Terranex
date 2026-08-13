# 07 — Incident and Support Operating Matrix

**Purpose:** link pilot support situations to the **existing** runbooks in `docs/runbooks/`. This matrix does not duplicate or override any runbook; the runbooks are authoritative and their standing rules (no destructive SQL on posted facts, no evidence deletion, no maker/checker bypass, no service-role key from a browser, never claim an unrun gate) apply to every situation below.

**Entry point for everything:** `docs/runbooks/SUPPORT_ESCALATION.md` decides severity, ownership, and escalation. The escalation owners are engagement placeholders — fill them before go-live (gate PRM-10): `<PILOT_OPS_OWNER>`, `<FINANCE_CONTROL_OWNER>`, `<ENGINEERING_ONCALL>`, `<SECURITY_OWNER>`, `<CUSTOMER_APPROVER>`.

## Situation → runbook matrix

| # | Situation | First response | Authoritative runbook(s) | Notes / cross-references |
| --- | --- | --- | --- | --- |
| I-01 | Failed opening import (rejected rows, stuck state, control-total mismatch, approval refused) | Stop the import; preserve the staged record, rejected-row reasons, and declared vs computed totals | `FAILED_OPENING_IMPORT.md` | Prevention procedure: `03_OPENING_BALANCE_CONTROL_PACK.md` §6–7 |
| I-02 | Incorrect posting (wrong amount/party/date/account, or posting for a transaction that never happened) | Do not touch the posted batch; capture the batch id and the observed balance drift | `INCORRECT_POSTED_TRANSACTION.md` | Correction is linked reversal + replacement, never SQL edits |
| I-03 | Bank/cash reconciliation variance | Freeze further matching on the affected account; list unmatched lines both sides | `UNRECONCILED_CASH.md` | Reconciliation R-01/R-02 in `06_RECONCILIATION_PROCEDURES.md` |
| I-04 | Non-cash reconciliation variance (capital, payable, receivable, distribution checkpoint) | Record the exception the checkpoint opened; assign owner and severity | `SUPPORT_ESCALATION.md` (triage) → `INCORRECT_POSTED_TRANSACTION.md` if a posting is wrong; otherwise `03_OPENING_BALANCE_CONTROL_PACK.md` §12 / `06_RECONCILIATION_PROCEDURES.md` | Correct the wrong side through product paths, then record a **new** checkpoint — never edit the old one |
| I-05 | Access revoked unexpectedly / someone lost or has access they should not | Confirm the membership state and actor; if suspicious, treat as security | `MEMBERSHIP_AND_ACCESS_INCIDENT.md` | Revocation is immediate and audited (`s7_set_membership_status`); last-active-owner guard applies |
| I-06 | Suspected tenant exposure / cross-organization data leak | Treat as real until disproven; highest-severity runbook | `CROSS_TENANT_OR_SECURITY_INCIDENT.md` | Notify `<SECURITY_OWNER>` immediately; preserve request evidence |
| I-07 | Close failure (a close gate FAILs or close approval is blocked) | Capture the close run id, failing gate codes, and details | `UNRECONCILED_CASH.md` when `BANK_RECONCILIATION_COVERAGE` fails; `SUPPORT_ESCALATION.md` for triage of other gates; `CLOSED_PERIOD_CORRECTION.md` when the blocker is a wrong fact in an already-closed period | Gate semantics: `06_RECONCILIATION_PROCEDURES.md` R-10; see gap G-01 below |
| I-08 | Backup/restore event (verification requested, or a real restore being considered) | Distinguish rehearsal from production restore; never conflate them | `BACKUP_AND_RESTORE.md` | The automated rehearsal (`supabase/tests/26_s7_backup_restore.sh`) is not a production restore and never claims one |
| I-09 | Duplicate command concern ("I think it posted twice") | Find the idempotency key and request hash of the suspected command | `SUPPORT_ESCALATION.md` (triage) → `INCORRECT_POSTED_TRANSACTION.md` only if a duplicate material effect actually exists | Product semantics: identical retry (same key + same request hash) has exactly one material effect; a changed payload under a reused key is refused. Most concerns resolve as no-op after verification — record the verification |
| I-10 | Unavailable application / failed release or migration | Confirm deployment state; preserve logs and migration position | `FAILED_DEPLOYMENT_OR_MIGRATION.md` | Rollback decision belongs to `<ENGINEERING_ONCALL>` per that runbook |
| I-11 | Data correction request from the customer | Classify: open period vs closed period; posted fact vs draft | Open period: `INCORRECT_POSTED_TRANSACTION.md` · Closed period: `CLOSED_PERIOD_CORRECTION.md` · Draft/unposted: fix in place (drafts may be edited before posting) | Customers never get direct SQL access; all corrections go through product commands with their own approvals |
| I-12 | Allocation/distribution failure or wrong approval | Capture the run/distribution id and the exact refusal message | `FAILED_ALLOCATION_OR_DISTRIBUTION.md` | Approved runs are never overwritten; comparison or reversal per the runbook |
| I-13 | Anything not matching I-01…I-12 | Triage before treating | `SUPPORT_ESCALATION.md` | New recurring classes may justify new runbooks — see gaps below, decided after the pilot |

## Severity defaults (proposed for the pilot; `SUPPORT_ESCALATION.md` decides case by case)

| Severity | Default situations |
| --- | --- |
| CRITICAL | I-06; I-02 with unknown cause on cash/capital; I-10 during operating hours with no workaround; any destructive change to a posted fact |
| HIGH | I-02 identified; I-03/I-04 variance unresolved > 7 days; I-07 blocking the scheduled close; I-08 real restore |
| MEDIUM | I-01 before posting (no posted impact); I-05 non-suspicious; I-09 confirmed no-op; I-11 draft-level |
| LOW | I-13 terminology/UX confusion; cosmetic |

## What support may and may not communicate

- **May:** state what was observed, what was preserved, which runbook applies, what the next step and owner are, and which gates actually ran.
- **May not:** promise a timeline that has not been agreed with the owner; claim a restore/rehearsal/gate happened when it did not; characterize a management valuation or unreconciled number as final; disclose another organization's existence or data under any circumstances.

## Genuinely missing runbook coverage

Identified strictly, without recreating existing content:

- **G-01 — Close-run gate-failure triage.** Cash-gate failures route to `UNRECONCILED_CASH.md`, and closed-period facts route to `CLOSED_PERIOD_CORRECTION.md`, but there is no single runbook that triages the remaining close gates (`SUSPENSE_CONTROL_ACCOUNTS`, `EVIDENCE_AND_APPROVALS`, `SECTOR_CUT_OFF`, `PARTNER_CAPITAL_ROLLFORWARD`, …) from "close run FAILs" to resolution. **Proposed:** one `CLOSE_RUN_GATE_FAILURE.md` runbook following the standard ten-section runbook format. Not written here to avoid diverging from the active audit/remediation workstream; create it after the audit stream merges, before or during Week 0.
- **G-02 — Non-cash checkpoint variance treatment.** The product flow (mandatory exception → correction → new checkpoint) is complete and documented in this pack (`03` §12, `06`), but it lives in readiness documents rather than in `docs/runbooks/`. **Proposed:** if pilot evidence shows operators need it, promote the procedure into the runbook set after the audit stream merges. Until then, this pack's procedures are the operating reference.

No other situation class above lacks coverage: every row resolves to an existing runbook or to documented product semantics.
