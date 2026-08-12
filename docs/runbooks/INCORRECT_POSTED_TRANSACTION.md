# Runbook — Incorrect posted transaction

**Scope:** a journal batch has been posted and is materially wrong — wrong amount, wrong party, wrong date, wrong cash account, or it should not exist at all.

## 1. Symptom

- A balance in the workspace does not match what the customer expects, and the difference traces to a specific posted batch.
- A reconciliation checkpoint shows a non-zero variance that traces to one posting.
- The customer reports that an obligation, payment, sale, collection, allocation or distribution was recorded with wrong details.
- A posting exists for a transaction that never happened.

## 2. Immediate safety action

- **Do not attempt to edit the posting.** `journal_batches` and `journal_lines` are immutable by trigger; any attempt fails, and attempting it repeatedly in a live session is noise in the audit trail.
- Establish whether more facts have been recorded on top of the wrong one. Corrections are applied in reverse dependency order, so knowing the dependents comes before deciding anything.
- If the wrong posting materially misstates a balance the customer is acting on (for example a distribution payment), tell `<PILOT_OPS_OWNER>` before the next business action on that project.
- Do not close the current period until the correction is agreed.

## 3. Evidence to preserve

- The batch id, source type, source id, transaction date, posting timestamp, and who posted it.
- The full line detail: account role, debit, credit, currency, party, cash account, obligation.
- The originating domain record (obligation, payment, recognition, collection, allocation run, distribution).
- The audit events for that entity.
- The customer's own document that shows the correct figures, referenced by identifier.

## 4. Diagnosis

```sql
-- The batch and its provenance.
select id, organization_id, project_id, source_type, source_id, transaction_date,
       idempotency_key, reversal_of_batch_id, posted_by, posted_at
  from public.journal_batches where id = :batch_id;

-- Its lines, with semantic roles.
select sa.role, jl.debit_minor_units, jl.credit_minor_units, jl.currency,
       jl.party_id, jl.cash_account_id, jl.obligation_id, jl.transaction_date
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id = jl.account_id
 where jl.batch_id = :batch_id
 order by sa.role;

-- Has it already been reversed?
select id, transaction_date, posted_at from public.journal_batches
 where reversal_of_batch_id = :batch_id;

-- What depends on it: later un-reversed postings in the same project.
select jb.id, jb.source_type, jb.transaction_date, jb.posted_at
  from public.journal_batches jb
 where jb.project_id = :project_id
   and jb.source_type <> 'REVERSAL'
   and jb.posted_at > (select posted_at from public.journal_batches where id = :batch_id)
   and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id)
 order by jb.posted_at;

-- Which period does the transaction date fall in, and is it open?
select id, status, version, start_date, end_date
  from public.accounting_periods
 where project_id = :project_id
   and (select transaction_date from public.journal_batches where id = :batch_id)
       between start_date and end_date
 order by version;

-- The audit trail.
select occurred_at, actor_id, event_type, entity_type, payload
  from public.audit_events
 where organization_id = :organization_id
   and (entity_id = :batch_id or payload->>'journal_batch_id' = :batch_id::text)
 order by occurred_at;
```

Decide, with `<FINANCE_CONTROL_OWNER>`, which of three cases applies:

1. **Not actually wrong** — the customer's expectation was based on a different concept (for example a management valuation, which is deliberately not accounting; or an approved distribution, which is a payable and not paid cash). No correction; explain the distinction.
2. **Wrong, in an open period** — go to 5a.
3. **Wrong, in a closed period** — go to [`CLOSED_PERIOD_CORRECTION.md`](CLOSED_PERIOD_CORRECTION.md).

## 5. Approved correction path

### 5a. Open period

1. Reverse dependents first, newest first. Each reversal uses the product command with a reason and its own idempotency key:

   `reverse_journal_batch(organization_id, batch_id, reason, idempotency_key)`

   The database enforces dependency order for S5 (an allocation cannot be reversed while an approved distribution depends on it; a distribution approval cannot be reversed while a payment depends on it) and for S7 opening positions. If a reversal is refused with a dependency message, that message names what to reverse first.

2. Reverse the wrong batch itself, with a reason that names the incident and the customer's document reference.

3. Re-record the fact correctly through the ordinary domain command — a new obligation, a new payment, a new recognition, a new allocation run — with fresh idempotency keys and correct details. The corrected record is a new fact with its own provenance; the wrong one remains visible.

4. If the original fact should never have existed, stop after step 2. A reversal with no replacement is a legitimate outcome.

### 5b. Special cases

- **Wrong opening balance** → [`FAILED_OPENING_IMPORT.md`](FAILED_OPENING_IMPORT.md) section 5c.
- **Wrong allocation or distribution** → [`FAILED_ALLOCATION_OR_DISTRIBUTION.md`](FAILED_ALLOCATION_OR_DISTRIBUTION.md).
- **Cash recorded that the bank never moved** → this is a Terranex-side correction *and* a reconciliation problem; also follow [`UNRECONCILED_CASH.md`](UNRECONCILED_CASH.md). Terranex records the customer's banking process; it does not execute payments, so a reversal here never moves money.

## 6. Prohibited shortcuts

- `UPDATE public.journal_lines ...` or `UPDATE public.journal_batches ...` for any reason.
- `DELETE` of a batch, a line, or a domain record.
- Posting a manual "adjustment" batch by direct `INSERT` instead of using a domain command.
- Reversing in the wrong order to get past a dependency error, or disabling the dependency trigger.
- Backdating a correction into a closed period to avoid the correction workflow.
- Recording a reversal without a reason, or with a reason like "error".

## 7. Post-recovery verification

```sql
-- The wrong batch is reversed exactly once.
select count(*) from public.journal_batches where reversal_of_batch_id = :batch_id;

-- Nothing is unbalanced.
select count(*) from (
  select batch_id from public.journal_lines
   where project_id = :project_id group by batch_id
  having sum(debit_minor_units) <> sum(credit_minor_units) or count(*) < 2) u;

-- The derived positions now read what the customer expects.
select * from public.project_cash_position_read where project_id = :project_id;
select * from public.s5_partner_capital_statement_read where project_id = :project_id;
```

Record the relevant reconciliation checkpoint and confirm zero variance, or open an exception with an owner if a residual difference remains.

## 8. Escalation

| Situation | Owner |
| --- | --- |
| Any reversal of a posted fact | `<FINANCE_CONTROL_OWNER>` approves before execution |
| Customer disputes which figure is correct | `<CUSTOMER_APPROVER>` decides; Terranex does not choose for them |
| The target period is closed | `<FINANCE_CONTROL_OWNER>` via the correction workflow |
| A reversal is refused and the message is not understood | `<ENGINEERING_ONCALL>` |

## 9. Communication

Explain that the wrong entry is not erased: it is reversed and superseded, and both are visible. That is a feature of an auditable subledger. Give the customer the corrected balance and the reference of the correcting entry. Never promise that the original will disappear from history.

## 10. Record

Record: the wrong batch id, why it was wrong, who authorised the reversal, the reversal batch id, the ids of any dependents reversed first, the corrected record's id, and the verification output.
