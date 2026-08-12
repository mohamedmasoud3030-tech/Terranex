# Runbook — Unreconciled cash

**Scope:** the customer's bank position and the Terranex project cash position do not agree, or bank statement lines remain unreconciled at close.

## 1. Symptom

- A `PROJECT_CASH` reconciliation checkpoint records a non-zero variance and opens an exception.
- The `BANK_RECONCILIATION_COVERAGE` close gate FAILs with unreconciled statement lines.
- The customer says the bank balance and the Terranex cash balance differ.
- A payment or collection exists in Terranex with no matching bank line, or vice versa.

## 2. Immediate safety action

- **Do not adjust the Terranex balance to match the bank.** There is no command to write a cash balance directly, and there must never be one. A variance is information; it is not something to erase.
- **Do not close the period** while the variance is unexplained. The close gate failing is the control working.
- If the variance suggests money left the customer's bank account without a corresponding Terranex record, treat it as potentially urgent and notify `<PILOT_OPS_OWNER>` and the customer's finance contact the same day.
- Do not resolve the reconciliation exception until the cause is understood. Resolution is a documented act, not a way to clear a red indicator.

## 3. Evidence to preserve

- The bank statement covering the period, referenced by the customer's own document identifier.
- The checkpoint id, as-of date, external value, Terranex value, and exact integer variance.
- The exception id, severity, and owner.
- The list of unreconciled statement lines and unmatched Terranex payments/collections.
- The period boundaries used for the comparison — a large "variance" is often a cut-off difference.

## 4. Diagnosis

```sql
-- The checkpoint and its exact variance.
select checkpoint_id, checkpoint_code, as_of_date, external_value_minor_units,
       terranex_value_minor_units, variance_minor_units, status, is_zero_variance,
       external_source_reference, external_evidence_reference
  from public.s7_reconciliation_checkpoints_read
 where project_id = :project_id and checkpoint_code = 'PROJECT_CASH'
 order by as_of_date desc;

-- The open exception.
select exception_id, severity, status, owner_user_id, variance_minor_units, detail, raised_at
  from public.s7_reconciliation_exceptions_read
 where project_id = :project_id and status = 'OPEN';

-- Bank statement lines that are not reconciled.
select * from public.bank_statement_line_status_read
 where project_id = :project_id and not is_reconciled
 order by transaction_date;

-- The Terranex cash position, by account.
select * from public.project_cash_position_read where project_id = :project_id;

-- Every cash movement in the window, with its source.
select jb.source_type, jb.transaction_date, jl.debit_minor_units, jl.credit_minor_units,
       jl.cash_account_id, jb.id as batch_id
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'BANK_CASH'
 where jl.project_id = :project_id
   and jl.transaction_date between :from_date and :to_date
 order by jl.transaction_date, jb.posted_at;
```

Work through the causes in order — most variances are the first three:

| Cause | Signature | Resolution |
| --- | --- | --- |
| **Cut-off** | Variance equals one or more movements dated just outside the as-of date | Re-record the checkpoint at the correct as-of date. Not an error. |
| **Timing** | A payment is recorded in Terranex but has not cleared the bank, or vice versa | Document it as a reconciling item; it resolves itself when the item clears |
| **Missing bank line** | A statement line was never imported | Import the statement lines and reconcile |
| **Missing Terranex fact** | Money moved and was never recorded | Record it through the proper command (payment, collection, contribution attribution) |
| **Wrong amount** | A single posting differs from the bank by the exact variance | [`INCORRECT_POSTED_TRANSACTION.md`](INCORRECT_POSTED_TRANSACTION.md) |
| **Wrong project or account** | Cash landed on the wrong project cash account | Reverse and re-record on the correct account |
| **Bank error** | The customer's own bank shows a movement they did not make | The customer raises it with their bank; Terranex records the eventual outcome |

## 5. Approved correction path

1. **Classify the variance.** Every minor unit must be attributed to one of the causes above. A residual "unexplained" amount is never rounded away.

2. **Import any missing statement lines** with the existing bank statement import, which fingerprints lines and rejects duplicates:

   `import_bank_statement_lines(organization_id, cash_account_id, dates[], amounts[], currencies[], descriptions[], references[], idempotency_key)`

3. **Reconcile matched lines** using the existing reconciliation commands for payments and for property sale collections. Terranex reconciles one statement line to one allocation; it deliberately does not implement fuzzy or many-to-many matching.

4. **Record genuinely missing facts** through their domain commands, never as a bare journal entry.

5. **Correct wrong facts** through reversal and re-recording — see [`INCORRECT_POSTED_TRANSACTION.md`](INCORRECT_POSTED_TRANSACTION.md).

6. **Resolve the reconciliation exception** only once the variance is explained, using:

   `s7_resolve_reconciliation_exception(organization_id, exception_id, resolution, evidence_reference, idempotency_key)`

   The resolution text must state the cause and the corrective action, and the evidence reference must point at a real document. "Resolved" alone is not acceptable.

7. **Record a fresh checkpoint** at the same as-of date after correction. The earlier checkpoint stays: it is the record that a variance existed. A new checkpoint with zero variance is the record that it was fixed.

8. **Sign off** the zero-variance checkpoint with `s7_sign_off_reconciliation_checkpoint`. The signer must not be the person who recorded it; the database enforces this.

9. If the close gate was failing and a residual reconciling item is legitimate and immaterial, the only supported path to close is the audited close-exception workflow (`s6_request_close_run_exception` then `s6_approve_close_run_exception`) with a materiality comment — never an unconditional pass.

## 6. Prohibited shortcuts

- Any direct write to a cash balance. There is no such column; the balance is derived.
- Posting a plug entry to make the two numbers agree.
- Resolving the exception without an explanation and an evidence reference.
- Signing off a checkpoint that still has an open exception (the database refuses this, correctly).
- Approving a close run with a failing bank gate by any route other than the recorded exception workflow.
- Deleting or re-importing statement lines to make a duplicate disappear — the fingerprint rejection is the control working.
- Treating an approved distribution as paid cash. They are separate facts by design.

## 7. Post-recovery verification

```sql
-- A current zero-variance, signed-off cash checkpoint exists.
select checkpoint_code, as_of_date, variance_minor_units, status, open_exception_count
  from public.s7_reconciliation_checkpoints_read
 where project_id = :project_id and checkpoint_code = 'PROJECT_CASH'
 order by as_of_date desc limit 1;

-- No unreconciled lines remain in the period.
select count(*) from public.bank_statement_line_status_read
 where project_id = :project_id and not is_reconciled;

-- No open exceptions.
select count(*) from public.s7_reconciliation_exceptions_read
 where project_id = :project_id and status = 'OPEN';
```

Re-run the close gate evaluation and confirm `BANK_RECONCILIATION_COVERAGE` now PASSes on its own merits.

## 8. Escalation

| Situation | Owner |
| --- | --- |
| Variance explained as timing or cut-off | `<PILOT_OPS_OWNER>` |
| Variance requires reversing a posted fact | `<FINANCE_CONTROL_OWNER>` |
| Money left the bank with no authorised Terranex record | `<PILOT_OPS_OWNER>` immediately, then `<CUSTOMER_APPROVER>`; treat as potential fraud until shown otherwise |
| Bank statement data appears to belong to another customer | `<SECURITY_OWNER>` — see [`CROSS_TENANT_OR_SECURITY_INCIDENT.md`](CROSS_TENANT_OR_SECURITY_INCIDENT.md) |

## 9. Communication

Give the exact integer variance and the classification of every component of it. Do not describe a variance as "a system error" before it is diagnosed — in this product the most common causes are cut-off and timing, both of which are correct behaviour. Never tell a customer a variance was "cleared" when it was only resolved administratively.

## 10. Record

Record: the checkpoint id and variance, the classification of every component, what was imported/reconciled/corrected, the exception resolution text and evidence reference, the new zero-variance checkpoint id, and who signed it off.
