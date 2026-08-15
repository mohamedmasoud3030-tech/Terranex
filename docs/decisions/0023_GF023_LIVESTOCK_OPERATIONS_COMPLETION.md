# ADR-0023 — GF-023 Livestock Operations Completion

**Status:** Accepted for GF-023  
**Date:** 2026-08-14  
**Base:** `a1ca7e8111e75e3cddc5613f4912e326c2f66156`

## Decision

Complete the bounded, non-commercial Livestock v1 operating layer with four append-only areas: health, reproduction, optional individual identity, and feed consumption. The GF-020 Cohort model and GF-021/GF-022 placement, quantity, weight, inception, species, and lineage invariants remain authoritative.

GF-023 adds one forward migration in its reserved range: `20260815010000_livestock_operations_completion.sql`. It does not alter an applied GF-020/021/022 migration.

## Implemented boundaries

### Health, treatment, medicine and vaccination

- `livestock_medicine_products` is an immutable operational product reference, not a pharmacy or stock ledger. It records product kind, active ingredient where known, and an explicit default withdrawal period.
- `livestock_health_events` records cohort-level facts first and can optionally target an identified Animal that belongs to that Cohort at the effective time.
- Event types are `OBSERVATION`, `DIAGNOSIS`, `TREATMENT`, and `VACCINATION`.
- Diagnosis classification, product, exact dose/unit, route, administration time, practitioner/operator, evidence, and notes are constrained according to event type.
- Treatment accepts a `MEDICINE` reference and vaccination accepts a `VACCINE` reference. The database enforces the match independently of the UI.

No medicine balance, lot availability, supplier, purchase, cost, or emergency stock exception is invented. A configured product is a reference only.

### Withdrawal semantics

At administration, `withdrawal_period_days` and `withdrawal_ends_at` are frozen on the HealthEvent from the immutable product reference. Zero days explicitly means no withdrawal interval. Positive intervals become `ACTIVE` until their end and then `ENDED` in the read model.

`livestock_active_withdrawals` exposes active operational facts by tenant/project/cohort/optional Animal. It does **not** decide whether a sale is permitted. Commercial interpretation and sale-blocking belong to GF-024.

### Reproduction

`livestock_reproduction_events` supports:

- breeding/service and service method;
- pregnancy check, status, and expected birth date when positive;
- birth outcome, observed live/stillbirth counts, and optional dam/sire identity;
- weaning count;
- cohort-level events when individual identity is unavailable;
- optional individual subject when identity exists and membership is valid.

Reproduction observations do not form a lifecycle state machine or a second quantity ledger. They are immutable events.

### Optional Animal identity

`livestock_animals` and `livestock_animal_memberships` provide an optional identification layer:

- A Cohort never requires one Animal row per head.
- Identification is accepted only against a positive, active Cohort at the effective time.
- Ear tag, RFID, and other identifiers are normalized and unique within explicit `(organization, project, identifier type)` scope. Identical values in another tenant/project remain isolated.
- Identification creates exactly one immutable `IDENTIFIED` membership provenance row in the same transaction.
- The read model states `identification_quantity_effect = 0`. Identification neither creates a head nor moves one.
- GF-023 does not add mutable Animal current status/current Cohort. It also does not add an individual transfer command: a future transfer must be explicitly coupled to authoritative Cohort quantity/lineage semantics rather than silently reassigning membership.

The command serializes on the existing per-Cohort quantity lock and prevents concurrent identification from introducing more identities at an instant than the Cohort quantity supports. Subsequent cohort-level biological facts do not fabricate an individual life status.

### Feed operations

- `livestock_feed_items` is an immutable feed reference with category and issue unit.
- `livestock_feed_issues` records positive quantity/unit, Cohort, effective time, optional feeding period, operator, evidence, and notes.
- Unit must match the item reference.
- A feed issue requires a positive, active Cohort at its effective time.

No receipt/opening stock, supplier purchasing, feed inventory, formulation, ration optimization, cost, or valuation is inferred.

## Authoritative facts and quantity interaction

GF-020 remains authoritative for Cohort identity and immutable opening placement. GF-021 remains authoritative for movement, derived current placement, and WeightEvents. GF-022 remains the only exact integer Cohort quantity ledger.

GF-023 does not register a quantity event class and does not store current headcount. It reuses:

- `gf022_cohort_inception_at` for temporal eligibility;
- `gf022_lock_cohort_quantity` for serialization;
- `livestock_cohort_quantity_as_of` for effective-time population checks;
- `record_livestock_birth` for an authoritative birth outcome.

### Reproduction/BIRTH relationship and no double counting

A birth outcome must explicitly choose one of two meanings:

1. `OBSERVATION_ONLY`: stores observed live/stillbirth counts but has no quantity event link and changes Cohort quantity by zero.
2. `GF022_BIRTH`: the GF-023 command invokes the existing GF-022 `record_livestock_birth` command inside the same transaction and stores its returned `birth_quantity_event_id`.

The link is unique, and a privileged-path trigger verifies that the linked event is a GF-022 `BIRTH` for the same organization, project, Cohort, effective time, and live-birth quantity. Reproduction never inserts into `livestock_quantity_events` itself. Payload-bound replay returns the same ReproductionEvent before invoking birth again. Thus one outcome has exactly one authoritative quantity effect, never two.

## FCR truthfulness and limitations

`livestock_feed_conversion_metrics` returns FCR only when all of the following hold for the two latest WeightEvents:

- both are measured `COHORT_TOTAL` weights;
- both weights have evidence;
- feed issues exist between them;
- all feed is evidenced and expressed in kilograms;
- no GF-022 quantity event changes population in the interval;
- total weight gain is positive.

Then `FCR = evidenced feed kg / evidenced cohort-total weight gain kg`.

Otherwise `fcr`, numerator, and denominator are `NULL`, with a specific reason such as insufficient weight events/evidence, incomparable basis/unit, population change, no feed evidence, or no positive gain. Sample averages, estimates, and changing-population intervals are not converted into fabricated FCR.

FCR is a physical operating metric only. Feed cost per head/kg gain is unavailable because GF-023 has no authoritative feed cost or inventory valuation.

## Security, consistency and audit

Every command:

- authenticates the actor and requires active organization membership;
- validates a Livestock-sector project and tenant/project-coherent references;
- binds idempotency to a canonical request hash and serializes retries;
- writes its audit event in the same transaction;
- derives actor IDs server-side;
- runs through a `SECURITY DEFINER` function with pinned `search_path`.

All seven new base tables have forced, default-deny RLS. Authenticated clients receive read-only access through tenant-scoped policies and command execution; direct table DML is revoked. Sector triggers, composite tenant/project foreign keys, event-shape validators, deferred Animal-membership shape checks, and append-only triggers also protect privileged/import paths.

## Operator experience

An isolated Arabic/RTL route is implemented at:

`/projects/[projectId]/livestock/operations`

It contains local sections for health, identified animals, reproduction, and feed. It distinguishes loading, empty, filtered-empty, validation error, forbidden, conflict/server failure, success, and insufficient-data metric states. Operator labels use Cohort references, product names/references, and animal identifiers rather than raw UUIDs.

The global Livestock navigation and existing Livestock landing composition are intentionally unchanged for parallel-delivery safety. Shared integration is deferred until GF-023 and GF-024 are complete.

## Explicitly deferred / excluded

GF-023 does not implement or modify:

- livestock buyers or commercial purchasing;
- `SALE_OUT` / `PURCHASE_IN` quantity semantics;
- sales, customer dispatch, receivables, collections, or revenue recognition;
- profitability, Finance posting, biological-asset valuation, or closeout;
- commercial reporting or commercial withdrawal enforcement;
- medicine/feed procurement, authoritative inventory, lot stock balance, costing, or valuation;
- advanced feed formulation/nutrition optimization;
- individual transfer, pedigree/genetics ERP, dairy/milk, IoT, or offline sync.

`GREENFIELD_EXECUTION.md` and global/top-level Livestock navigation are intentionally not modified in this parallel PR.
