# ADR 0022 — GF-022 Livestock biological quantity events, mortality, births, split and merge

**Status:** Accepted for GF-022
**Date:** 2026-08-14
**Builds on:** ADR 0020 (GF-020 foundation), ADR 0021 (GF-021 movement/quantity/weight)

## Context

GF-021 delivered an exact integer quantity ledger (`livestock_quantity_events`)
whose sign comes from a registered class in `livestock_quantity_event_types`,
and deliberately registered **zero** classes, because it implemented no
quantity-changing event. GF-022 registers the real operational classes.

## Decision

### Additive, not a rebuild

GF-022 adds six classes and three columns to the existing ledger. It does not
drop or recreate `livestock_quantity_events`. The GF-021 forward-upgrade proof
and the GF-022 forward-upgrade proof together show the ledger evolved in place
and pre-existing derived quantities are byte-identical across the upgrade.

Registered classes: `BIRTH (+1)`, `MORTALITY (−1)`, `SPLIT_OUT (−1)`,
`SPLIT_IN (+1)`, `MERGE_OUT (−1)`, `MERGE_IN (+1)`. Sale and removal are **not**
introduced; sales remain a later stage.

### One operation identity binds the two sides

A split or a merge is **one** operation with two sides, never two unrelated
`+N` / `−N` rows. `livestock_quantity_operations` supplies that identity, and
every leg carries `operation_id` under a composite tenant-aware FK.

Two data-driven flags on the class registry keep the rules out of the commands:
`requires_operation` (the class is an operation leg and may never stand alone)
and `requires_cause` (the class must carry a cause category). A `BEFORE INSERT`
validator enforces both in either direction — an orphan `SPLIT_OUT` is refused,
and a `BIRTH` carrying a cause or an operation is refused — and checks that the
operation type matches the leg, so a SPLIT leg cannot hang off a MERGE.

### Conservation is a database invariant

A deferred constraint trigger proves at commit that every operation has both an
outgoing and an incoming leg and that `sum(out) = sum(in)`. Deferral lets the
atomic command write both legs in one transaction while still refusing any
incomplete or unbalanced privileged write. Quantity is never created or
destroyed by an operation.

### Derived quantity can never go negative

Each command takes a per-Cohort advisory transaction lock, reads the derived
balance **under that lock**, and refuses to overdraw it. A deferred non-negative
constraint trigger is the last-resort backstop for privileged paths. Merge locks
its sources in deterministic id order so two concurrent merges sharing a source
cannot deadlock.

### Operation-derived Cohorts have no opening balance

A Cohort produced by a split or a merge did not "open" with a headcount: its
entire quantity arrives through the lineage event. Recording an opening balance
as well would double-count it. Two new origins, `SPLIT_FROM_COHORT` and
`MERGED_FROM_COHORTS`, are the only ones permitted a zero opening headcount; a
CHECK constraint keeps every other origin strictly positive. The source Cohort's
opening headcount is never rewritten.

The destination's Herd, Site, sex composition, and breed are **explicitly
chosen** by the command rather than blindly copied, and it receives its own
immutable opening placement and a complete `PLANNED → ACTIVE` lifecycle chain so
it can carry operational events immediately.

### Zero quantity does not mutate lifecycle

Reaching zero is a truthful derived reading, not a state transition. GF-022 does
**not** invent an implicit close or loss transition, because the canonical
lifecycle doctrine requires explicit, causal, command-driven transitions. A
Cohort fully consumed by a merge correctly shows `current_quantity = 0` and
remains `ACTIVE`. Any future close/lost state must arrive as an explicit
immutable transition command, never as a trigger-side mutation.

### Rollforward

```
current = opening + births + split_in + merge_in
                  - mortality - split_out - merge_out
```

Exact integers throughout; no floating point on this path. The resolver raises
on a negative balance rather than returning it.

### No Finance side effect

Births, deaths, splits and merges post nothing: no journal, payment, valuation,
IAS 41, biological-asset measurement, or COGS. Shared Finance Core remains the
single authoritative ledger.

## Deferred

Detailed HealthEvent, medicine/treatment, withdrawal periods, vaccination
programmes, reproduction/pregnancy/breeding workflow, individual Animal/RFID
registry, feed formulation/inventory/FCR, procurement, sales, receivables,
collections, revenue, profitability, closeout, dairy/milk, IAS 41 and
fair-value biological-asset accounting, GIS, IoT, AI, and offline sync.
