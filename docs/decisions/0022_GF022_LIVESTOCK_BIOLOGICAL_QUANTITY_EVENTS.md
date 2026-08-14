# ADR 0022 — GF-022 Livestock biological quantity events, mortality, births, split and merge

**Status:** Accepted for GF-022  
**Date:** 2026-08-14  
**Builds on:** ADR 0020 (GF-020 foundation), ADR 0021 (GF-021 movement/quantity/weight)

## Context

GF-021 delivered an exact integer quantity ledger (`livestock_quantity_events`)
whose sign comes from a registered class in `livestock_quantity_event_types`,
and deliberately registered **zero** classes, because it implemented no
quantity-changing event. GF-022 registers the real operational classes and the
review-hardening migrations close temporal, species, lineage-shape, and
zero-population gaps without rewriting an already-applied migration.

## Decision

### Additive, not a rebuild

GF-022 adds six classes and extends the existing ledger. It does not replace
`livestock_quantity_events`. The forward-upgrade proofs keep pre-existing
GF-021 facts and derived quantities intact across the upgrade.

Registered classes are `BIRTH (+1)`, `MORTALITY (-1)`, `SPLIT_OUT (-1)`,
`SPLIT_IN (+1)`, `MERGE_OUT (-1)`, and `MERGE_IN (+1)`. Sale and removal are
**not** introduced; they remain a later slice.

### Business time is authoritative

Quantity-changing rows and movement rows are confirmed operational facts, not
scheduling records. They may not be future-dated. Ordinary Cohorts open for
business-time quantity purposes at their `origin_date` boundary. A Cohort
created by split or merge opens at the parent operation's `effective_at`, and
its immutable opening placement uses that same operation time rather than the
row-write clock.

`livestock_cohort_quantity_as_of(cohort_id, effective_at)` is the authoritative
availability resolver. It sums only facts effective at or before the requested
instant. Every consuming command resolves that amount while holding the same
per-Cohort advisory transaction lock used by the quantity command. Therefore a
backdated mortality/split/merge leg cannot borrow from a later birth or other
later inflow, even when the two commands race in separate sessions.

The current rollforward is explicitly an **as-of-now** projection. A deferred
prefix-nonnegative timeline constraint is a privileged/import-path backstop: a
later inflow can never repair an earlier negative historical prefix.

### GF-021 WeightEvent temporal policy is deliberately narrower

A GF-021 `WeightEvent` is an immutable **effective-dated observation log**.
GF-021/GF-022 do not derive one authoritative `current_weight` field from that
log. For that reason a future-dated WeightEvent may be stored as a dated
observation/scheduled record and cannot change current placement or current
headcount. Its sample/measured-animal counts are still checked against Cohort
quantity **as of the WeightEvent effective time**, and the Cohort must be
ACTIVE with a positive population at that time.

If the product later needs a distinct planned-weighing workflow, that is a
separate planning concept; it must not be smuggled into current quantity truth.

### Species continuity is a database invariant

A Cohort's species is derived from the Herd that defines its identity. Movement
may change Site/Herd only when the source Herd and destination Herd preserve
that Cohort species. Split and merge destination species must match every source
species. The invariant is enforced on database insert paths and again by the
deferred operation-shape validation, not merely by UI filtering.

A Herd's species is immutable once any Cohort has adopted that Herd, preventing
a privileged/import path from retroactively rewriting the biological identity
of historical movement or lineage facts.

### One operation identity binds the two sides

A split or merge is **one** operation, never unrelated `+N` and `-N` rows.
`livestock_quantity_operations` supplies the identity and every operation leg
carries that `operation_id` under tenant-aware foreign keys.

Registry flags still enforce whether a quantity class requires an operation or
a cause category. A BIRTH cannot carry a mortality cause or operation identity;
an orphan split/merge leg is invalid.

### Split and merge shape is exact at COMMIT

Conservation alone is insufficient. Deferred database constraint triggers now
validate the complete operation graph at COMMIT:

- **SPLIT:** exactly one `SPLIT_OUT`, exactly one `SPLIT_IN`, exactly one
  lineage row, matching source/destination identities, matching quantity, one
  operation effective time, and matching species.
- **MERGE:** at least two distinct `MERGE_OUT` source Cohorts, exactly one
  `MERGE_IN` destination, exactly one lineage row per source, exact per-source
  quantities, exact total conservation, one operation effective time, and one
  species across every source and destination.

The triggers are deferred so the atomic command may construct the complete
operation inside one transaction while malformed privileged writes are rejected
at COMMIT and leave no partial operation.

### Derived quantity can never go negative

Every consuming command locks the Cohort and checks its as-of quantity before
writing. Deferred all-time and timeline non-negative constraints remain
last-resort database backstops. Merge locks sources in deterministic id order so
competing commands sharing a source serialize without a deadlock-prone lock
order.

### Operation-derived Cohorts have no opening balance

A Cohort produced by split or merge receives its quantity only through the
lineage event. Its stored `opening_headcount` is zero, preventing double count.
`SPLIT_FROM_COHORT` and `MERGED_FROM_COHORTS` are the only origins permitted a
zero opening headcount; all other origins remain strictly positive. The source
Cohort opening headcount is never rewritten.

The destination Site, Herd, sex composition, and breed are explicitly chosen by
the command, validated for project/species coherence, and the destination gets
its own immutable opening placement plus a complete `PLANNED -> ACTIVE` chain.

### Zero quantity does not silently mutate lifecycle

GF-020's implemented lifecycle is deliberately bounded to `PLANNED -> ACTIVE`.
GF-022 therefore does **not** fabricate a `SPLIT`, `MERGED`, `CLOSED`, or `LOST`
state as a trigger side effect. Reaching zero remains a truthful derived reading
and the Cohort remains `ACTIVE` until a later explicit lifecycle slice defines a
causal closure command.

A zero-population ACTIVE Cohort is nevertheless **operation-ineligible**:
movement, weight, mortality, split, and merge-source consumption are refused by
database guards. BIRTH is the only GF-022 additive quantity command allowed to
restore a zero ACTIVE Cohort. The UI must not present zero-population Cohorts as
eligible sources for the consuming/observational workflows.

### Rollforward

```text
current = opening + births + split_in + merge_in
                  - mortality - split_out - merge_out
```

Headcount remains exact integer data throughout; no floating-point arithmetic
is used on this path.

### No Finance side effect

Births, deaths, splits, merges, movement, and WeightEvent logging post nothing:
no journal, payment, valuation, IAS 41 measurement, biological-asset carrying
amount, or COGS is created. Shared Finance Core remains the only authoritative
financial ledger.

## Explicit canonical deferrals

These are **not implemented in GF-021/GF-022 and must not be claimed as shipped**:

1. **Sampled-weight confidence.** GF-021 stores the weight method, sample size,
   measured-animal count when relevant, and evidence reference. A canonical
   confidence field/model for sampled weights is deferred to the next bounded
   Livestock slice that owns measurement quality.
2. **Mortality disposal method.** GF-022 stores mortality quantity, cause
   category, optional cause detail, evidence, notes, actor, and effective time.
   Canonical carcass/disposal method is deferred to the next bounded Livestock
   health/mortality-detail slice.
3. **Explicit terminal lifecycle states.** `SPLIT/SOLD/CLOSED/LOST` transitions
   are not introduced here. Zero is protected operationally but is not silently
   turned into a lifecycle transition.

Until those slices land, Terranex must describe GF-021/GF-022 as the bounded
movement/weight/quantity foundation, **not** as complete coverage of every
canonical Livestock field.

## Other deferred scope

Detailed HealthEvent, medicine/treatment, withdrawal periods, vaccination
programmes, reproduction/pregnancy/breeding workflow, individual Animal/RFID
registry, feed formulation/inventory/FCR, procurement, sales, receivables,
collections, revenue, profitability, closeout, dairy/milk, IAS 41 and
fair-value biological-asset accounting, GIS, IoT, AI, and offline sync remain
outside GF-022.