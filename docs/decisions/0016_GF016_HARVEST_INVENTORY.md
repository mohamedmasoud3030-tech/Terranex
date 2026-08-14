# ADR 0016 — GF-016 Harvest & Inventory Flow Foundation

**Status:** Accepted
**Date:** 2026-08-14
**Decision owner:** Mohamed

## Context

GF-013 delivered `Farm → Field → CropCycle` and assignments, GF-014 added
append-only Field Activity, and GF-015 added Input Item / Input Lot /
Input Application. An operator can now record everything from planting
through input application, but cannot yet record the **output** of the
cycle: the harvest, its traceable output lot, where it is stored, and how
it moves.

GF-016 closes exactly that gap — Harvest Event, Harvest Lot, basic
harvest-output storage, and append-only inventory movements with a derived
current balance — in one bounded vertical slice, while keeping sales,
accounting, and profitability outside.

## Decision

### 1. Harvest Event is separate from Field Activity

A `FieldActivity` records arbitrary field work (prepare, plant, irrigate,
fertilize, spray, scout, weed, other) against an assignment, with optional
quantity. A `HarvestEvent` is a **weighing/acceptance fact**: gross and net
accepted quantity, a mandatory unit, an optional grade, and a destination.
It carries stronger invariants (positive gross/net, net <= gross, cycle
must be HARVESTING) and produces a lot. Folding it into FieldActivity would
have either overloaded that table or lost the quantity invariant and the
lot relationship.

### 2. One Harvest Event produces one canonical Harvest Lot

For this bounded version a single weighing event yields one lot. Grade
splitting or multi-lot output from one weighing is a deliberately deferred
future workflow; prebuilding it now would add unused schema and commands.
The lot's initial quantity equals the event's net quantity and its unit
equals the event's unit, and its harvest date equals the event's harvest
date — all enforced by a single composite foreign key
(`initial_quantity → net_quantity`, `harvest_date → harvest_date`,
`quantity_unit → quantity_unit`), so a free-floating or incoherent lot
cannot exist even via privileged SQL. Exactly one `HARVEST_RECEIPT` exists
per lot (a partial unique index), and its quantity and date must equal the
lot's initial quantity and harvest date (enforced in the movement trigger).

### 3. Harvest does not auto-transition CropCycle

GF-013 owns the CropCycle lifecycle. Recording a harvest must not silently
advance it. A Harvest Event may only be recorded while the cycle is
`HARVESTING`; an operator whose cycle is still `GROWING` must first use the
existing explicit `transition_crop_cycle` command. No second lifecycle
engine is introduced, and the rule is enforced in the command and again in
a `BEFORE INSERT` trigger.

### 4. Quantity invariant and derived loss

`gross_quantity > 0`, `net_quantity > 0`, and `net_quantity <= gross_quantity`
are table CHECK constraints. Loss is `gross - net`, derived in the read
model and never stored a second time, so two separately-editable values can
never contradict the same physical fact.

### 5. The harvest command is atomic

`record_harvest_event` validates membership, project, cycle state,
assignment coherence, quantities and the destination, then creates the
Harvest Event, exactly one Harvest Lot, the lot's initial `HARVEST_RECEIPT`
into the selected storage location, and one audit event, all in a single
transaction. If any insert fails the whole command rolls back — there is no
partially-created harvest.

### 6. Inventory balance is derived from append-only movements

There is deliberately no mutable `on_hand`, `available_quantity`,
`current_balance` or `remaining_quantity` column. Current stock at a
location is `incoming − outgoing` from the movement history, and total lot
balance is the same across locations. Corrections are additional append-only
movements with a reason, actor and timestamp — never a destructive UPDATE.

### 7. Negative inventory is concurrency-protected

The movement command locks the Harvest Lot row `FOR UPDATE` and the
`BEFORE INSERT` movement trigger locks it again, so concurrent movements
against the same lot serialize and re-check the available balance under the
lock. Two simultaneous outbound movements cannot overdraw the same
lot/location; the database test races 70 KG and 60 KG against a 100 KG
location and requires exactly one success.

Idempotent replay is resolved **before** any mutable-state check: the
lifecycle check (harvest) and the available-balance check
(transfer/adjustment) run only after the same-key/same-payload replay
lookup has returned. A true retry therefore returns the original event or
movement even after the cycle has moved out of `HARVESTING` or the source
balance has dropped below the requested quantity.

### 8. Input inventory remains outside scope

GF-015 input lots are identity/traceability records, not stock. GF-016
introduces an inventory-movement concept **for harvested output only**. It
does not retrofit a balance onto `input_lots` and does not claim
InputApplication now validates input-stock availability — there is still no
input purchase/receipt/opening-stock workflow, so an input balance would be
fabricated.

### 9. Sale and accounting remain deferred

`SALE_ISSUE` is not implemented. Recording a harvest or moving inventory
creates no journal batch, journal line, obligation, payment, investor
balance, IAS 41 posting, or inventory-valuation fact. GF-016 tracks physical
operational quantity only.

## Consequences

* Real Estate behavior and every existing GF-013/GF-014/GF-015 row and
  command are unchanged; the forward-upgrade fixture proves seeded Real
  Estate, GF-013, GF-014 and GF-015 rows survive the migration unchanged.
* One additive composite key
  (`crop_cycle_field_assignments_harvest_scope_key`) is added to the
  already-merged assignment table; no applied migration is edited.
* The GF-015 forward-upgrade fixture now excludes the GF-016 family so a
  later migration can never be applied before GF-015's own prerequisites.

## What GF-017 is expected to build next

The final Agriculture slice: sale/dispatch → canonical core revenue linkage
→ cycle profitability → cycle closeout → Agriculture technical hardening.
It must reuse Terranex's existing finance core rather than inventing
Agriculture accounting. Livestock does not start before Agriculture reaches
its technical gate.
