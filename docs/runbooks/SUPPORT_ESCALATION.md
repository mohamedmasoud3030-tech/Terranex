# Runbook — Support escalation

**Scope:** how a report is triaged, how severity is set, who owns it, and when it must be escalated. This runbook is the entry point; the others are the treatments.

## 1. Symptom

Any inbound report from the pilot customer, or any alert from CI or monitoring, that is not already obviously covered by one of the other runbooks.

## 2. Immediate safety action

Before triaging, answer three questions in this order:

1. **Is money or a financial fact affected?** If yes, nothing may be "fixed quickly"; `<FINANCE_CONTROL_OWNER>` is involved from the start.
2. **Is another tenant's data possibly visible?** If yes, stop triaging and go straight to [`CROSS_TENANT_OR_SECURITY_INCIDENT.md`](CROSS_TENANT_OR_SECURITY_INCIDENT.md) and notify `<SECURITY_OWNER>`.
3. **Is access wrongly granted right now?** If yes, revoke first — see [`MEMBERSHIP_AND_ACCESS_INCIDENT.md`](MEMBERSHIP_AND_ACCESS_INCIDENT.md).

Otherwise, capture evidence before changing anything.

## 3. Evidence to preserve

For every report, before any action:

- Who reported it, when, and in their own words.
- The organization, project, and screen or command involved.
- The exact error text, in full. Truncated errors cost hours.
- The time of the event and whether it is reproducible.
- The deployed commit SHA.
- Screenshots, stored in the operator's incident system — never in this repository.

## 4. Triage

### Route to the right runbook

| Report | Runbook |
| --- | --- |
| Opening balances rejected, stuck, or wrong | [`FAILED_OPENING_IMPORT.md`](FAILED_OPENING_IMPORT.md) |
| A posted entry is wrong | [`INCORRECT_POSTED_TRANSACTION.md`](INCORRECT_POSTED_TRANSACTION.md) |
| Bank and Terranex disagree | [`UNRECONCILED_CASH.md`](UNRECONCILED_CASH.md) |
| Allocation or distribution refused or wrong | [`FAILED_ALLOCATION_OR_DISTRIBUTION.md`](FAILED_ALLOCATION_OR_DISTRIBUTION.md) |
| Change needed in a closed period | [`CLOSED_PERIOD_CORRECTION.md`](CLOSED_PERIOD_CORRECTION.md) |
| Access wrong, or owner recovery | [`MEMBERSHIP_AND_ACCESS_INCIDENT.md`](MEMBERSHIP_AND_ACCESS_INCIDENT.md) |
| Suspected cross-tenant or secret exposure | [`CROSS_TENANT_OR_SECURITY_INCIDENT.md`](CROSS_TENANT_OR_SECURITY_INCIDENT.md) |
| Restore, or backup verification | [`BACKUP_AND_RESTORE.md`](BACKUP_AND_RESTORE.md) |
| Release or migration failure | [`FAILED_DEPLOYMENT_OR_MIGRATION.md`](FAILED_DEPLOYMENT_OR_MIGRATION.md) |

### Check whether it is actually correct behaviour

A large share of pilot reports are the product's controls working as designed. Verify before escalating:

| Report | Likely correct behaviour |
| --- | --- |
| "I cannot approve my own entry" | Maker/checker is enforced in the database, even between two OWNERs |
| "I cannot post to that date" | The period is closed; that is the period lock |
| "The import was rejected" | Row validation or control totals; nothing was posted |
| "It will not let me distribute" | Conservative distributable-cash capacity, or no positive allocation |
| "The valuation is not in the result" | Management valuation is deliberately not an accounting fact |
| "The approved distribution is not showing as paid" | Approved payable and paid cash are separate facts |
| "The reversed entry is still visible" | Reversal supersedes; it never erases |
| "UAT is still PENDING after the tests passed" | Automated rehearsals never grant human acceptance |

If the behaviour is correct, the resolution is an explanation, recorded — not a change.

### Severity

| Severity | Definition | Response | Owner |
| --- | --- | --- | --- |
| **S1** | Suspected cross-tenant exposure, credential compromise, or total loss of access to a tenant | Immediate, out of hours | `<SECURITY_OWNER>` |
| **S2** | A posted financial fact is wrong, or cash cannot be reconciled and the customer is acting on the figure | Same business day | `<FINANCE_CONTROL_OWNER>` + `<PILOT_OPS_OWNER>` |
| **S3** | A workflow is blocked but nothing is wrong in the data — refused command, failed import, deployment rollback | Next business day | `<PILOT_OPS_OWNER>` |
| **S4** | Question, usability friction, or documentation gap | Scheduled | `<PILOT_OPS_OWNER>` |

Severity is set on impact, not on customer volume. A calm report of a cross-tenant sighting is S1; an urgent complaint about a refused self-approval is S4.

## 5. Approved handling path

1. **Acknowledge** with a timestamp and the assigned severity.
2. **Preserve evidence** (section 3) before touching anything.
3. **Diagnose read-only.** Every runbook's diagnosis section is read-only by design. Never begin with a write.
4. **Confirm the fix path** with the owner for that severity. Financial corrections require `<FINANCE_CONTROL_OWNER>` authorisation *before* execution, not after.
5. **Execute through product commands only.** Every supported correction in this product is a product command with an actor, a reason, an evidence reference and an idempotency key.
6. **Verify** with the runbook's verification section, and attach the output.
7. **Close** with the record in section 10.

### What a support engineer may do without further authorisation

- Run any read-only diagnostic query in these runbooks.
- Explain correct behaviour to the customer.
- Revoke an access that is confirmed to be wrongly held (containment is always allowed).
- Re-run a rejected import after the customer corrects their file.
- Record a reconciliation checkpoint against evidence the customer has supplied.

### What always requires authorisation

- Any reversal of a posted fact — `<FINANCE_CONTROL_OWNER>`.
- Any period reopen — `<FINANCE_CONTROL_OWNER>` + `<CUSTOMER_APPROVER>`.
- Any restore — `<PILOT_OPS_OWNER>` + `<FINANCE_CONTROL_OWNER>` + `<CUSTOMER_APPROVER>`.
- Any owner recovery — `<SECURITY_OWNER>` + `<CUSTOMER_APPROVER>`.
- Accepting or rejecting a UAT task — only `<CUSTOMER_APPROVER>`, never Terranex staff.

## 6. Prohibited shortcuts

- Any direct SQL write to a posted financial fact, under any pressure.
- Deleting evidence, audit events, or an inconvenient record.
- Marking a UAT task accepted on the customer's behalf. Terranex never grants a human gate.
- Recording a rehearsal, checkpoint, or acceptance result that did not actually happen.
- Telling a customer a gate passed when it was not run.
- Downgrading a security report because it could not be reproduced on first attempt.
- Using shared credentials, or a service-role key, to "get around" a control.
- Closing a ticket with "resolved" and no cause.

## 7. Post-recovery verification

Every escalation closes with:

- The runbook-specific verification output attached.
- Confirmation from the reporter that the observed symptom is gone.
- For anything financial: a reconciliation checkpoint recorded against the customer's own evidence, with zero variance or a documented open exception with a named owner.
- For anything structural: the full gate green on the deployed commit — `npm ci`, lint, typecheck, test, build, `npm run db:test`.

## 8. Escalation ladder

| Step | Trigger | Owner |
| --- | --- | --- |
| 1 | Any report received | `<PILOT_OPS_OWNER>` |
| 2 | Financial fact involved | `<FINANCE_CONTROL_OWNER>` |
| 3 | Access, tenancy, or secrets involved | `<SECURITY_OWNER>` |
| 4 | Code, schema, or infrastructure defect | `<ENGINEERING_ONCALL>` |
| 5 | Customer decision needed on their own data | `<CUSTOMER_APPROVER>` |

Escalate rather than improvise. An unclear situation that stays unresolved for an hour is far cheaper than a wrong write to a financial fact.

## 9. Communication

- State facts, not reassurance. "We have confirmed X, we are still verifying Y."
- Distinguish "reported", "confirmed", and "resolved" in every update.
- Never promise that history will be erased; corrections are forward and visible.
- Never present an automated rehearsal as customer acceptance, or as a production restore.
- Agree the update cadence up front for S1 and S2 and keep to it even when there is no news.

## 10. Record

Every escalation produces a record containing: the report verbatim, severity and who set it, the evidence captured, the diagnosis and the cause, the runbook followed, the authorisations obtained, the exact commands executed with their idempotency keys, the verification output, the customer communication log, and any follow-up work with an owner and a date. If a step could not be completed, the record says so explicitly rather than leaving it implied.
