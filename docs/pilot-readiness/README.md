# Terranex — Pilot & GA Readiness Pack

**Status:** Preparation artifacts — nothing in this pack has been executed against a real customer.
**Scope:** Delivery Phase 4 (Controlled Paid Pilot) and Delivery Phase 5 (General Availability) preparation.
**Canonical source:** `docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md` and the rest of the Greenfield set. This pack translates those documents into operating assets; where this pack and a canonical Greenfield document disagree, the canonical document wins.

## What this pack is

S0–S7 established **technical** pilot readiness. Per `docs/decisions/0009_S7_PILOT_HARDENING.md` §11, that does **not** establish that a controlled paid pilot ran, that a real customer's opening balances were imported, that four weekly reconciliations were performed on real data, or that buyer UAT was completed. Those are human events with real customer evidence.

This pack is the set of procedures, contracts, checklists, and matrices those human events need in order to run with minimal ambiguity. It adds **no application code, no migrations, no import functionality, and no new roles**. Everything here operates the product exactly as built by S0–S7.

## Delivery status (read first)

**Technical verification and delivery exit evidence are separate concepts.** Automated fixtures, rehearsals, and synthetic PostgreSQL tests prove technical correctness; they do **not** satisfy the canonical Phase 2 and Phase 3 exit gates, which require *real* project evidence.

| Canonical milestone | Requirement (roadmap §5) | Status |
| --- | --- | --- |
| S0–S7 implementation | Platform core + Real Estate sector pack + pilot hardening built | **Built** (merged to main through PR #103; S7 via PR #101). Technical audit/remediation streams run in parallel and supersede where they land. |
| Technical verification | typecheck/lint/tests/build, migration replay, RLS/concurrency/idempotency/reversal/period-lock suites, rehearsals on fixtures | **Based on merged main** — automated gates green on fixtures. This proves the product is technically operable; it is not delivery exit evidence. |
| Phase 2 exit | "a real opening project can be imported and every financial balance reproduced" | **Not passed.** Requires real opening-project evidence: a real customer trial balance imported through the S7 controlled import and every financial balance reproduced at zero variance (pack gates PRM-04…PRM-07 produce this evidence). |
| Phase 3 exit | "one real project runs from operational event through cost/revenue, close, allocation, distribution, statement, and correction in staging" | **Not passed.** Requires the supervised real-project staging proof on the selected pilot project's verified data (pack gate PRM-09B). Synthetic fixture rehearsals (e.g. `27_s7_end_to_end_rehearsal.sql`) are explicitly **not** this evidence. |
| Phase 4 — controlled paid pilot | four consecutive weekly reconciliations, one period close, accurate investor statement, zero unresolved critical security/data issues, buyer acceptance | **Not started.** Cannot start until the Phase 2 and Phase 3 staging gates above are complete with real evidence. |
| Phase 5 — general availability | hardened onboarding/import, support/admin console + SLA, billing/plan limits, accounting export adapter, second design partner, then second sector | **Not started.** Cannot start until Phase 4 exit passes. Preparation documentation (like this pack) is allowed before the pilot; productization is not. |

No real-project, customer, UAT, reconciliation, close, restore, deployment, or buyer-acceptance gate is marked passed anywhere in this pack. Every such gate remains pending real evidence.

### GF-010 hosted workflow status

The hosted application now presents the pilot as **one coherent project workspace** in business language (نظرة عامة، رأس المال، الأصول العقارية، التكاليف والنقدية، الإيراد والبيع، الإغلاق والتوزيع، كشوف الشركاء، الاستيراد والمطابقة، الرقابة والجاهزية). Every displayed number comes from canonical read models; all mutations use the canonical RPC/command path. This is an operator-readiness improvement — it does **not** change the evidence gates below. The permanent demo (DEMO-RE-2026-001) remains synthetic; the real-world evidence section stays explicitly not satisfied for it. Phase 2 and Phase 3 exit gates remain **not passed** until real project source data is imported and reproduced at zero unexplained variance.

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
| [`12_PRE_PILOT_ACTIVATION_AND_INTAKE_STATUS.md`](12_PRE_PILOT_ACTIVATION_AND_INTAKE_STATUS.md) | Pre-pilot environment classification, provisioning boundary, and missing-value inventory (names only) |
| [`13_GUIDED_REAL_PROJECT_INTAKE.md`](13_GUIDED_REAL_PROJECT_INTAKE.md) | Guided Arabic intake overlay over S0–S7; ready to receive real data, Phase 2 still not passed |
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
