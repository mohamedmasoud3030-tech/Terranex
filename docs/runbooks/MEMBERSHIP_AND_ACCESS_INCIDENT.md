# Runbook — Membership and access incident

**Scope:** someone has access they should not have, someone lost access they need, or an organization is at risk of having no active owner.

## 1. Symptom

- A person has left the customer's organisation or changed role, and their Terranex access must end.
- A user reports "غير مصرح" / forbidden where they previously had access.
- A privileged command is refused with "organization owner required".
- An attempt to deactivate a membership is refused with "at least one active owner".
- Credentials are suspected to be shared or compromised.

## 2. Immediate safety action

**If access must be removed, remove it first and investigate afterwards.** Revocation is immediate and safe: it removes read access and blocks privileged commands in the same instant, including for a session that is already open.

```
s7_set_membership_status(organization_id, user_id, 'INACTIVE', reason, idempotency_key)
```

- The actor must be an OWNER. A plain member cannot change any membership status, including their own.
- The reason is mandatory and is recorded in the audit trail.
- The database refuses to leave an organization without at least one active owner. If the refusal appears, appoint or confirm another owner **before** revoking.

If credentials are suspected to be compromised rather than merely stale, also treat this as a security incident: see [`CROSS_TENANT_OR_SECURITY_INCIDENT.md`](CROSS_TENANT_OR_SECURITY_INCIDENT.md).

## 3. Evidence to preserve

- The user id, organization id, previous and new status and role, and the exact time of change.
- Who performed the change, and the reason recorded.
- The audit events for that user in the period of concern, particularly any material command.
- Any facts the user prepared or approved that are now under review.
- Whether the person was a maker or a checker on anything currently in flight.

## 4. Diagnosis

```sql
-- Current access, as the product itself reports it.
select organization_id, user_id, role, status, has_access, status_changed_at, status_reason
  from public.s7_membership_access_read
 where organization_id = :organization_id order by role, user_id;

-- Owner cover: never let this reach zero.
select count(*) from public.memberships
 where organization_id = :organization_id and role = 'OWNER' and status = 'ACTIVE';

-- What did this user actually do?
select occurred_at, event_type, entity_type, entity_id, payload
  from public.audit_events
 where organization_id = :organization_id and actor_id = :user_id
 order by occurred_at desc limit 200;

-- Anything in flight where they are maker or checker.
select id, status, prepared_by, approved_by from public.s5_allocation_runs
 where organization_id = :organization_id and (prepared_by = :user_id or approved_by = :user_id);
select id, status, prepared_by, approved_by from public.s5_distributions
 where organization_id = :organization_id and (prepared_by = :user_id or approved_by = :user_id);
select id, status, prepared_by, approved_by from public.s7_opening_imports
 where organization_id = :organization_id and (prepared_by = :user_id or approved_by = :user_id);
select checkpoint_id, status, prepared_by, signed_off_by from public.s7_reconciliation_checkpoints_read
 where organization_id = :organization_id and (prepared_by = :user_id or signed_off_by = :user_id);

-- Open exceptions owned by this user, which need reassignment by resolution.
select exception_id, severity, status, owner_user_id from public.s7_reconciliation_exceptions_read
 where organization_id = :organization_id and owner_user_id = :user_id and status = 'OPEN';
```

## 5. Approved paths

### 5a. Planned offboarding

1. Confirm owner cover if the leaver is an OWNER: another active OWNER must exist first.
2. Revoke with a reason naming the offboarding.
3. Reassign work in flight. Note that a revoked user's *historical* actions stay attributed to them permanently — that is correct and must not be rewritten.
4. Confirm loss of access with the diagnosis query.

### 5b. Emergency revocation (suspected compromise)

1. Revoke immediately, reason "suspected credential compromise, incident `<ref>`".
2. Notify `<SECURITY_OWNER>` the same hour.
3. Review the user's audit events for material commands in the exposure window.
4. Any material command that was not authorised by a real person is corrected through the ordinary correction paths — see [`INCORRECT_POSTED_TRANSACTION.md`](INCORRECT_POSTED_TRANSACTION.md). It is never deleted.

### 5c. Restoring access

An OWNER re-activates:

```
s7_set_membership_status(organization_id, user_id, 'ACTIVE', reason, idempotency_key)
```

Restoration requires the same justification discipline as revocation. Record who requested it and why.

### 5d. Owner recovery — the organization is about to lose its last owner

The guard prevents this, so the sequence is always: **appoint first, revoke second.**

1. Confirm with `<CUSTOMER_APPROVER>` who the new owner is. Terranex does not choose an owner on the customer's behalf.
2. Ensure that person has an active membership with the OWNER role.
3. Verify with the owner-cover query that at least two active owners exist.
4. Only then revoke the departing owner.

If the organization has *already* lost all human access — for example the sole owner is unreachable — this is an ownership recovery event, not a support action. It requires written authorisation from `<CUSTOMER_APPROVER>` at the customer entity level and is executed by `<SECURITY_OWNER>` with `<ENGINEERING_ONCALL>`, with the authorisation attached to the incident record.

### 5e. A member cannot perform an action they believe they should

Check first whether the refusal is correct:

- Many material actions are OWNER-only by design ("organization owner required").
- Maker/checker refusals are correct even when both people are OWNERs. The preparer of a fact can never approve it.
- A revoked member sees nothing at all; that is not a display bug.

Only if none of these apply is it an engineering question.

## 6. Prohibited shortcuts

- `UPDATE public.memberships SET status = ...` directly. The last-active-owner guard and the audit trail exist for a reason.
- Sharing an owner account so that "someone can approve".
- Creating a second account for the same human to satisfy maker/checker. This is a control failure, not a workaround.
- Revoking the last active owner and planning to fix it afterwards.
- Deleting a membership row to remove access. Revocation is a status change with a reason and a trail.
- Deleting or altering audit events attributed to a departed user.
- Using a service-role key to act "as" a user.

## 7. Post-recovery verification

```sql
-- The intended access state.
select user_id, role, status, has_access, status_reason
  from public.s7_membership_access_read where organization_id = :organization_id order by role, user_id;

-- Owner cover is intact.
select count(*) >= 1 from public.memberships
 where organization_id = :organization_id and role = 'OWNER' and status = 'ACTIVE';

-- Segregation of duties was not weakened anywhere.
select bool_and(prepared_by <> approved_by) from public.s5_allocation_runs
 where organization_id = :organization_id and status = 'APPROVED';
select bool_and(approved_by is null or approved_by <> prepared_by) from public.s5_distributions
 where organization_id = :organization_id;
select bool_and(approved_by is null or approved_by <> prepared_by) from public.s7_opening_imports
 where organization_id = :organization_id;
select bool_and(signed_off_by is null or signed_off_by <> prepared_by)
  from public.s7_reconciliation_checkpoints where organization_id = :organization_id;
```

Have the affected user confirm, from their own session, that they can or cannot see what is intended.

## 8. Escalation

| Situation | Owner |
| --- | --- |
| Routine joiner/leaver | `<PILOT_OPS_OWNER>` |
| Suspected credential compromise | `<SECURITY_OWNER>` immediately |
| Loss of the last active owner | `<SECURITY_OWNER>` + `<CUSTOMER_APPROVER>`, written authorisation required |
| Material commands executed by an unauthorised actor | `<FINANCE_CONTROL_OWNER>` for the corrections, `<SECURITY_OWNER>` for the incident |

## 9. Communication

Tell the customer exactly when access ended and what the user could see or do before that point. If material commands were executed during an exposure window, say so and describe the correction plan. Do not describe historical attribution as something that can be removed — it cannot, and that is a property of an auditable system.

## 10. Record

Record: the user id, the status change with its reason and timestamp, who performed it, the owner-cover position before and after, any work reassigned, any commands reviewed in an exposure window, and the verification output.
