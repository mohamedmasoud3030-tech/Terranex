# 09 — Pilot Roles and Responsibilities

**Purpose:** the smallest practical operating responsibility model for the first customer, expressed strictly inside existing Terranex authorization semantics.

**Product truth (S0–S7):** the database knows exactly two application roles — `OWNER` and `MEMBER` — with status `ACTIVE`/`INACTIVE`. There is no finer application role hierarchy in v1, and this pack does not invent one. Every duty below is either a product-enforced authority (OWNER-gated commands, maker/checker constraints) or an **operational responsibility** the customer assigns to a MEMBER and honors by convention. Where a duty is operational only, the organization must assign a named person — the product will not stop a member from acting outside their duty, so the customer's own discipline is the control.

## 1. Responsibility model

| Responsibility | Application role (product) | Product-enforced authority | Operational duty |
| --- | --- | --- | --- |
| **Customer acceptance authority** (`<CUSTOMER_APPROVER>`) | OWNER | Accepts/rejects UAT tasks (must differ from executor); approves opening import (must differ from maker); approves close; authorizes obligations/payments | Final pilot decisions; signs the weekly reconciliation summary and the pilot exit record |
| **Operational member** (daily capture) | MEMBER | Can prepare drafts, record events, import statements within the product's member permissions | Same-day capture of obligations, receipts, sector events; evidence references attached; raises exceptions |
| **Data-import maker** | MEMBER | Stages opening import rows; stages bank statement imports | Prepares DS-09 worksheet → staging; runs validation; resolves rejected rows with the customer finance lead; never approves own import |
| **Import approver / checker** | OWNER (product-gated) | Opening-import approval is OWNER-gated with maker ≠ approver enforced by table CHECK; posting date must sit in an OPEN period | Reviews the approval pack (control totals, mapping review, zero rejects) before approving |
| **Finance control owner** (`<FINANCE_CONTROL_OWNER>`) | MEMBER or OWNER | Prepares checkpoints (sign-off must be a different person); prepares allocations and close runs | Owns reconciliation cadence (R-01…R-10), exception triage severity, statement verification |
| **Allocation maker** | MEMBER (finance) | Prepares allocation runs from approved close snapshot; self-approval refused by product | Independent recalculation evidence kept alongside the run |
| **Allocation/distribution checker** | OWNER (or a different member where product permits) | Allocation and distribution approval enforce maker ≠ checker in the database | Approves only after comparing run lines to the independent recalculation |
| **Close preparer** | MEMBER (finance) | Runs the close run; gates computed server-side | Resolves blockers before presenting the close for approval |
| **Close approver** | OWNER (product-gated) | Close approval locks the period; reopen is a controlled superseding version with reason | Approves only with all gates PASS/APPROVED_EXCEPTION-evidenced |
| **Independent signer (checkpoints)** | MEMBER ≠ preparer | Sign-off CHECK: signer ≠ preparer; refused while an exception is open; frozen after sign-off | Signs weekly/opening checkpoints with evidence reference |
| **Independent UAT acceptor** | OWNER (`<CUSTOMER_APPROVER>`) | Executor ≠ acceptor enforced; nothing self-accepts | Accepts/rejects every UAT task from evidence |
| **Terranex support operator** | MEMBER during pilot (see §3), or guidance-only | Same member permissions as any member; never a service-role path | Facilitates onboarding, runs `04_PILOT_RUNBOOK_WEEKS_0_TO_4.md`, triages via `SUPPORT_ESCALATION.md`, fills incident records. **Has no product authority above any member**; any OWNER-level act in the pilot is executed by the customer OWNER |

## 2. Minimum viable staffing (first pilot)

Three customer people + one Terranex operator is the smallest practical model:

1. **Customer OWNER** — holds `<CUSTOMER_APPROVER>`, import approver, close approver, allocation/distribution checker, UAT acceptor. (One person may hold all OWNER-gated duties; they can never also be the maker of what they approve.)
2. **Customer finance lead (MEMBER)** — `<FINANCE_CONTROL_OWNER>`, import maker or checkpoint preparer, close preparer, reconciliation owner.
3. **Customer operating member (MEMBER)** — daily capture; UAT executor for operational scenarios; second active member so maker/checker and signer ≠ preparer pairs never require the same person twice.

The customer OWNER should appoint **one additional active OWNER early** (recovery duty): the product's last-active-owner guard makes owner recovery always "appoint, then revoke", but losing the only owner's access is still an operational crisis — UAT-19 exercises this.

## 3. Terranex support operator boundary

- Default posture: the support operator is granted a **MEMBER** membership for the pilot duration so they can reproduce issues on real pilot data; the membership is recorded in the evidence register with grant/revoke dates.
- They never hold OWNER in the customer organization. Every OWNER-gated act (import approval, close approval, obligation authorization, membership changes) stays with the customer.
- Standing rules from `docs/runbooks/README.md` bind them: no service-role key from a support session, no destructive SQL on posted facts, no maker/checker bypass (if only the maker is available, the action waits), no evidence deletion.
- At pilot exit, the support membership is revoked through `s7_set_membership_status` with a reason (immediate effect), or converted to the GA support model (backlog WP2).

## 4. Segregation-of-duties matrix (what the product enforces vs what the customer must discipline)

| Control | Enforced by product | Customer discipline required |
| --- | --- | --- |
| Opening import maker ≠ approver | yes (table CHECK; OWNER-gated approval) | approve only from the full approval pack |
| Checkpoint signer ≠ preparer | yes (CHECK; frozen sign-off) | rotate the signer so it is genuinely independent |
| UAT executor ≠ acceptor | yes | acceptor reviews evidence, not just the happy path |
| Allocation/distribution self-approval | yes (refused) | checker performs an actual comparison against the independent recalculation |
| Last active OWNER protection | yes (even against direct DML) | appoint the second owner early |
| Member cannot change membership status | yes | report departures the same day (`MEMBERSHIP_AND_ACCESS_INCIDENT.md`) |
| Duty-level separation among MEMBERs (capture vs finance vs import) | **no** — MEMBER is one application role | assign named duties per §1 and review audit events weekly |

## 5. Onboarding checklist for this model (gate PRM-08)

- [ ] Responsibilities assigned to named people (§1 table filled with names in the engagement operations plan).
- [ ] Second active OWNER appointed.
- [ ] Every invited user signed in at least once; ≥ 80% weekly active target accepted (roadmap metric).
- [ ] Support operator membership decision recorded (granted/deferred) with dates.
- [ ] All users can state: commitment ≠ called ≠ contributed capital; allocation ≠ distribution; valuation ≠ realized result; cash ≠ profit (terminology gate from Week 0 training).
