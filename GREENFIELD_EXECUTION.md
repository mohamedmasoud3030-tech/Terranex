# Greenfield Execution Status

**Updated:** 2026-08-13  
**Canonical branch:** `main`
**Strategy:** Product-first, Egypt-first, thin vertical slices

This file records execution state only. Detailed domain/accounting decisions belong in the numbered ADRs and the approved Greenfield product documents.

## Foundation

Status: **COMPLETE**.

- Legacy product frozen at `legacy/pre-greenfield-20260810`; it is not a source for Greenfield behavior.
- Eight Greenfield product documents are the conceptual baseline.
- Product-first Egypt launch: `docs/decisions/0001_PRODUCT_FIRST_BUILD.md`.
- Simple modular-monolith delivery: `docs/decisions/0002_SIMPLICITY_AND_VERTICAL_SLICES.md`.
- Customer interviews/design partner are not build prerequisites.

## Completed batches

### GF-002 / S0 — Executable Foundation and Project Shell

Status: **COMPLETE**. Merged through PR #84.

Proof: Arabic responsive application shell, organization/project creation, Supabase tenancy/RLS/audit baseline, deterministic npm install, PostgreSQL 16 replay, two-tenant isolation.

### GF-003 / S1 — Terms & Funding

Status: **COMPLETE — VERIFIED AND MERGED**. Integration PR #88.

Proof: parties/participants, immutable governing agreement version, commitments, capital calls/contributions, exact capital rollforward, payload-bound idempotency, OWNER material approval, RLS/cross-project integrity, real over-call/over-contribution races.

Canonical decision: `docs/decisions/0003_S1_TERMS_AND_FUNDING.md`.

### GF-004 / S2 — Cost & Cash

Status: **COMPLETE — VERIFIED AND MERGED**.

Proof: project cash accounts, controlled contribution-to-cash attribution, obligations/payment/reconciliation, balanced immutable subledger, exact bigint money transport, bank-statement fingerprinting, linked reversals, OWNER material approval, real payment/posting/reconciliation concurrency, forward upgrade.

Canonical decision: `docs/decisions/0004_S2_COST_AND_CASH.md`.

### GF-005 / S3 — Real Estate Sector Operation

Status: **COMPLETE — VERIFIED AND MERGED**.

Proof: Real Estate project profile, property/parcels, authoritative lifecycle/history, acquisition/control evidence, development phases/milestones/events, immutable budget versions, S2-backed property cost control, management valuation kept separate from accounting, hierarchy integrity, real lifecycle concurrency, forward upgrade.

Canonical decision: `docs/decisions/0005_S3_REAL_ESTATE_OPERATIONS.md`.

### GF-006 / S4 — Revenue & Realized Result

Status: **COMPLETE — VERIFIED AND MERGED**.

Proof: disposition/control-transfer lifecycle, balanced sale recognition and carrying-cost derecognition, partial/multiple collection, bank reconciliation reuse, realized-result read models, selling-cost separation, no implicit accounting from operational states, real recognition/collection races, forward upgrade.

Canonical decision: `docs/decisions/0006_S4_REVENUE_AND_REALIZED_RESULT.md`.

### GF-007 / S6 — Period Close and Controlled Correction

Status: **COMPLETE — VERIFIED AND MERGED**.

Merged through PR #98 on 2026-08-12. Merge commit: `d26a3bbbc9a8e29b61bb0a4ecfd2a21bf9e0a0c6`.

Delivered and verified:

1. Versioned accounting periods with one authoritative OPEN period per organization/project/currency scope and immutable CLOSED rows.
2. Database-enforced period lock on financial posting once period management is authoritative for the project.
3. Versioned close runs with ten server-side close controls, OWNER approval, and immutable content-hashed close snapshots.
4. Truthful `BANK_RECONCILIATION_COVERAGE`: unresolved lines are FAIL and can only move to `APPROVED_EXCEPTION` through an audited exception workflow.
5. Period-scoped sector cut-off and reproducible sector rollforward controls without forcing valid operational assets to artificial maturity.
6. Controlled reopen as a new superseding period version; no rewrite of the closed period.
7. Forward correction request/approval/execution using exact linked journal reversal; original S2/S4 economics and provenance stay immutable.
8. Correct close-exception relational integrity and composite-gate recomputation.
9. PostgreSQL-safe strict S6 SQL assertions; historical S2/S3/S4 concurrency and forward-upgrade fixtures remain compatible without weakening production controls.
10. Canonical PostgreSQL 16 Greenfield CI run #68: application PASS and database PASS, including S0–S4 regressions, S3/S4 forward upgrades, S6 SQL, S6 two-session concurrency, and S6 forward upgrade.
11. SonarQube Cloud Quality Gate PASS, 0 security hotspots, 1.7% duplication on new code.

Canonical decision: `docs/decisions/0007_S6_PERIOD_CLOSE_AND_CORRECTION.md`.

### GF-008 / S5 — Allocation & Distribution

Status: **COMPLETE — VERIFIED AND MERGED**.

Proof: immutable allocation basis frozen to one activated governing agreement version with an evidence reference; allocation prepared only from an approved immutable S6 close snapshot, with the source amount derived in-database as of the snapshot capture timestamp; deterministic largest-remainder allocation that totals exactly to the source; database-enforced maker/checker on allocation and distribution approval; separate allocation, approved payable, and paid-cash facts; conservative recorded-liability distributable-cash rule; exact partner-capital rollforward; reversal dependency ordering; a real two-session distribution-payment race; forward upgrade from the merged S6 boundary.

Canonical decision: `docs/decisions/0008_S5_ALLOCATION_AND_DISTRIBUTION.md`.

### GF-009 / S7 — Pilot Hardening

Status: **COMPLETE — VERIFIED AND MERGED**. Delivered through PR #101 and subsequently integrated into `main`.

Delivered and verified:

1. Controlled opening import with a governed `DRAFT → VALIDATED → READY_FOR_APPROVAL → APPROVED → POSTED` lifecycle, file checksum, schema version, deterministic normalization, twelve explicit row-rejection reasons, exact control totals, rejected-row atomicity, database-enforced maker/checker, immutable approved snapshot hash, and a locked six-code Real-Estate mapping registry.
2. No destructive overwrite of an opening position: at most one active posted opening per project, and a reversal guard that refuses while later un-reversed postings depend on it.
3. Nine reconciliation checkpoints comparing externally supplied control totals against in-database derived balances, with exact integer variance, explicit zero-variance, mandatory owned exceptions on any non-zero variance, and immutable maker/checker sign-off.
4. Deterministic end-to-end technical rehearsal across S0 → S1 → S7 → S2 → S3 → S4 → S6 → S5 → S7 on fixtures only, proving balances and provenance survive the full cycle.
5. Executable PostgreSQL 16 backup/restore rehearsal with seventeen integrity fingerprints reproduced exactly, plus proof that forced RLS, immutability triggers, and posted-fact tamper refusal all survive a restore. **Rehearsal only; no production restore has been performed.**
6. Access revocation that takes effect immediately for open sessions, a last-active-owner guard, and re-assertion that S5 self-approval remains impossible.
7. Durable UAT evidence that the system can never self-accept, and an acceptance report that derives technical readiness from recorded facts while reporting the human gate separately.
8. Arabic/RTL pilot workspace inside the existing project shell, with distinct loading, empty, filtered-empty, validation-error, server-error, forbidden, conflict and completed states.
9. Ten operator runbooks in `docs/runbooks/`, none of which permit destructive SQL on posted financial facts.

Not claimed: the controlled paid pilot itself, a real customer opening import, four weekly reconciliations on real data, and buyer UAT. Those are human events requiring real customer evidence; `human_uat_status` remains `NOT_STARTED`/`PENDING` until a real authorised approver accepts a real executed task.

Canonical decision: `docs/decisions/0009_S7_PILOT_HARDENING.md`.

### GF-010 — Coherent Hosted Real Estate Workspace

Status: **CODE COMPLETE — MERGED**. Delivered through PR #121; merge commit `cfeaf00321f1271af7bc557e09643fe59a678211`.

Proof: one Arabic/RTL business workspace across the nine Real Estate operating sections, canonical read models/RPCs only, synthetic-demo truthfulness, and an explicit separation between technical readiness and real-world evidence.

### GF-011 — Hosted Presentation Readiness

Status: **CODE COMPLETE — MERGED; LATEST PRODUCTION ALIAS VERIFICATION PENDING**. Delivered through PR #122; merge commit `6122cedc1bf4fac2f84df60630c3579aac5f27ce`.

Proof: shared workspace chrome across all nine sections, operator-safe errors and identifiers, tighter mobile/tablet presentation, preserved permanent synthetic showcase, and a server-only presentation-user provisioner. The final PR reported 185 application tests plus lint, typecheck, and build passing locally. GitHub/Vercel reported free-tier deployment rate limiting, so this status does not claim that the production alias serves the merge commit.

Real Estate status is therefore explicit:

- implementation: complete for the authorized S0-S7/GF-010/GF-011 scope;
- synthetic technical/presentation evidence: complete;
- latest hosted deployment verification: pending until the production alias SHA is proved;
- real-customer validation, buyer UAT, and commercial Phase 2/3 evidence: not started/not passed.

### GF-013 — Agriculture Sector Foundation (Farm → Field → CropCycle)

Status: **CODE COMPLETE — DRAFT PR OPEN**. Branch
`agent/gf-013-agriculture-foundation`, base SHA
`b1c8f7c8855fb8339459b67b5ede1f01a74904b1` (zero behind origin/main).

Delivered and verified in this slice:

1. Sector-aware project identity: the authoritative
   `investment_projects.sector` constraint is expanded from
   `REAL_ESTATE` to `REAL_ESTATE | AGRICULTURE`; the canonical
   `create_investment_project(uuid, uuid, text, text, text, text)`
   RPC takes the explicit sector; the historical 4-argument
   signature is preserved as a Real Estate compatibility wrapper;
   the actual selected sector is recorded in the immutable
   `audit_events` payload.
2. Agriculture bounded context as a sibling feature:
   `src/features/agriculture/{schema,actions,queries,labels}.ts`
   plus `/projects/[projectId]/agriculture` and its forms. No
   Agriculture logic lives inside the Real Estate feature.
3. Server-authoritative commands for `agriculture_project_profiles`,
   `farms`, `fields`, `crop_cycles`,
   `crop_cycle_field_assignments`, and CropCycle lifecycle
   transitions. All commands are idempotent
   (8–120 char key + sha256 request_hash), refuse payload
   mismatch, are advisory-lock-serialized, write the audit event
   in the same transaction, and require an active organization
   member against a project whose sector is `AGRICULTURE`.
4. Documented lifecycle enforced at the database boundary:
   `PLANNED → ESTABLISHED`, `ESTABLISHED → GROWING`,
   `GROWING → HARVESTING`, `HARVESTING → CLOSED`,
   `PLANNED → CANCELLED`, `GROWING → FAILED`. Every other
   transition, including skips, backward moves, and same-state
   re-assertion, is rejected. Causal current state is derived
   from the unique unconsumed chain tip
   (`agriculture_current_cycle_history_tip_id`), not from a
   `changed_at`/UUID ordering.
5. Field-area invariant: assigned area is positive, the unit
   matches the Field's unit, the half-open `[start, end)` overlap
   rule is used, the total for any non-cancelled cycle overlapping
   the new range must not exceed the Field's area. The invariant
   is enforced twice — once inside the assignment RPC with a
   `FOR UPDATE` row lock + advisory lock, and once in a
   `BEFORE INSERT` row trigger so direct SQL cannot bypass it.
6. Default-deny RLS, forced RLS, and security_invoker read views
   on every Agriculture table. `REVOKE`d from `anon` and
   `authenticated`; the `authenticated` role gets only `SELECT`
   on the read views. No browser/table write path exists.
7. Sector-aware navigation: Real Estate keeps its nine business
   sections unchanged; Agriculture has a single truthful entry
   `المزرعة والمحاصيل`. The project home, the project cards,
   and the project overview page all show a truthful sector
   label (`عقارات` / `زراعة`) and link to the sector-correct
   destination. Agriculture projects are redirected away from
   the Real Estate overview page.
8. Append-only history: a `BEFORE UPDATE OR DELETE` trigger on
   `crop_cycle_state_history` refuses all mutations, matching
   the existing S3/S7 audit-trail immutability pattern.
9. Application test count: 228 (15 test files), up from 190 at
   the GF-012 baseline. All 228 pass locally; lint, typecheck,
   and the production `next build` pass locally with the same
   public placeholder environment used by CI.
10. New database verification suites:
    `37_gf013_sector_aware_project.sql`,
    `38_gf013_agriculture_foundation.sql`,
    `39_gf013_field_area_invariant.sql`,
    `40_gf013_agriculture_forward_upgrade.sh`, and
    `41_gf013_two_tenant_agriculture.sql`. They are discovered
    automatically by `scripts/db-test.sh`.
11. Local `npm run db:test` reports as **unresolved** in this
    environment because neither `psql` nor Docker is available
    on the local agent sandbox. The canonical GitHub Actions
    PostgreSQL 16 job is the authoritative gate before the PR
    is called ready. Per `AGENTS.md` and `docs/DB_DEVELOPMENT.md`,
    the local database gate is never simulated or marked passed
    when its prerequisites are missing.

Real Estate is unchanged: no existing row, function, view, RLS
policy, trigger, or test was weakened. The pre-existing
Real Estate row in the forward-upgrade fixture survives the
GF-013 migration and remains `sector = 'REAL_ESTATE'`.

Canonical decision: `docs/decisions/0013_GF013_AGRICULTURE_FOUNDATION.md`.

## Explicitly deferred

- agreement amendment/supersession and funding carry-forward beyond the implemented governing version;
- advanced waterfall economics: preferred return, hurdle tiers, GP catch-up, carry, clawback, tax/withholding and cross-project netting;
- statutory/general ledger, chart-of-accounts editor, external accounting adapters, bank APIs/open banking, VAT/tax/e-invoicing;
- fuzzy/split/many-to-many bank reconciliation and multi-currency/FX engine;
- private DMS/platform, generic workflow/approval engine, notifications/outbox/integrations;
- partial-property disposition and other sector-specific complexity not required by the current Real Estate vertical slice;
- leasing/property management and construction ERP/procurement/BOQ/change-order scope;
- PWA/offline sync;
- Agriculture capabilities beyond the active bounded slice and all Livestock runtime modules;
- Agriculture operational entities deferred by GF-013 itself: `FieldActivity`, `InputItem`, `InputLot`, `InputApplication`, `HarvestEvent`, `HarvestLot`, `StorageLocation`, `InventoryMovement`, `AgronomyObservation`, agriculture-side sales/receivables, agriculture profitability or accounting recognition, IAS 41 posting logic, agronomy recommendations, weather providers, GIS / map integrations, and any second ledger, ownership model, payment engine, investor balance, approval framework, or audit truth;
- generic repositories, plugin/rules frameworks, CQRS/event sourcing, microservices and speculative shared layers.

## Next active batch

`GF-014 — second bounded Agriculture slice`, to be chosen after the
GF-013 PR is reviewed and merged. The candidate entities documented
as deferred in the GF-013 migration are
`FieldActivity`, `InputItem`, `InputLot`, `InputApplication`,
`HarvestEvent`, `HarvestLot`, `StorageLocation`,
`InventoryMovement`, and `AgronomyObservation`. The next batch
must pick the smallest end-to-end workflow that advances the
agriculture operator journey without re-opening Real Estate or
scaffolding livestock.

This batch is authorized only after GF-013 is merged and the
GF-013 PR's GitHub Actions PostgreSQL 16 database job has
returned green. Real-customer validation remains a separate
parallel evidence track; the controlled Real Estate pilot still
requires a signed engagement, real opening data, exact
reconciliation, buyer UAT, and runbook evidence before any
Phase 2/3/4 claim advances. The absence of those events does
not block GF-014, and no synthetic fixture may impersonate them.

## Decision rules

- One canonical implementation per concept; extend before creating another.
- A shared abstraction requires two real consumers.
- Every batch completes one user workflow across schema, domain, application, UI, permissions, tests, telemetry/audit, and documentation.
- Money, ownership, allocation, payable and payment semantics must be exact, server-authoritative, tenant-safe and auditable.
- Approved/posted facts are immutable; correction is forward-versioned or linked reversal, never destructive editing.
- Every implementation branch starts from the exact latest `origin/main`, is zero commits behind before delivery, and contains no unrelated legacy churn. `greenfield/foundation` is historical and non-authoritative unless Mohamed explicitly reactivates it.
- No production deployment or production-data change without explicit authorization.
