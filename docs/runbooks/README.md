# Terranex operational runbooks

These runbooks are the operator-facing procedures for the controlled Real Estate pilot delivered by GF-009 / S7. They are written for a support or operations engineer working a live incident, not for a developer reading source code.

## How to use a runbook

Every runbook follows the same ten sections:

1. **Symptom** — what the operator or the customer actually observes.
2. **Immediate safety action** — what to do first so the situation cannot get worse.
3. **Evidence to preserve** — what must be captured *before* anything is changed.
4. **Diagnosis** — read-only queries and checks that establish what really happened.
5. **Approved correction path** — the only supported way to fix it, always through product commands.
6. **Prohibited shortcuts** — actions that are never acceptable, whatever the pressure.
7. **Post-recovery verification** — the checks that prove the system is correct again.
8. **Escalation** — who owns the next step.
9. **Communication** — what the customer is told, and what must never be promised.
10. **Record** — what has to be written down afterwards.

## Standing rules that override any individual runbook

- **Never edit a posted financial fact with SQL.** Journal batches and journal lines are immutable by database trigger. Corrections are made with the product's linked reversal and correction commands, never with `UPDATE` or `DELETE`. A runbook that appears to require destructive SQL on posted facts is a defect in the runbook; escalate instead.
- **Never delete evidence.** Opening imports, reconciliation checkpoints, exceptions, UAT tasks, rehearsal records and audit events are append-only by design. If something is wrong, add a corrective record; do not remove the wrong one.
- **Never bypass maker/checker.** If the only available person is the maker, the action waits. Segregation of duties is enforced in the database and must not be worked around by sharing credentials or reassigning ownership mid-incident.
- **Never use a service-role key from a browser or from a support session.** All operator actions go through the application or through an authenticated database session bound to a real user id.
- **Never claim a gate that did not run.** If a verification step could not be executed, the incident record says so explicitly.
- **Real customer data never enters this repository.** Evidence references are identifiers (ticket numbers, document references, file names); the documents themselves live in the customer's own systems.

## Escalation owners

Owner names are deliberately left as placeholders. They are filled in per engagement, in the customer-facing operations plan, not in this repository.

| Role | Placeholder | Responsible for |
| --- | --- | --- |
| Pilot operations owner | `<PILOT_OPS_OWNER>` | First response, customer communication, incident record |
| Finance control owner | `<FINANCE_CONTROL_OWNER>` | Any correction that touches a posted financial fact |
| Engineering on-call | `<ENGINEERING_ONCALL>` | Migration, deployment, and database-level faults |
| Security owner | `<SECURITY_OWNER>` | Access, tenancy, and suspected data-exposure incidents |
| Customer authorised approver | `<CUSTOMER_APPROVER>` | Accepting or rejecting any UAT task; approving corrections on their own data |

## Index

| Runbook | Use when |
| --- | --- |
| [`FAILED_OPENING_IMPORT.md`](FAILED_OPENING_IMPORT.md) | An opening balance import is rejected, stuck, or posted wrong |
| [`INCORRECT_POSTED_TRANSACTION.md`](INCORRECT_POSTED_TRANSACTION.md) | A posted journal is materially wrong |
| [`UNRECONCILED_CASH.md`](UNRECONCILED_CASH.md) | Bank cash does not agree with Terranex |
| [`FAILED_ALLOCATION_OR_DISTRIBUTION.md`](FAILED_ALLOCATION_OR_DISTRIBUTION.md) | An allocation or distribution fails, or is approved wrong |
| [`CLOSED_PERIOD_CORRECTION.md`](CLOSED_PERIOD_CORRECTION.md) | Something must change in a period that is already closed |
| [`MEMBERSHIP_AND_ACCESS_INCIDENT.md`](MEMBERSHIP_AND_ACCESS_INCIDENT.md) | Someone has access they should not, or lost access they need |
| [`CROSS_TENANT_OR_SECURITY_INCIDENT.md`](CROSS_TENANT_OR_SECURITY_INCIDENT.md) | Suspected data exposure across organizations |
| [`BACKUP_AND_RESTORE.md`](BACKUP_AND_RESTORE.md) | Backup verification, or a real restore is being considered |
| [`FAILED_DEPLOYMENT_OR_MIGRATION.md`](FAILED_DEPLOYMENT_OR_MIGRATION.md) | A release or database migration failed |
| [`SUPPORT_ESCALATION.md`](SUPPORT_ESCALATION.md) | Deciding severity, ownership, and when to escalate |
