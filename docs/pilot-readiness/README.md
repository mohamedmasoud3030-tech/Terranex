# Terranex — Pilot & GA Readiness Pack

**Status:** Preparation artifacts — nothing in this pack has been executed against a real customer.
**Scope:** Delivery Phase 4 (Controlled Paid Pilot) and Delivery Phase 5 (General Availability) preparation.
**Canonical source:** `docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md` and the rest of the Greenfield set. This pack translates those documents into operating assets; where this pack and a canonical Greenfield document disagree, the canonical document wins.

## What this pack is

S0–S7 established **technical** pilot readiness. Per `docs/decisions/0009_S7_PILOT_HARDENING.md` §11, that does **not** establish that a controlled paid pilot ran, that a real customer's opening balances were imported, that four weekly reconciliations were performed on real data, or that buyer UAT was completed. Those are human events with real customer evidence.

This pack is the set of procedures, contracts, checklists, and matrices those human events need in order to run with minimal ambiguity. It adds **no application code, no migrations, no import functionality, and no new roles**. Everything here operates the product exactly as built by S0–S7.

## What this pack is not

- Not a strategy memo: every gate has an owner, evidence, and deterministic pass/fail.
- Not customer data: no real customer facts, names, amounts, or documents appear anywhere in this repository. Placeholders use the `<ANGLE_BRACKET>` convention already used by `docs/runbooks/README.md`.
- Not UAT results: no scenario in `05_UAT_ACCEPTANCE_MATRIX.md` is marked passed. Acceptance is a human act by a real authorized customer approver, recorded in the product's `s7_uat_tasks`.

## Index

| File | Package |
| --- | --- |
| [`01_PILOT_READINESS_MAP.md`](01_PILOT_READINESS_MAP.md) | Dependency-driven gate map from verified main to GA decision |
| [`02_DATA_INTAKE_CONTRACT.md`](02_DATA_INTAKE_CONTRACT.md) | Source-data intake contract for the first Real Estate pilot |
| [`03_OPENING_BALANCE_CONTROL_PACK.md`](03_OPENING_BALANCE_CONTROL_PACK.md) | Opening-balance control procedure with explicit zero-variance acceptance |
| [`04_PILOT_RUNBOOK_WEEKS_0_TO_4.md`](04_PILOT_RUNBOOK_WEEKS_0_TO_4.md) | Four-week controlled pilot operating plan and exit gates |
| [`05_UAT_ACCEPTANCE_MATRIX.md`](05_UAT_ACCEPTANCE_MATRIX.md) | Business-acceptance scenarios over S0–S7 outcomes |
| [`06_RECONCILIATION_PROCEDURES.md`](06_RECONCILIATION_PROCEDURES.md) | Ten repeatable reconciliations with zero-minor-unit acceptance |
| [`07_INCIDENT_SUPPORT_MATRIX.md`](07_INCIDENT_SUPPORT_MATRIX.md) | Pilot situations mapped onto the existing runbook set |
| [`08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md`](08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md) | Deployment prerequisites, categorized by verification method |
| [`09_PILOT_ROLES_AND_RESPONSIBILITIES.md`](09_PILOT_ROLES_AND_RESPONSIBILITIES.md) | Smallest practical operating responsibility model |
| [`10_COMMERCIAL_HANDOFF_REQUIREMENTS.md`](10_COMMERCIAL_HANDOFF_REQUIREMENTS.md) | What must be agreed before the paid pilot begins |
| [`11_GA_READINESS_BACKLOG.md`](11_GA_READINESS_BACKLOG.md) | Prioritized Phase 5 work packages |
| [`templates/`](templates/) | Blank preparation worksheets (no customer data) |

Validation scripts live in `scripts/pilot-readiness/` (zero-dependency bash; they inspect the repository only and never read secret values).

## Standing rules for using this pack

1. **Zero variance is the acceptance standard.** Financial acceptance variance is zero minor units everywhere in this pack, matching the product's exact control-total and checkpoint semantics. There is no tolerance, plug, or rounding accommodation.
2. **Evidence is a reference, not a file in this repository.** Per the standing rules in `docs/runbooks/README.md`, real customer data never enters this repository; evidence references are identifiers (document numbers, ticket IDs, file names in the customer's own systems).
3. **Nothing self-advances.** Technical rehearsals, scripts, and checklists can never mark a UAT task accepted, a checkpoint signed off, or a pilot gate passed. Those are separate human acts recorded in the product.
4. **Payments are records, not money movement.** Terranex does not move money. Every payment in the pilot is recorded *after* the customer's existing banking process executes it.
5. **Do not claim unrun gates.** If a checklist item could not be verified, it is recorded as not verified, never as passed.
6. **Runbooks are authoritative for incidents.** This pack references `docs/runbooks/*`; it never overrides or duplicates them.

## Relationship to the technical audit workstream

This pack was prepared in parallel with the Phase 2C/2D technical audit and security/financial remediation work. It touches no migrations, financial SQL, authorization SQL, application source, tests, or CI. If audit remediation changes any product behavior referenced here (rejection reasons, gate codes, checkpoint codes, command names), this pack must be re-validated against the merged result — `scripts/pilot-readiness/check-readiness-pack.sh` detects the code-list drift it can see.
