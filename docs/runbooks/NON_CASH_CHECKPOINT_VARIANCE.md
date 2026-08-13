# Runbook — Non-cash reconciliation checkpoint variance

**Scope:** an S7 reconciliation checkpoint **other than bank cash** records a non-zero variance: `CONTRIBUTED_CAPITAL`, `SUPPLIER_OBLIGATION_POSITION`, `CUSTOMER_RECEIVABLE_POSITION`, `DISTRIBUTION_PAYABLE`, `DISTRIBUTION_PAID`, `PARTNER_CAPITAL`, or `REALIZED_RESULT`. (Bank/book cash variance is `PROJECT_CASH` and belongs to `UNRECONCILED_CASH.md`.)

**Core semantics (S7):** the Terranex side is derived inside PostgreSQL from posted journal lines; the external number is **evidence only** and never influences a Terranex balance. `variance = external − terranex` is an exact integer. A non-zero variance creates a mandatory visible exception with an owner and severity. Checkpoints are immutable from the moment of recording: **correction means recording a NEW checkpoint, never editing the old one.** Sign-off is maker/checker and is refused while an exception is open.

## 1. Symptom

- A checkpoint is recorded with status `VARIANCE` and a non-zero `variance_minor_units`.
- The pilot workspace shows an open reconciliation exception tied to a checkpoint.
- A weekly reconciliation (per the pilot reconciliation procedures) cannot be signed off.

## 2. Immediate safety action

1. Do not sign off the checkpoint — the product refuses while the exception is open; do not look for a way around that.
2. Do not re-record the same checkpoint with a different external number "to clear" the variance; the external figure is the customer's evidence and changes only when the customer's own records are genuinely corrected at source.
3. Confirm the exception has an owner (an active member) and a severity. If not, assign both immediately via the exception resolution flow.

## 3. Evidence to preserve

- checkpoint id, code, as-of date, external value, derived Terranex value, variance;
- external source reference and external evidence reference exactly as recorded;
- exception id, owner, severity;
- the derivation inputs of the Terranex side (the posted lines/read model the checkpoint was derived from) as of the checkpoint date.

## 4. Diagnosis — identify the wrong side

The variance has exactly three possible origins. Establish which one before correcting anything:

1. **External side wrong:** the customer's record/extract used as the external value is itself incorrect or stale (wrong as-of date, missing item, double count). The Terranex derivation is reproducible and correct.
2. **Terranex side wrong:** a posted fact is missing, duplicated, or wrong (unrecorded contribution/obligation/collection, wrong party, wrong amount, wrong opening row). The external evidence is correct.
3. **Definition mismatch:** both sides are internally correct but measure different things (different as-of date, different scope, e.g. committed vs contributed capital). This is resolved by re-stating the comparison correctly, not by moving money.

Diagnostic path per checkpoint:

| Checkpoint | Compare Terranex derivation against | Typical wrong-side facts |
| --- | --- | --- |
| `CONTRIBUTED_CAPITAL` | customer capital register, per participant | missing/duplicated contribution posting; contribution attributed to wrong participant; opening row route vs contribution-flow route double count |
| `SUPPLIER_OBLIGATION_POSITION` | AP aging / supplier statements | unrecorded obligation; payment recorded without settlement; opening payable row wrong |
| `CUSTOMER_RECEIVABLE_POSITION` | sale contracts and collection records | collection unrecorded or matched wrong; recognition amount wrong; opening receivable row wrong |
| `DISTRIBUTION_PAYABLE` | partner resolutions on unpaid distributions | approved distribution not recorded; payment not settled against payable; opening payable row wrong |
| `DISTRIBUTION_PAID` | bank evidence of distribution payments executed by the customer | payment record missing or duplicated; recorded before the customer's banking process actually executed it |
| `PARTNER_CAPITAL` | customer per-partner capital schedule; rollforward equation | any of the contribution/allocation/distribution facts above; opening capital row wrong |
| `REALIZED_RESULT` | independent recalculation of income less recognized costs | recognition or carrying-cost source wrong; cost treatment wrong; period scope mismatch |

Read-only checks only during diagnosis; no command that changes state until the wrong side is identified.

## 5. Approved correction path

Order is fixed: **variance detected → immutable exception → identify wrong side → correct through the authoritative product path → record a NEW checkpoint → zero-variance verification → independent sign-off.**

1. **Exception stays open** until resolution is recorded with its own evidence reference.
2. **External side wrong:** the customer corrects their own records and issues a corrected extract/reference. No Terranex change. Record a **new** checkpoint with the corrected external value and its new source/evidence references.
3. **Terranex side wrong — open period:** correct the posted fact through the linked reversal/replacement path (`INCORRECT_POSTED_TRANSACTION.md`), or record the genuinely missing fact through the normal product command (contribution, obligation, payment record, collection, distribution). Never "adjust" a balance: there are no editable balances.
4. **Terranex side wrong — opening position:** wrong opening rows follow `FAILED_OPENING_IMPORT.md` (reversal-guard ordering applies).
5. **Terranex side wrong — closed period:** `CLOSED_PERIOD_CORRECTION.md`.
6. **Definition mismatch:** agree the correct comparison definition with `<FINANCE_CONTROL_OWNER>` and the customer; record a new checkpoint with the corrected external value under the correct code/as-of date. The mismatch is documented in the exception resolution.
7. **Record a NEW checkpoint** (same code, corrected as-of/value and fresh source/evidence references). The old checkpoint remains exactly as it was — it is history, not a mistake to erase.
8. **Zero-variance verification:** the new checkpoint must show variance = 0 (`MATCHED`). Any residual variance restarts this procedure; there is no tolerance.
9. **Resolve the exception** with a resolution statement and evidence reference, then **independent sign-off**: a signer who is not the preparer signs the new checkpoint with an evidence reference. Sign-off is immutable.

## 6. Prohibited shortcuts

- Never edit, re-date, or delete the old checkpoint or its exception.
- Never "clear" a variance by changing the external evidence to match Terranex; the external value changes only when the customer's own records are genuinely corrected at source, with a new dated reference.
- Never use manual SQL balance adjustment — no such path exists or may be invented; all corrections are product commands.
- Never sign off with a variance outstanding, and never let preparer and signer be the same person (the product enforces both).
- Never record the new checkpoint before the underlying correction is fully posted; a checkpoint over an in-flight correction is misleading evidence.

## 7. Post-recovery verification

- New checkpoint recorded: variance = 0, status `MATCHED` path, fresh source/evidence references.
- Exception resolved with resolution text and evidence reference.
- Independent sign-off recorded (signer ≠ preparer).
- Any related weekly reconciliation record updated to reference the new checkpoint ids.
- If the correction moved cash, `PROJECT_CASH`/bank reconciliation re-checked per `UNRECONCILED_CASH.md`.

## 8. Escalation

- Variance with unknown cause after diagnosis → `<FINANCE_CONTROL_OWNER>` + `<PILOT_OPS_OWNER>`; severity at least HIGH when cash or capital is involved.
- Suspected tampering or cross-tenant exposure discovered during diagnosis → stop and use `CROSS_TENANT_OR_SECURITY_INCIDENT.md`.
- Recurring variances on the same checkpoint across weeks → onboarding/data-quality problem; escalate to `<PILOT_OPS_OWNER>` for intake remediation rather than repeating ad-hoc fixes.

## 9. Communication

- Tell the customer the checkpoint, the exact variance in minor units, which side was wrong, the correction taken, and the new checkpoint reference.
- Never present the old (variance) checkpoint as superseded-and-forgotten: both checkpoints remain visible history. Never promise zero variance before the new checkpoint is recorded.

## 10. Record

Write down: checkpoint ids (old and new), variance amount, wrong side and root cause, correction command references, exception id and resolution, sign-off actor and evidence reference. References only — real customer data stays in the customer's systems.
