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

### GF-019 — Agriculture Profitability, Cycle Closeout & Technical Gate

Status: **TECHNICALLY IMPLEMENTED**. GF-018 is merged through PR #129 and technically complete. GF-019 dimensions active posted Finance Core `PROJECT_EXPENSE` lines to CropCycle without a second expense ledger, derives the cycle quantity/commercial/operating result, keeps Land Asset investment and unvalued physical inventory separate, and validates the canonical `HARVESTING → CLOSED` transition while allowing inventory and receivables to remain open.

Input-stock decision: traceability stays in scope; procurement/receipt/opening-stock and availability remain deferred farm-ERP scope because no authoritative stock source exists. Shared S6 periods/corrections and S5 allocation/distribution remain authoritative; CropCycle close never auto-distributes. Canonical decision: `docs/decisions/0019_GF019_AGRICULTURE_PROFITABILITY_CLOSEOUT_GATE.md`.

### GF-018 — Agriculture Sale, Dispatch & Revenue

Status: **MERGED — TECHNICALLY COMPLETE** through PR #129. Adds buyer-backed Agriculture Sale headers and immutable Harvest Lot lines, explicit draft/approval/control-transfer states, atomic physical `SALE_ISSUE` plus shared Finance Core revenue/receivable recognition, and append-only partial/multiple collections protected by a concurrent ceiling. Sale units are derived from Harvest Lot truth. Lot-to-buyer dispatch and revenue lineage is exposed in Arabic/RTL under `المبيعات والتحصيل`.

GF-018 reuses `CUSTOMER_RECEIVABLE`, `BANK_CASH`, shared journal batches/lines, project cash accounts, S6 posting-period guards, audit, membership and idempotency controls. It adds only `AGRICULTURE_SALE_REVENUE`; it does not create a sector ledger, mutable receivable balance, inventory valuation, COGS, profit or margin. Canonical decision: `docs/decisions/0018_GF018_AGRICULTURE_SALE_DISPATCH_REVENUE.md`.

### GF-017 — Agricultural Land Asset, Acquisition & Control

Status: **MERGED — TECHNICALLY COMPLETE** through PR #128. Adds the durable Agriculture investment/legal-control object before Farm, with `PURCHASED | LEASED | CONTRIBUTED_IN_KIND | MANAGED_FOR_OWNER`, exact legal/contract area, Party/agreement/evidence, optional purchase consideration, and an append-only Farm link. It does not fabricate assets for existing Farms and does not create payment, Contribution, journal, valuation, carrying amount, or CropCycle cost. Real Estate alignment passed without a Real Estate change. Canonical decision: `docs/decisions/0017_GF017_AGRICULTURAL_LAND_ASSET.md`.

### GF-016 — Harvest & Inventory Flow Foundation

Status: **MERGED — TECHNICALLY COMPLETE**. Bounded
Agriculture slice extending the chain from
`Farm → Field → CropCycle → assignment → Field Activity / Input Application`
to
`Harvest Event → Harvest Lot → Storage Location → Inventory Movement`.

Delivered in this slice:

1. `storage_locations` — a minimal Storage Location (organization, project,
   name, optional reference/notes) that holds harvested output. No capacity
   planning, zones, bins, temperature automation, or WMS workflow.
2. `harvest_events` — the immutable operational fact of a real harvest:
   harvest date, gross and net accepted quantity, unit, optional grade,
   notes and evidence. Gross and net are positive and net never exceeds
   gross; loss is derived (gross − net), never stored twice.
3. `harvest_lots` — one traceable output lot per Harvest Event, with the
   lot's initial quantity equal to the event's net quantity and the same
   unit, both enforced by a composite foreign key. A free-floating lot
   cannot exist.
4. `harvest_inventory_movements` — the append-only inventory truth
   (`HARVEST_RECEIPT`, `TRANSFER`, `ADJUSTMENT_IN`, `ADJUSTMENT_OUT`,
   `SPOILAGE`). Current balance per lot/location is derived from movements,
   never stored, and is concurrency-protected so a location can never go
   negative. `SALE_ISSUE` is deliberately not implemented.
5. Four idempotent, audited commands — `create_storage_location`,
   `record_harvest_event` (atomically creating event + lot + initial
   receipt + one audit event), `transfer_harvest_inventory`, and
   `record_harvest_inventory_adjustment` — with numerics normalized to the
   stored `numeric(20,6)` precision before hashing.
6. Harvest may only be recorded while the CropCycle is `HARVESTING`;
   recording a harvest never advances the lifecycle.
7. Arabic/RTL `الحصاد والمخزون` area inside the existing Agriculture
   workspace, with derived balances shown as derived and server-authoritative
   commands.

**Intentional boundary — not missing implementation:** GF-016 tracks
physical harvest-output quantity only. Sale/dispatch, buyers, invoicing,
receivables, revenue and any policy-approved COGS/valuation are deferred to
GF-018/GF-019; profitability and closeout are deferred to the final
Agriculture phase, GF-019. No IAS 41 posting is implied.
GF-015 input lots remain identity/traceability records, not stock: GF-016
does not retrofit an input balance and does not claim InputApplication now
validates input-stock availability.

Canonical decision: `docs/decisions/0016_GF016_HARVEST_INVENTORY.md`.

### GF-015 — Field Input Application Foundation

Status: **MERGED — TECHNICALLY COMPLETE**. Bounded
Agriculture slice completing the chain
`Farm → Field → CropCycle → assignment → Field Activity → Input Item →
Input Lot → Input Application`.

Delivered in this slice:

1. `input_items` — a controlled Agriculture input definition
   (`SEED | FERTILIZER | CHEMICAL`) scoped to one Agriculture project.
   No price, supplier, accounting mapping, stock balance or valuation.
2. `input_lots` — a traceable lot/batch of an Input Item. **An
   identity/traceability record, not inventory.** The lot unit is
   derived from its Input Item and held coherent by a composite
   foreign key.
3. `input_applications` — the immutable operational fact. Project,
   crop cycle, field and assignment are derived server-side from the
   referenced `field_activities` row; the browser never asserts them.
4. Server-enforced activity/category mapping: `SEED → PLANT`,
   `FERTILIZER → FERTILIZE`, `CHEMICAL → SPRAY`. `SCOUT`, `IRRIGATE`,
   `WEED`, `PREPARE` and `OTHER` can never consume an input
   application.
5. Area rule: the treated area is positive, uses the assignment's own
   area unit, and never exceeds the assigned area. Exact compatible
   units are required; no unit conversion is performed.
6. Lot expiry rule: `application_date <= expires_on`, and
   `manufactured_on <= expires_on` when both are supplied. Enforced in
   the command and again in a `BEFORE INSERT` trigger.
7. Three idempotent, audited commands — `create_input_item`,
   `create_input_lot`, `record_input_application` — writing
   `INPUT_ITEM_CREATED`, `INPUT_LOT_CREATED` and
   `INPUT_APPLICATION_RECORDED` to the existing `audit_events` table.
   Numerics are normalized to the stored `numeric(20,6)` precision
   before hashing, so presentation formatting is not a false payload
   mismatch.
8. Arabic/RTL `المدخلات والتطبيقات` area inside the existing
   Agriculture workspace, with selection constrained so invalid
   combinations are hard to choose while the server stays
   authoritative.

**Intentional boundary — not missing implementation:** GF-015 proves
identity, lot traceability, field/application quantity, expiry, and
project/assignment coherence. Input available-stock validation begins only
when canonical input receipt/opening-stock and consumption movements exist;
GF-016 harvest-output movement is not an input-stock source. No
`available_stock`, `current_quantity`, `remaining_quantity` or
`lot_balance` column exists, and no accounting, inventory-valuation,
or CropCycle-lifecycle side effect is created.

Canonical decision: `docs/decisions/0015_GF015_INPUT_APPLICATION.md`.

### GF-014 — Field Activity Foundation

Status: **MERGED — TECHNICALLY COMPLETE**. Merged into `main` through
PR #125 (merge commit `e8e94cfdbb3daeeb80e9e7d8c5ef5f13948e2ad6`).
Bounded Agriculture operational record against an existing
CropCycle-to-Field assignment. GitHub Actions `app` and `database`
(PostgreSQL 16 replay, GF-013/GF-014 suites, two-tenant isolation,
forward upgrade) were green on the merged head.

Canonical decision: `docs/decisions/0014_GF014_FIELD_ACTIVITY.md`.

### GF-013 — Agriculture Sector Foundation (Farm → Field → CropCycle)

Status: **MERGED — TECHNICALLY COMPLETE**. Integrated into `main`
ahead of GF-014. The record below describes what that slice delivered
and verified at the time it was reviewed.

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
- Agriculture capabilities beyond the completed GF-013–GF-019 investment operating scope, and Livestock capabilities beyond the merged GF-020 foundation and the active GF-021/GF-022 slices — specifically health/medicine/withdrawal, vaccination, reproduction/pregnancy/breeding, individual Animal/RFID identity, feed formulation/inventory/FCR, livestock procurement, sale/receivable/revenue, profitability, closeout, dairy/milk, and IAS 41 or fair-value biological-asset accounting;
- Agriculture capabilities deferred beyond GF-019: input-stock receiving/balance, purchase orders / procurement / supplier ERP, input/harvest valuation, COGS policy, storage capacity planning, warehouse zones/bins, advanced lot splitting/merging, `AgronomyObservation`, sale returns/credit notes/invoicing, IAS 41 posting logic, agronomy recommendations, weather providers, GIS / map integrations, generic unit conversion, and any second ledger, ownership model, payment engine, investor balance, approval framework, or audit truth;
- generic repositories, plugin/rules frameworks, CQRS/event sourcing, microservices and speculative shared layers.

## Next active batch

Real Estate and Agriculture are **TECHNICALLY IMPLEMENTED** for their authorized
scopes. `GF-013` through `GF-019` form the completed Agriculture chain.
**Livestock is the active sector. GF-020 is merged; GF-021 and GF-022 are the active bounded slices.** This status is not permission to
place Livestock schema or runtime inside GF-019, and Real Estate remains closed
to unrelated changes.

Livestock construction order, and its truthful state:

- `GF-020 — Livestock Sector Foundation` (`Site`/`Herd` → `Cohort`, immutable
  opening placement, one causal lifecycle chain): **merged through PR #131,
  technically complete**.
- `GF-021 — Livestock Movement, Quantity Rollforward & Weight Events`: delivered
  as the independently reviewable first commit of PR #132. Delivers an append-only
  causal movement chain
  (`UNIQUE (previous_movement_id)`, one root per Cohort, same-Cohort composite
  predecessor FK, database-level no-op rejection, source-equals-current-placement
  validator), a derived current-placement read model that raises on ambiguity
  instead of using `LIMIT 1`, the exact integer quantity-event architecture with
  **zero** event classes registered, and immutable WeightEvents across
  `INDIVIDUAL_MEASURED | COHORT_TOTAL | SAMPLED_AVERAGE | ESTIMATED` with
  method-specific required/forbidden metadata enforced by CHECK constraints.
  Its quantity registry is intentionally empty; GF-022 extends it additively.
- `GF-022 — Livestock Biological Quantity Events, Mortality, Births, Split &
  Merge`: delivered as the independently reviewable second commit of PR #132,
  with forward-only review hardening. Registers
  `BIRTH | MORTALITY | SPLIT_OUT | SPLIT_IN | MERGE_OUT | MERGE_IN`; binds both
  sides of a split/merge to one `livestock_quantity_operations` identity with a
  deferred conservation trigger proving `sum(out) = sum(in)`; makes a negative
  derived quantity unreachable through a per-Cohort advisory lock plus a
  deferred non-negative trigger; gives operation-derived Cohorts a zero opening
  headcount under the new `SPLIT_FROM_COHORT` / `MERGED_FROM_COHORTS` origins so
  quantity is never double-counted; and does NOT mutate lifecycle state when a
  Cohort reaches zero. Rollforward:
  `current = opening + births + split_in + merge_in − mortality − split_out − merge_out`
  as of `current_timestamp`; future events are scheduled facts and same-time
  events are one atomic bucket. It also stores qualitative weight confidence and
  constrained mortality disposal state. Normal Cohorts do not expose opening
  quantity before their date-only `origin_date` boundary; operation-derived
  Cohorts use the exact producing operation `effective_at`, including for future
  split/merge scheduling. GF-023 has not started.

Real-customer validation remains a separate parallel evidence track. No
synthetic fixture may impersonate customer, UAT, production or commercial
verification.

## Decision rules

- One canonical implementation per concept; extend before creating another.
- A shared abstraction requires two real consumers.
- Every batch completes one user workflow across schema, domain, application, UI, permissions, tests, telemetry/audit, and documentation.
- Money, ownership, allocation, payable and payment semantics must be exact, server-authoritative, tenant-safe and auditable.
- Approved/posted facts are immutable; correction is forward-versioned or linked reversal, never destructive editing.
- Every implementation branch starts from the exact latest `origin/main`, is zero commits behind before delivery, and contains no unrelated legacy churn. `greenfield/foundation` is historical and non-authoritative unless Mohamed explicitly reactivates it.
- No production deployment or production-data change without explicit authorization.
