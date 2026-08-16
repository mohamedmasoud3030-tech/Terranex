# Runbook — Failed allocation or distribution

**Scope:** an allocation run or a distribution cannot be prepared, approved or paid, or one of them was approved with wrong content.

> **Pre-owner policy-safety (2026-08-16):** S5 allocation/distribution is
> **policy-inert** until an approved `policy_authority` exists (ADR 0033). The
> expected first refusal for an unactivated tenant is now
> `target-company investor policy is not activated` — that is correct behavior,
> not a defect. This runbook covers the mechanism once policy is (later) approved.

## 1. Symptom

Preparation or approval is refused with one of:

- "target-company investor policy is not activated" (policy not approved — expected)
- "allocation requires an approved S6 close snapshot"
- "allocation rules are not configured for the governing version"
- "closed snapshot contains no allocable real-estate sale result"
- "allocation weights must resolve exactly to 100 percent"
- "S5 posting requires exactly one OPEN accounting period covering the posting date"
- a maker/checker constraint violation (`s5_allocation_run_maker_checker_check` or `s5_distribution_maker_checker_check`)
- "distribution requires an approved allocation run"
- "participant has no positive allocation in this run"
- "requested distribution exceeds participant capital available"
- "requested distribution exceeds project distributable cash"
- "distribution payment exceeds approved outstanding payable"
- "distribution payment exceeds cash account balance"

Or: the run/distribution posted, and the investor statement is wrong.

## 2. Immediate safety action

- A refused preparation or approval has **posted nothing**. There is no financial exposure. Do not retry with new keys until the cause is understood.
- If a distribution has been **approved**, the customer now has a recorded payable. If it is wrong, stop before it is paid — reversing an approval is much simpler than unwinding a payment.
- If a distribution has been **paid** in Terranex, remember that Terranex records the customer's banking process; it does not move money. Check with the customer whether the bank transfer actually happened before deciding what to correct.

## 3. Evidence to preserve

- The allocation run id, its close snapshot id, snapshot content hash, source amount, rule set id, and status.
- The rule set weights and the basis evidence reference.
- The distribution id, requested and approved amounts, status, and settlement status.
- The exact error text and the actor who received it.
- The investor statement rows for the affected participants.

## 4. Diagnosis

```sql
-- The allocation run and its frozen provenance.
select id, status, source_period_id, close_run_id, close_snapshot_id, snapshot_content_hash,
       governing_version_id, rule_set_id, policy, algorithm_version, source_category,
       source_amount_minor_units, prepared_by, approved_by, posting_date, journal_batch_id
  from public.s5_allocation_runs where id = :run_id;

-- The deterministic lines.
select participant_party_id, weight_numerator, weight_denominator,
       exact_floor_minor_units, rounding_award_minor_units, allocated_minor_units
  from public.s5_allocation_lines where run_id = :run_id order by participant_party_id;

-- Are the stored lines still the canonical result?
select public.s5_allocation_lines_are_canonical(:run_id);

-- The frozen rule set and its basis.
select * from public.s5_rule_sets_read where project_id = :project_id;

-- Is there an approved close snapshot at all?
select s.id, s.content_hash, s.captured_at, c.status
  from public.close_run_snapshots s
  join public.close_runs c on c.id = s.close_run_id
 where s.project_id = :project_id order by s.captured_at;

-- Period state for the intended posting date.
select id, status, version, start_date, end_date
  from public.accounting_periods where project_id = :project_id order by version;

-- Distribution state and settlement.
select * from public.s5_distributions_read where project_id = :project_id order by prepared_at;

-- Capacity: what the database will actually allow.
select * from public.s5_distribution_capacity_read where project_id = :project_id;

-- The investor statement.
select * from public.s5_partner_capital_statement_read where project_id = :project_id;
```

### Cause table

| Error | Real cause | Path |
| --- | --- | --- |
| requires an approved S6 close snapshot | The period was never closed, or the close run is not APPROVED | Close the period properly first |
| rules are not configured | No frozen rule set for that governing agreement version | Configure rules (OWNER) before preparing |
| no allocable real-estate sale result | The closed period genuinely contains no recognized sale result | Nothing to allocate; this is correct |
| weights must resolve exactly | Numerators do not sum to the denominator | Fix the weights; they come from the governing schedule, not from commitments |
| exactly one OPEN period | The posting date is in a closed period or no period covers it | Reopen or open the correct period; see [`CLOSED_PERIOD_CORRECTION.md`](CLOSED_PERIOD_CORRECTION.md) |
| maker/checker constraint | The same person prepared and approved | A different authorised person approves. Never share credentials |
| no positive allocation in this run | That investor received zero or a loss allocation | A distribution to them is not supported; this is correct |
| exceeds participant capital available | The request is larger than that investor's capital balance | Reduce the request, or investigate the capital position |
| exceeds project distributable cash | Bank cash less supplier payables less distribution payables is insufficient | Do not distribute; this is a deliberate conservative capacity rule |
| payment exceeds outstanding payable | Over-payment attempt, often a duplicate | Check for an existing payment before retrying |
| payment exceeds cash account balance | The account does not hold the cash | Correct the account, or the cash position is wrong — see [`UNRECONCILED_CASH.md`](UNRECONCILED_CASH.md) |

Note on the distinction the customer most often disputes: **allocation is not a payable, an approved distribution is not paid cash, and paid cash is not a bank transfer executed by Terranex.** These are four separate facts on purpose.

## 5. Approved correction path

### 5a. Nothing posted (preparation or approval refused)

Fix the precondition named in the cause table and retry with the same idempotency key if the payload is unchanged, or a new key if the payload changed. A refused command left no record to clean up.

### 5b. Wrong rule set, before any allocation used it

Configure a corrected rule set through `s5_configure_allocation_rules` (OWNER, with a basis evidence reference). Rule rows are append-only and cannot be edited; a corrected configuration is a new frozen basis.

If a run has already used the wrong basis, that run must be reversed first — 5c.

### 5c. Allocation approved and posted, but wrong

Requires `<FINANCE_CONTROL_OWNER>` approval.

1. Reverse dependents first. The database refuses to reverse an allocation journal while an active approved distribution depends on it, and refuses to reverse a distribution approval while an active payment depends on it. Work in this order:
   - distribution payments → distribution approvals → allocation journal.
   - each via `reverse_journal_batch(organization_id, batch_id, reason, idempotency_key)`.
2. Correct the underlying cause (usually the rule set, occasionally the close snapshot if the period itself was closed on wrong data — then follow [`CLOSED_PERIOD_CORRECTION.md`](CLOSED_PERIOD_CORRECTION.md)).
3. Prepare a new allocation run from the correct approved snapshot and the corrected rule set, with a new idempotency key.
4. Have a different authorised person approve it.
5. Re-prepare, re-approve and, if appropriate, re-pay the distributions.

### 5d. Distribution paid in Terranex but the bank transfer never happened

1. Confirm with the customer in writing that no money moved.
2. Reverse the payment batch with a reason naming the confirmation.
3. The payable returns to outstanding. Do not reverse the approval unless the distribution itself is being cancelled.

### 5e. Bank transfer happened but Terranex has no payment

Record the payment through `s5_pay_distribution` with the bank evidence reference. If the amount exceeds the approved payable, do not force it: investigate whether the customer paid the wrong amount, which is a finance matter for `<CUSTOMER_APPROVER>`.

## 6. Prohibited shortcuts

- Editing `s5_allocation_lines` to change an investor's share.
- Editing `s5_distributions` status or amounts.
- Recomputing an allocation in a spreadsheet and posting the result manually.
- Using commitment amounts as allocation weights because the rule set is inconvenient to configure. Commitments identify who is eligible; they are not entitlement weights.
- Reversing in an order that avoids a dependency error by disabling a trigger.
- Approving one's own preparation via a second account.
- Distributing beyond the conservative distributable-cash rule by adjusting a cash figure.

## 7. Post-recovery verification

```sql
-- Allocation totals exactly to the source amount, and lines are canonical.
select sum(allocated_minor_units) from public.s5_allocation_lines where run_id = :run_id;
select public.s5_allocation_lines_are_canonical(:run_id);

-- Maker/checker held.
select prepared_by <> approved_by from public.s5_allocation_runs where id = :run_id;
select approved_by is null or approved_by <> prepared_by from public.s5_distributions where id = :distribution_id;

-- The rollforward reconciles exactly for every investor.
select participant_party_id,
       closing_capital_minor_units::bigint =
         opening_capital_minor_units::bigint + contributions_minor_units::bigint
       + allocated_income_minor_units::bigint - allocated_loss_minor_units::bigint
       - approved_distributions_minor_units::bigint as reconciles
  from public.s5_partner_capital_statement_read where project_id = :project_id;
```

Then record `PARTNER_CAPITAL`, `DISTRIBUTION_PAYABLE`, `DISTRIBUTION_PAID` and `INVESTOR_STATEMENT_TOTAL` reconciliation checkpoints against the customer's own records and confirm zero variance.

## 8. Escalation

| Situation | Owner |
| --- | --- |
| Precondition failure, nothing posted | `<PILOT_OPS_OWNER>` |
| Rule set weights disputed | `<CUSTOMER_APPROVER>` — the governing schedule is theirs |
| Any reversal of an approved allocation or distribution | `<FINANCE_CONTROL_OWNER>` |
| Terranex and the bank disagree about whether a distribution was paid | `<PILOT_OPS_OWNER>` + `<CUSTOMER_APPROVER>` same day |

## 9. Communication

Be precise about which of the four states applies: allocated, approved payable, recorded as paid, actually transferred by the bank. Most disputes in this area are a confusion between them. If a capacity rule blocked a distribution, explain it as a deliberate conservative control — Terranex will not let a project distribute cash it has already committed to suppliers or to other approved payables.

## 10. Record

Record: the run and distribution ids, the exact refusal text or the error in the posted content, what was reversed and in what order, the corrected rule set/run ids, who approved each step, and the reconciliation checkpoints that closed the incident.
