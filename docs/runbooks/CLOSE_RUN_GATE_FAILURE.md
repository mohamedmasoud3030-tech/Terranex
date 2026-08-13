# Runbook — Close-run gate failure

**Scope:** a period close run cannot be approved because one or more of the ten S6 close gates reports `FAIL` (or a gate result is disputed). This runbook triages every gate category and routes each one to its treatment. It never replaces the specialized runbooks; it decides which one applies.

**Standing rule:** a `FAIL` gate is a truthful control, not an obstacle. The only ways a gate stops failing are: fix the underlying fact through an authoritative product command, or — where this runbook explicitly says so — carry the item as an `APPROVED_EXCEPTION` with evidence through the close-exception workflow. There is no third path.

## 1. Symptom

- `s6_prepare_close_run` (or a gate re-evaluation) returns one or more gates as `FAIL`, and close approval is blocked.
- The pilot workspace / close checklist shows a failing gate code with a detail message.
- `CLOSE_REPORT_AND_EXCEPTIONS` refuses the composite close because a `FAIL` gate has no linked approved exception.

## 2. Immediate safety action

1. **Do not approve the close** while any gate is `FAIL` without its own linked approved exception.
2. **Do not delete or re-label anything.** Close runs, gates, and exceptions are append-only and immutable by trigger; a failed run stays as evidence.
3. Record the close run id, period id, failing gate codes, and their exact detail/evidence payloads before touching anything.
4. If more than one gate fails, triage in the order below; cash and integrity gates come first.

## 3. Evidence to preserve

Capture before any remediation:

- close run id and version, period id and date range, project id;
- every gate result row (`PASS`/`FAIL`/`APPROVED_EXCEPTION`/`NOT_APPLICABLE`) with its `detail` and `evidence` jsonb;
- the failing detail numbers (counts and minor-unit amounts) exactly as reported;
- who prepared the run and when.

## 4. Diagnosis and treatment per gate

Owners: `<FINANCE_CONTROL_OWNER>` triages; `<ENGINEERING_ONCALL>` is pulled in only where marked; close approval always remains with the customer OWNER.

### 4.1 `JOURNAL_BATCHES_BALANCED`

- **What the failure means:** a journal batch in the period has debits ≠ credits or fewer than two lines. The balance trigger makes this impossible through normal product commands, so a `FAIL` here indicates something bypassed database controls (e.g. direct DML with elevated privileges).
- **Evidence to capture:** the batch ids reported, their line sums, and any database/admin session that could have written directly.
- **Safe diagnostic path:** read-only listing of the reported batches and their lines; check `audit_events` and deployment history around the posting dates.
- **Responsible owner:** `<ENGINEERING_ONCALL>` with `<SECURITY_OWNER>` — treat as an integrity incident, not a bookkeeping fix.
- **Acceptable remediation:** if a batch is confirmed wrong, correct it through the linked-reversal command path (`INCORRECT_POSTED_TRANSACTION.md`), then re-run the gate. If direct tampering is suspected, treat as a security incident (`CROSS_TENANT_OR_SECURITY_INCIDENT.md`) before any correction.
- **Forbidden remediation:** any direct SQL repair of journal lines; deleting or rewriting the batch; approving the close with this gate failed. This gate is **never** approvable as an exception.
- **Re-run/sign-off:** re-evaluate the gate after the reversal posts; it must return `PASS` on its own.

### 4.2 `BANK_RECONCILIATION_COVERAGE`

- **What the failure means:** bank statement lines in the period have no reconciliation allocation; the detail reports the count and total minor units.
- **Evidence to capture:** the unreconciled line list (dates, amounts, provider references) and the current book-side candidates.
- **Safe diagnostic path:** match candidates one-to-one against book receipts/payments/collections; unmatched-on-purpose lines (bank charges, interest, external transfers) are identified explicitly.
- **Responsible owner:** `<FINANCE_CONTROL_OWNER>`.
- **Acceptable remediation:** reconcile the lines through the normal reconciliation commands; or, for lines that legitimately remain explained-but-unmatched at close, request a close-run exception and have it approved with evidence (the product path named in the gate's own detail). Full treatment: `UNRECONCILED_CASH.md`.
- **Forbidden remediation:** forcing a match to the wrong book item; deleting statement lines; importing an altered statement; closing while genuine unknowns stay unowned.
- **Re-run/sign-off:** reconcile or approve the exception, then re-evaluate; result must be `PASS` or `APPROVED_EXCEPTION` with the exception linked.

### 4.3 `SUSPENSE_CONTROL_ACCOUNTS`

- **What the failure means:** in the current S1–S4 subledger this gate is structurally `NOT_APPLICABLE` — there is no suspense/control account structure and no editable balance column. A result other than `NOT_APPLICABLE`/`PASS` would itself be a defect.
- **Evidence to capture:** the gate result row itself.
- **Safe diagnostic path:** confirm the result; if the gate reports `FAIL`, escalate immediately as an integrity incident.
- **Responsible owner:** `<ENGINEERING_ONCALL>` only in the defect case.
- **Acceptable remediation:** none needed for `NOT_APPLICABLE`/`PASS`; defect case follows `FAILED_DEPLOYMENT_OR_MIGRATION.md` plus incident escalation.
- **Forbidden remediation:** inventing a suspense workaround or posting a "clearing" journal by hand.
- **Re-run/sign-off:** none for the normal outcome.

### 4.4 `RECEIVABLE_PAYABLE_AGING`

- **What the failure means:** this is a review gate; it reports counts of open payables (authorized obligations with outstanding amounts) and open receivables (recognitions with collections short of proceeds). Open items are normal business — the control is that a human reviewed them.
- **Evidence to capture:** the reported open-payable and open-receivable counts and the reviewer's aging notes.
- **Safe diagnostic path:** review each open item: is it genuinely open at cut-off, or is there a missing payment/collection/decision?
- **Responsible owner:** `<FINANCE_CONTROL_OWNER>` with the close preparer.
- **Acceptable remediation:** record the missing payment/collection through the normal flows if something was omitted; otherwise document the review and proceed. If an aging item is undecided or disputed, attach a close-run exception rather than silently passing.
- **Forbidden remediation:** recording a payment that did not happen in the customer's banking process just to zero an aging item; hiding disputed items from the review.
- **Re-run/sign-off:** re-evaluate after corrections; carry review evidence into the close record.

### 4.5 `ASSET_SECTOR_ROLLFORWARDS`

- **What the failure means:** one or more properties are still in a pre-held lifecycle state (`CANDIDATE`, `DUE_DILIGENCE`, `ACQUIRING`) at cut-off.
- **Evidence to capture:** the asset list with current states and their state histories.
- **Safe diagnostic path:** for each asset decide the truth at cut-off: did control/acquisition actually complete (then record it with evidence), or is the project genuinely still pre-held (then the period's expectations, not the asset, are wrong)?
- **Responsible owner:** operating member who owns the asset lifecycle, with `<FINANCE_CONTROL_OWNER>`.
- **Acceptable remediation:** complete the lifecycle transition through the S3 commands with the required control/acquisition evidence; or, if the state is genuinely correct at cut-off, carry it as an approved close exception with that justification.
- **Forbidden remediation:** forcing an asset state forward without acquisition/control evidence (the product's "no owned state without evidence" control exists precisely against this).
- **Re-run/sign-off:** re-evaluate after the transitions/exception; `PASS` or linked `APPROVED_EXCEPTION`.

### 4.6 `EVIDENCE_AND_APPROVALS`

- **What the failure means:** a property in `EXITING` or `DISPOSED` lacks an approved/control-transferred disposition.
- **Evidence to capture:** the asset list and the disposition (or its absence) for each.
- **Safe diagnostic path:** check whether the disposition workflow was started but not completed (approval pending, control transfer missing) versus never started.
- **Responsible owner:** operating member + OWNER for the approval step.
- **Acceptable remediation:** complete the disposition workflow through its product commands with the contract/control-transfer evidence; if the lifecycle state itself was wrong, correct the lifecycle per S3 semantics with evidence.
- **Forbidden remediation:** approving a disposition without the underlying contract/control evidence; editing lifecycle state directly.
- **Re-run/sign-off:** re-evaluate; must be `PASS` (a missing-approval condition is not a candidate for indefinite exception — complete the approval).

### 4.7 `POSTING_CURRENCY_RULES`

- **What the failure means:** a journal line in the period uses a currency other than the project reporting currency. Line-insert validation normally makes this impossible; a `FAIL` indicates a bypass of controls.
- **Evidence to capture:** the offending line/batch ids, their currencies, and any direct-write session evidence.
- **Safe diagnostic path:** read-only listing of the reported lines; verify whether a reversal/repost in the correct currency is required.
- **Responsible owner:** `<ENGINEERING_ONCALL>` with `<FINANCE_CONTROL_OWNER>` — treat as an integrity issue like 4.1, at lower urgency if the cause is identifiable.
- **Acceptable remediation:** linked reversal of the offending batch and repost through the correct product command in the reporting currency (`INCORRECT_POSTED_TRANSACTION.md`).
- **Forbidden remediation:** SQL update of the currency column; approving the close with the gate failed. Not exception-approvable.
- **Re-run/sign-off:** re-evaluate; must return `PASS`.

### 4.8 `SECTOR_CUT_OFF`

- **What the failure means:** one or more batches are attributed to the project with a transaction date outside the period's date range.
- **Evidence to capture:** the out-of-range batch ids and their dates.
- **Safe diagnostic path:** determine whether the date is wrong (event actually belongs to another period) or the period boundaries are wrong.
- **Responsible owner:** `<FINANCE_CONTROL_OWNER>` with the close preparer.
- **Acceptable remediation:** if the posting date is wrong, correct via linked reversal and repost in the correct period (`INCORRECT_POSTED_TRANSACTION.md`, and `CLOSED_PERIOD_CORRECTION.md` when the correct period is closed); if the period boundaries are wrong, fix the period plan through the period commands before preparing the close again.
- **Forbidden remediation:** editing batch dates directly; stretching a period silently to absorb stray postings.
- **Re-run/sign-off:** re-evaluate; must return `PASS`.

### 4.9 `PARTNER_CAPITAL_ROLLFORWARD`

- **What the failure means:** the derived capital rollforward is inconsistent — contributed capital exceeds called capital, or a receivable position is negative.
- **Evidence to capture:** the rollforward totals reported in the gate evidence (committed/called/contributed/receivable).
- **Safe diagnostic path:** compare against the customer's capital register (reconciliation R-03/R-07): find the contribution, call, or opening row that breaks the invariant.
- **Responsible owner:** `<FINANCE_CONTROL_OWNER>`.
- **Acceptable remediation:** correct the underlying facts through the authoritative paths — contribution/call corrections via linked reversal (`INCORRECT_POSTED_TRANSACTION.md`), wrong opening rows via `FAILED_OPENING_IMPORT.md` (reversal-guard ordering applies). Then re-evaluate.
- **Forbidden remediation:** any direct balance adjustment; forcing the rollforward view; approving the close with the gate failed. Not exception-approvable — the rollforward must be exactly consistent.
- **Re-run/sign-off:** re-evaluate; must return `PASS`.

### 4.10 `CLOSE_REPORT_AND_EXCEPTIONS`

- **What the failure means:** composite gate — the close run as a whole is not review-ready: some `FAIL` gate has no linked approved exception.
- **Evidence to capture:** the full gate set of the run; which failing gates lack exception links.
- **Safe diagnostic path:** walk the gate list; for each `FAIL`, either remediate per 4.1–4.9 or complete the exception workflow (request → approve with evidence).
- **Responsible owner:** close preparer coordinates; OWNER approves exceptions and the close.
- **Acceptable remediation:** resolve every underlying gate first; this gate clears when the run is coherent.
- **Forbidden remediation:** approving exceptions without evidence or without reading the underlying gate detail.
- **Re-run/sign-off:** re-prepare/re-evaluate the run; then OWNER close approval.

## 5. Prohibited shortcuts (all gates)

- Never mutate posted journal facts, batches, or lines with SQL — corrections are linked reversals and replacements through product commands only.
- Never delete or edit a close run, gate row, or exception; they are append-only evidence.
- Never approve an exception for gates marked "not exception-approvable" above (4.1, 4.7, 4.9).
- Never bypass maker/checker: if only the maker is available, the close waits.
- Never report a gate as re-run when it was not re-evaluated after remediation.

## 6. Post-recovery verification

- Every remediated gate re-evaluates to `PASS` (or `APPROVED_EXCEPTION` with a linked approved exception where this runbook allows it).
- The full close run is re-prepared/re-evaluated end-to-end so the composite gate sees the current state.
- The evidence jsonb of the final gate rows reflects reality (counts, amounts, exception ids).
- Weekly checkpoint set for the same period still shows zero variance (`06_RECONCILIATION_PROCEDURES.md`) — a gate fix that moves money must re-reconcile.

## 7. Escalation

- Cash/integrity gates (4.1, 4.2, 4.7, 4.9) unresolved within one business day → `<ENGINEERING_ONCALL>` + `<FINANCE_CONTROL_OWNER>` jointly.
- Any suspicion of direct DML/tampering → `<SECURITY_OWNER>` via `CROSS_TENANT_OR_SECURITY_INCIDENT.md` before further corrections.
- Close date at risk → `<PILOT_OPS_OWNER>` communicates with `<CUSTOMER_APPROVER>`; a close is postponed honestly rather than approved loosely.

## 8. Communication

- Tell the customer which gates failed, what they mean in business terms, the remediation path, and the new expected close date.
- Never promise the close date before the re-evaluated gate results exist; never describe an `APPROVED_EXCEPTION` as if the underlying item were resolved.

## 9. Record

For every gate failure write down: close run id, gate code, detail/evidence captured, root cause, remediation taken (command references), exception id if used, re-evaluation result, and who verified it. The record lives with the engagement's incident log; real customer data stays in the customer's systems (references only).
