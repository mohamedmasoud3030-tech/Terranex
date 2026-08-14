# ADR 0015 — GF-015 Field Input Application Foundation

**Status:** Accepted
**Date:** 2026-08-14
**Decision owner:** Mohamed

## Context

GF-013 delivered `Farm → Field → CropCycle` and CropCycle-to-Field
assignments. GF-014 added the append-only `FieldActivity` record of
what happened in the field. An operator can therefore say "we
fertilized this assignment on this date" but cannot yet say **which
real input, from which traceable lot, in what quantity, over what
treated area**.

GF-015 closes exactly that gap and nothing more. The operational chain
becomes:

```
Farm → Field → CropCycle → CropCycle-Field Assignment
     → Field Activity → Input Item → Input Lot → Input Application
```

## Decision

### 1. InputApplication follows FieldActivity; it does not replace it

An `input_applications` row attaches to an existing `field_activities`
row, and the project, crop cycle, field and assignment are **derived
server-side from that activity**. They are not parameters of the
command and are never asserted by the browser.

This is the decisive modelling choice. The alternative — letting an
application carry its own independent scope — would have created a
second, competing statement of "where did this happen" that could
drift from the activity record. One operational fact already owns the
field work; the input application annotates it.

The operator therefore selects an activity, an input, and a lot. They
are never asked to independently pick six identifiers the activity
already knows.

### 2. Coherence is database-enforced, not application-enforced

Every scope column participates in a composite foreign key. GF-015 adds
two additive composite keys to the already-merged GF-013/GF-014 tables
(`crop_cycle_field_assignments_area_scope_key`,
`field_activities_input_scope_key`) so that a single key can prove more
than membership:

* `(assignment_id, organization_id, project_id, crop_cycle_id, field_id, applied_area_unit)`
  → the assignment exists **and** the treated-area unit is the
  assignment's own unit;
* `(field_activity_id, organization_id, project_id, crop_cycle_id, field_id, assignment_id, activity_type)`
  → the activity exists in this exact scope **and** its type is the one
  recorded on the application;
* `(input_item_id, organization_id, project_id, input_category, unit)`
  → the item exists in this project **and** its category and
  application unit match;
* `(input_lot_id, organization_id, project_id, input_item_id, unit)`
  → the lot belongs to that item, in that project, with that unit.

A guessed id from another organization, project, crop cycle, field,
assignment, field activity, input item, or input lot cannot be stored,
even by privileged SQL. The commands validate the same rules first so
the operator receives a clear message rather than a constraint name.

### 3. Activity/category mapping is closed and server-enforced

```
SEED       → PLANT
FERTILIZER → FERTILIZE
CHEMICAL   → SPRAY
```

`SCOUT`, `IRRIGATE`, `WEED`, `PREPARE` and `OTHER` can never consume an
input application: `activity_type` is constrained to the three
input-bearing values, a table check binds category to activity, and the
composite foreign key forces the stored `activity_type` to equal the
referenced activity's own type. The UI filters the activity list to the
same three types; the server does not trust that filtering.

Only `SEED | FERTILIZER | CHEMICAL` are modelled. Fuel, packaging and
other non-field-applied materials are deferred until a real workflow
needs them; GF-015 is not a procurement, warehouse, or ERP item master.

### 4. Stock availability is intentionally NOT modelled

This is the most important boundary in the slice.

> GF-015 proves identity, lot traceability, field/application quantity,
> expiry, and project/assignment coherence. Available-stock validation
> begins only when the canonical InventoryMovement slice exists.

An `input_lots` row is an **identity and traceability record, not
inventory**. There is deliberately no `available_stock`,
`current_quantity`, `remaining_quantity`, `lot_balance`,
`received_quantity`, `on_hand_quantity`, `unit_cost`, `purchase_price`
or `valuation_amount` column anywhere in this migration, and no
browser-calculated balance.

Registering a lot does not mean stock exists, and the system does not
claim to validate availability. A fabricated balance would be worse
than no balance: an operator would trust a number the database cannot
support. The database test asserts the absence of those columns so the
boundary cannot erode silently. **This is intentional architecture, not
missing implementation.**

### 5. Lot expiry rule

If the lot has an expiry date, `application_date <= expires_on` must
hold; an expired lot cannot be recorded as a valid new application.
Application exactly on the expiry date is valid. If both dates are
supplied, `manufactured_on <= expires_on` must hold. Expiry is checked
in the command and again in a `BEFORE INSERT` trigger, so direct SQL
cannot bypass it. The UI additionally omits already-expired lots from
the picker for the chosen activity date.

`input_lots_read` exposes `VALID | EXPIRED | NO_EXPIRY` against today;
`input_applications_read` exposes the lot's status **as at the
application date**, because a historical fact must not be re-labelled
merely because time passed.

### 6. Area rule — exact units, no conversion engine

The treated area must be positive, must use the assignment's own area
unit, and must not exceed the assigned area for that CropCycle-Field
assignment. GF-015 requires exactly compatible units and refuses a
mismatch; it does not silently convert. No generic unit-conversion
framework is introduced.

The application quantity must be positive and must use the Input Item
application unit. The rate (`quantity / applied area`) is **derived in
the read view for display and reporting** and is deliberately not
stored a second time, because a stored copy can disagree with its
inputs.

### 7. Idempotency

`organization_id + idempotency_key` is unique per table. Each command
computes a sha256 hash of the canonical payload, takes a per-key
advisory transaction lock, and returns the existing row when the hash
matches or raises `idempotency key payload mismatch` when it does not.
Concurrency cannot create duplicates.

Reviewing the GF-014 numeric hashing caveat: numeric parameters are
normalized to the stored `numeric(20,6)` precision **before** hashing
(`(p_quantity::numeric(20,6))::text`), so the hash represents the
payload that is actually stored. `'200'`, `'200.00'` and `'4.0'`
therefore replay idempotently instead of becoming a false mismatch
caused by presentation formatting. No canonicalization framework was
invented; this is a one-line cast at the existing hash site.

### 8. Audit

The existing `audit_events` table is reused. No second audit trail is
created. Three distinct event types — `INPUT_ITEM_CREATED`,
`INPUT_LOT_CREATED`, `INPUT_APPLICATION_RECORDED` — are written in the
same transaction as the fact. Payloads carry the useful identifiers
(project, activity, assignment, item, lot, date) rather than a copy of
the whole row. A same-payload idempotent replay returns early and emits
no second audit event.

### 9. No CropCycle automation

Recording an input application never advances CropCycle lifecycle
state. GF-014 established that operational records do not silently
mutate lifecycle; GF-015 preserves it, and the database suite asserts
the cycle is still `PLANNED` after applications are recorded.

### 10. No accounting side effect

Creating an Input Item, an Input Lot, or an Input Application must not
create or mutate obligations, payments, journal batches, journal lines,
investor balances, project cost postings, inventory valuation, IAS 41
facts, distributions, or accounting periods. GF-015 records the
operational fact only. Financial consequences will be connected through
an explicit later slice under canonical accounting policy.

### 11. Narrow lifecycle surface

`input_applications` is append-only. `input_items` and `input_lots` are
immutable once recorded. Correction of a catalog definition is not
required by this slice, so no edit/history/status/workflow framework is
introduced. When a correction workflow is genuinely needed it will
arrive as an explicit slice with its own reversal semantics; until then
the narrow surface is the documented boundary.

## Consequences

* GF-013 rows, GF-014 rows, Real Estate behavior, and every existing
  command are unchanged; the forward-upgrade fixture proves seeded
  Real Estate, GF-013 and GF-014 rows survive the migration unchanged.
* Every earlier forward-upgrade fixture was updated to exclude the
  `20260814*` family, so a later migration can never be applied before
  its prerequisites — the defect found during GF-014.
* Stock-on-hand, warehouse balances, InventoryMovement, storage
  locations, purchase orders, procurement, receiving, supplier
  accounting, costing/valuation, automatic financial postings, IAS 41
  posting, HarvestEvent, HarvestLot, crop output inventory,
  sale/dispatch, receivables, weather provider integration, GIS/maps,
  offline synchronization, generic workflow/rules engines, generic
  unit-conversion engines, a second audit framework, a second approval
  engine, livestock, and production deployment all remain deferred and
  are not scaffolded.

## What GF-016 is expected to build next

`GF-016 — Harvest Event & Harvest Lot Foundation`: the output side of
the same assignment, recording a harvest event against a CropCycle-Field
assignment and creating the traceable output lot. GF-015 deliberately
prepares that path — the assignment-scoped composite keys, the
append-only operational-fact pattern, the lot identity pattern, and the
derived-not-stored read view are all directly reusable — but GF-016 is
**not** implemented here.

After GF-016 the sector can progress naturally through

```
field work → input application → harvest event → harvest lot
           → storage/inventory movement → sale → cycle profitability
```

without rewriting the Agriculture core. The canonical InventoryMovement
slice is what will finally make available-stock validation truthful,
for both inputs and outputs.
