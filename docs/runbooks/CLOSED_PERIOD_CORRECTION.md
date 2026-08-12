# Runbook — Correction affecting a closed period

**Scope:** a fact recorded in a period that is already `CLOSED` is wrong, or a new fact needs to be recorded with a date inside a closed period.

## 1. Symptom

- A posting attempt fails with "no open accounting period covers transaction_date ... for this project" or "no open accounting period covers line transaction_date ...".
- An S5 command fails with "S5 posting requires exactly one OPEN accounting period covering the posting date".
- An S7 opening import approval is refused because the posting date is not in an OPEN period.
- A material error is discovered in a period that has already been closed and snapshotted.

## 2. Immediate safety action

- **Do not reopen a period reflexively.** Reopening is a governed act with accounting consequences, and a closed period's snapshot may already be the source of an approved allocation.
- **Do not backdate a correction into the closed period.** The period lock is the control; forcing past it destroys the meaning of the close.
- Establish first whether anything downstream already depends on the closed period's snapshot:

  ```sql
  select id, status, close_snapshot_id, source_period_id
    from public.s5_allocation_runs where source_period_id = :period_id;
  ```

  If an approved allocation exists, the correction plan must be agreed with `<FINANCE_CONTROL_OWNER>` before anything is touched.

## 3. Evidence to preserve

- The period id, version, boundaries, status, and its close run and snapshot ids with the snapshot content hash.
- The target batch id and its full line detail.
- Any allocation runs, distributions or payments that trace to that period's snapshot.
- The customer's document that establishes the correct figure.
- The business justification for correcting a closed period at all, rather than recording the effect in the current open period.

## 4. Diagnosis

```sql
-- Period versions for this project.
select id, version, status, start_date, end_date, supersedes_period_id, opened_by, closed_by
  from public.accounting_periods where project_id = :project_id order by version;

-- The close run, its gates and its snapshot.
select id, version, status, source_cutoff_date, generated_by from public.close_runs
 where period_id = :period_id;
select gate_code, result, detail from public.close_run_gates
 where close_run_id = :close_run_id order by gate_code;
select id, content_hash, captured_at from public.close_run_snapshots
 where close_run_id = :close_run_id;

-- What consumed the snapshot.
select id, status, prepared_at, approved_at from public.s5_allocation_runs
 where close_snapshot_id = :snapshot_id;

-- Existing correction requests for this project.
select * from public.correction_requests_read where project_id = :project_id order by requested_at;
```

Then choose the correct route. **Prefer the first that applies:**

| Situation | Route |
| --- | --- |
| The effect belongs economically in the current period (for example a supplier credit note received now) | Record it normally in the **current open period**. No closed-period correction is needed. |
| A posted fact in the closed period is materially wrong and must be reversed | **Correction workflow** (section 5a). This is the primary supported path. |
| The whole period was closed on materially wrong data and must be re-closed | **Reopen as a new version** (section 5b), then re-close. |
| Only a new *future* posting is blocked | Open the next period; the closed one is not involved. |

## 5. Approved correction path

### 5a. Correction workflow — the primary path

The S6 correction workflow exists exactly for this. It creates a forward, audited, linked reversal; it never edits the closed period.

1. **Request.** Any member may raise it:

   `s6_request_correction(organization_id, project_id, target_batch_id, source_period_id, correction_period_id, reason, evidence_reference)`

   - `source_period_id` is the closed period holding the wrong fact.
   - `correction_period_id` is the current OPEN period where the correcting entry will land.
   - The reason must state what is wrong and why it is material. The evidence reference must point at a real customer document.

2. **Approve.** An OWNER who is not the requester:

   `s6_approve_correction(organization_id, correction_request_id, idempotency_key)`

   If the correction should not proceed, `s6_reject_correction(organization_id, correction_request_id, reason)` records that decision permanently.

3. **Execute.**

   `s6_execute_correction(organization_id, correction_request_id, correction_date, idempotency_key)`

   This posts the linked reversal into the open correction period. The closed period, its snapshot and its content hash are untouched.

4. **Re-record** the correct fact, if there is one, through its ordinary domain command in the open period.

The closed period's reported figures do not change. That is deliberate: a closed period is a published result, and the correction is visible as a subsequent event.

### 5b. Reopen — only when the whole close is invalid

Requires `<FINANCE_CONTROL_OWNER>` and `<CUSTOMER_APPROVER>` agreement, because it can invalidate downstream allocations.

1. Confirm no approved allocation depends on the snapshot, or agree the plan to reverse those allocations first (see [`FAILED_ALLOCATION_OR_DISTRIBUTION.md`](FAILED_ALLOCATION_OR_DISTRIBUTION.md)).
2. Reopen:

   `s6_reopen_period(organization_id, project_id, period_id, reason, evidence_reference)`

   This does **not** modify the closed period. It creates a **new authoritative period version** with `version + 1` that back-points to the superseded one. The closed row stays immutable and its snapshot stays valid as history.
3. Record the corrections in the new open period through ordinary commands.
4. Prepare and approve a new close run for the new period version. Gates are re-evaluated from scratch.
5. Any allocation must now be prepared from the **new** approved snapshot. An allocation prepared from the old snapshot keeps its original source amount by design — a later reopen cannot silently rewrite an allocation's economic input.

## 6. Prohibited shortcuts

- `UPDATE public.accounting_periods SET status = 'OPEN'` — the immutability trigger refuses, and attempting it is a red flag in the audit trail.
- Dropping or disabling the period-lock triggers to force a posting through.
- Backdating a `transaction_date` to fall inside an open period when the event actually occurred in the closed one.
- Editing a close snapshot's `totals` or `content_hash`. The snapshot is immutable; that is what makes it usable as allocation provenance.
- Executing a correction without an approved correction request.
- Using the reopen path to avoid the correction workflow because reopening feels faster.
- Closing the new period with a failing gate waved through outside the recorded close-exception workflow.

## 7. Post-recovery verification

```sql
-- The originally closed period is untouched and still CLOSED.
select id, version, status, start_date, end_date from public.accounting_periods
 where id = :period_id;

-- Its snapshot hash is unchanged.
select id, content_hash from public.close_run_snapshots where period_id = :period_id;

-- The correction is recorded and executed.
select id, status, target_batch_id, source_period_id, correction_period_id,
       requested_by, approved_by, executed_at
  from public.correction_requests_read where id = :correction_request_id;

-- The correcting reversal exists and is linked.
select id, source_type, reversal_of_batch_id, transaction_date
  from public.journal_batches where reversal_of_batch_id = :target_batch_id;

-- Nothing is unbalanced.
select count(*) from (
  select batch_id from public.journal_lines where project_id = :project_id
   group by batch_id having sum(debit_minor_units) <> sum(credit_minor_units)) u;
```

If the period was reopened, verify that the new version supersedes the old one and that only one OPEN period exists for the project and currency.

## 8. Escalation

| Situation | Owner |
| --- | --- |
| Deciding correction vs reopen | `<FINANCE_CONTROL_OWNER>` |
| Any reopen | `<FINANCE_CONTROL_OWNER>` + `<CUSTOMER_APPROVER>` |
| An approved allocation depends on the affected snapshot | `<FINANCE_CONTROL_OWNER>` before any action |
| The period lock behaves unexpectedly | `<ENGINEERING_ONCALL>` |

## 9. Communication

Explain that a closed period is a published result and stays as published; the correction appears as a subsequent, linked, audited event. If a reopen is used, explain that it produces a new period *version* rather than editing the old one, and that both versions remain visible. Never tell a customer their previously reported figures will be silently restated.

## 10. Record

Record: the closed period id and version, the correction request id with its reason and evidence reference, who approved it, the correction date and the resulting reversal batch id, and — if reopened — the new period version id, the new close run and snapshot ids, and the treatment of any dependent allocations.
