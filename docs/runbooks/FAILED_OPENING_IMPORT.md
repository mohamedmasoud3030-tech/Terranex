# Runbook — Failed opening balance import

**Scope:** an opening-balance import for a Real Estate project fails validation, is stuck in a state, is rejected, or has been posted with wrong content.

## 1. Symptom

One of:

- Validation returns `FAILED` and the workspace shows rejected rows with reasons.
- Validation returns `FAILED` because computed control totals do not equal the declared totals.
- Approval is refused: "only an opening import that is ready for approval can be approved", "opening import is already posted", or the maker/checker refusal.
- Approval is refused because the project already has an active posted opening position.
- Approval is refused because the posting date is not inside exactly one `OPEN` accounting period.
- The import posted successfully but the customer says the opening figures are wrong.

## 2. Immediate safety action

- **Nothing has been posted unless the import status is `POSTED`.** `DRAFT`, `VALIDATED`, `READY_FOR_APPROVAL`, `REJECTED` and `FAILED` have no accounting effect. There is no emergency.
- Stop retrying the import with new idempotency keys. Repeated staging with different keys creates a trail of dead imports and makes diagnosis harder.
- If the import is already `POSTED` and is wrong, **stop all further posting on that project** until section 5c is agreed. Later postings on top of a wrong opening position make the correction harder, because the reversal guard will refuse while dependent later postings exist.

## 3. Evidence to preserve

- The import id, its idempotency key, its status, and the source file name and checksum.
- The source file itself, kept in the customer's own document store. It is referenced by checksum; it is never committed to this repository.
- The full rejected-row list with reasons and row numbers.
- The declared vs computed control totals and both variances.
- The mapping summary and rejection summary.
- The audit events for the import (`S7_OPENING_IMPORT_*`).

## 4. Diagnosis

Read-only. Substitute the import id.

```sql
-- Headline state, control totals, and variances.
select id, status, source_file_name, source_file_checksum, schema_version,
       row_count, accepted_row_count, rejected_row_count,
       declared_debit_total_minor_units, computed_debit_total_minor_units, debit_variance_minor_units,
       declared_credit_total_minor_units, computed_credit_total_minor_units, credit_variance_minor_units,
       failure_reason, prepared_by, approved_by, journal_batch_id
  from public.s7_opening_imports_read where import_id = :import_id;

-- Exactly which rows were rejected and why.
select row_number, mapping_code, status, rejection_reason, debit_minor_units, credit_minor_units
  from public.s7_opening_import_rows_read
 where import_id = :import_id and status = 'REJECTED'
 order by row_number;

-- What the file mapped to, in aggregate.
select mapping_summary, rejection_summary
  from public.s7_opening_imports_read where import_id = :import_id;

-- The locked mapping registry. Only these six codes exist.
select mapping_code, semantic_role, expected_side, requires_party, requires_cash_account
  from public.s7_opening_mapping_codes_read order by mapping_code;

-- Period state, if approval was refused on the posting date.
select id, status, version, start_date, end_date
  from public.accounting_periods where project_id = :project_id order by version;

-- Is there already an active posted opening position on this project?
select i.id, i.status, i.journal_batch_id,
       exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id = i.journal_batch_id) as is_reversed
  from public.s7_opening_imports i
 where i.project_id = :project_id and i.status = 'POSTED';
```

### Interpreting the twelve rejection reasons

| Reason | What it means | Fix in the source file |
| --- | --- | --- |
| `UNKNOWN_MAPPING_CODE` | The code is not one of the six registered codes | Use a registered code; the registry is locked and is not extended for one customer |
| `PARTY_REQUIRED` | The mapping needs a counterparty and none was given | Supply the party |
| `PARTY_NOT_ALLOWED` | A party was given for a mapping that has none | Remove the party |
| `PARTY_NOT_IN_ORGANIZATION` | The party belongs to another tenant | Create/select the correct party in this organization |
| `CASH_ACCOUNT_REQUIRED` | Opening bank cash needs a project cash account | Supply the cash account |
| `CASH_ACCOUNT_OUT_OF_SCOPE` | The cash account is not this project's | Use a cash account of this project |
| `INVALID_AMOUNT` | The amount is not a valid integer minor-unit value | Correct the amount; no thousands separators, no decimals beyond the currency's minor unit |
| `BOTH_SIDES_SET` | Both debit and credit are non-zero on one row | Split into two rows |
| `NO_AMOUNT` | Both sides are zero | Remove the row or supply an amount |
| `SIDE_CONTRADICTS_MAPPING` | E.g. a credit on a debit-side mapping | Put the amount on the side the mapping requires |
| `DUPLICATE_ROW_IN_FILE` | Two rows are identical in every material field | Merge them, or make the descriptions genuinely distinguish them |
| `DESCRIPTION_INVALID` | Missing, too long, or contains control characters | Supply a clean description |

### Interpreting a control-total mismatch

A mismatch means the declared totals disagree with the sum of **accepted** rows. Almost always one of:

- rows were rejected, so accepted rows no longer sum to the declared totals — fix the rejected rows first;
- the declared totals were transcribed from a different version of the file;
- debits and credits genuinely do not balance in the source, which is a bookkeeping problem in the customer's own opening trial balance and must be resolved by them before import.

Terranex will not post an unbalanced opening position and will not "plug" a difference.

## 5. Approved correction path

### 5a. The import is not posted (`DRAFT`, `VALIDATED`, `READY_FOR_APPROVAL`, `FAILED`)

1. Reject the bad import explicitly so the trail is honest:

   `s7_reject_opening_import(organization_id, import_id, reason, idempotency_key)`

   A reason is mandatory. "Retry" is not a reason; state what was wrong.
2. Correct the source file in the customer's own system.
3. Stage a fresh import with the corrected file, its new checksum, and a **new** idempotency key.
4. Validate, review, then have a **different** person approve. The database refuses self-approval.

Note on retries: re-staging with the *same* idempotency key and the *same* payload is safe and returns the same import. Re-staging with the same key and a *different* payload is refused as an idempotency payload mismatch — that is the system protecting you from a silent substitution, not a bug.

### 5b. The import is posted and correct, but a *second* opening position is needed

There is no such thing. A project holds at most one active opening position. If the customer needs to change it, that is 5c.

### 5c. The import is posted and materially wrong

This requires `<FINANCE_CONTROL_OWNER>` approval and the customer's written confirmation of the corrected figures.

1. Establish the dependency order. The database will refuse to reverse the opening batch while any un-reversed, non-reversal batch was posted later in that project:

   ```sql
   select jb.id, jb.source_type, jb.transaction_date, jb.posted_at
     from public.journal_batches jb
    where jb.project_id = :project_id
      and jb.source_type <> 'REVERSAL'
      and jb.posted_at > (select posted_at from public.journal_batches where id = :opening_batch_id)
      and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id)
    order by jb.posted_at;
   ```

2. Reverse the dependents in reverse chronological order, each through its own product path (`reverse_journal_batch`, or the S6 correction workflow if the target period is closed). Every reversal carries a reason and an idempotency key.
3. Reverse the opening batch itself with `reverse_journal_batch`, giving a reason that names the incident.
4. Stage, validate, review and approve a corrected opening import as in 5a. The corrected import is a new record; the wrong one stays visible as history.
5. Re-post the dependent facts that are still valid, through their ordinary product commands.

If the posting date now falls in a closed period, follow [`CLOSED_PERIOD_CORRECTION.md`](CLOSED_PERIOD_CORRECTION.md) instead of trying to force the date.

## 6. Prohibited shortcuts

- `UPDATE public.s7_opening_imports SET status = ...` — the transition guard exists precisely to stop this.
- `DELETE` of an import, an import row, or its journal batch.
- Editing `journal_lines` to "adjust" an opening balance to the right number.
- Adding a manual balancing row to make control totals agree.
- Extending the mapping-code registry to accommodate one customer's chart of accounts. The registry is locked by trigger and is Real-Estate specific by design.
- Having the same person stage and approve by switching accounts.
- Re-using the approval idempotency key of a different import.

## 7. Post-recovery verification

```sql
-- Exactly one active posted opening position, with matching control totals.
select id, status, control_totals_match, is_reversed, rejected_row_count
  from public.s7_opening_imports_read where project_id = :project_id;

-- The opening batch balances.
select sum(debit_minor_units), sum(credit_minor_units)
  from public.journal_lines where batch_id = :journal_batch_id;

-- Maker is not the approver.
select prepared_by <> approved_by from public.s7_opening_imports where id = :import_id;
```

Then record a `PROJECT_CASH` reconciliation checkpoint against the customer's opening bank evidence and confirm zero variance. Confirm the project cash position and partner capital statement read the values the customer expects.

## 8. Escalation

| Situation | Owner |
| --- | --- |
| Rejected rows only | `<PILOT_OPS_OWNER>` with the customer's finance contact |
| Control totals disagree in the customer's own trial balance | `<CUSTOMER_APPROVER>` — this is their bookkeeping to resolve |
| Any reversal of a posted opening position | `<FINANCE_CONTROL_OWNER>` |
| Import command errors that are not validation errors | `<ENGINEERING_ONCALL>` |

## 9. Communication

Say plainly whether anything was posted. If nothing was posted, say so: a failed validation is the control working, not a data-loss event. If a posted opening position must be reversed, explain that the wrong figures remain visible as history and the correction is a new record — this is deliberate and auditable, not an inability to delete.

## 10. Record

Record: the import id and file checksum, the rejection reasons or the control-total variance, what was changed in the source file, the new import id, who approved it, and the reconciliation checkpoint that proved the corrected opening position.
