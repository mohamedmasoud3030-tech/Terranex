# ADR 0021 — GF-021 Livestock movement, quantity rollforward and weight events

**Status:** Accepted for GF-021
**Date:** 2026-08-14
**Builds on:** ADR 0020 (GF-020 Livestock cohort-first foundation)

## Context

GF-020 established `Project → Site`, `Project → Herd`, `Herd → Cohort`, one
immutable opening placement, an immutable positive opening headcount, and one
causal lifecycle chain per Cohort. It deliberately stored no mutable
`current_site_id` and no mutable `current_headcount`, because no event existed
that could legitimately change either.

GF-021 makes the Livestock model operationally usable by adding the missing
events, while keeping every current fact derived.

## Decision

### Livestock stays event-derived

No mutable `current_site_id`, `current_herd_id`, `current_headcount`,
`current_weight`, `available_animals`, `mortality_total`, or `births_total` is
introduced as authoritative state on any base table. Commands validate against
the derived state under a lock; they never duplicate that truth into a counter.

### Movement is one causal placement chain

`livestock_cohort_movements` is append-only and models the same hardened causal
linked list the GF-020 lifecycle uses:

- `UNIQUE (previous_movement_id)` — a predecessor placement can be consumed by
  at most one successor, so two valid "next movements" cannot exist;
- a partial unique index gives at most one chain root per Cohort;
- a composite FK on `(previous_movement_id, organization_id, project_id, cohort_id)`
  keeps a predecessor inside the same Cohort and tenant;
- a `BEFORE INSERT` validator proves the declared source equals the real
  predecessor placement — the opening placement for a root, the predecessor's
  destination otherwise — so privileged and import paths cannot forge a
  successor either;
- `CHECK (source_site_id <> destination_site_id OR source_herd_id <> destination_herd_id)`
  rejects a no-op movement in the database, not only in the command.

The command additionally takes a per-Cohort advisory transaction lock and
re-derives the current placement under it. The browser-supplied source is
treated as a stale-view detector, never as truth.

### Current placement is resolved, and ambiguity is refused

`livestock_current_placement_movement` returns the unique unconsumed tip and
**raises** when more than one exists. `LIMIT 1` is never used to paper over a
corrupt graph. `livestock_cohort_current_placement` returns exactly one row per
valid Cohort with `placement_source ∈ {OPENING, MOVEMENT}`; nothing is persisted.

### Quantity rollforward is architecture-only in GF-021

`livestock_quantity_events` is an exact integer ledger whose sign comes from a
registered class in `livestock_quantity_event_types`. GF-021 registers **zero**
classes, because GF-021 implements no quantity-changing event. No event type is
fabricated to make the table look populated. The rollforward view is real and
truthfully reports `current_quantity = opening_headcount`. GF-022 adds its
classes and rows additively, with no destructive migration.

### Weight is an immutable measurement, not a Cohort property

`livestock_weight_events` supports `INDIVIDUAL_MEASURED`, `COHORT_TOTAL`,
`SAMPLED_AVERAGE`, and `ESTIMATED`. Method-specific required and forbidden
metadata is a table CHECK constraint, so the database itself refuses a sampled
average without a sample size, an estimate dressed up with a measured count, or
a cohort total carrying sample metadata. `SAMPLED_AVERAGE` additionally requires
an evidence reference. A trigger and the command both reject a sample size or
measured count greater than the current derived quantity.

`SAMPLED_AVERAGE` is available here — unlike the GF-020 opening-weight basis
that ADR 0020 deliberately removed — precisely because a WeightEvent can now
carry the sample size and evidence that make the figure honest.

The read model publishes `value_meaning` and `is_estimate` so an average per
sampled head is never rendered as a measured cohort total.

### No Finance side effect

No journal, payment, valuation, IAS 41, biological-asset, or COGS artifact is
created or touched. Shared Finance Core remains the single authoritative ledger.

## Deferred to GF-022 and later

GF-022 adds BIRTH, MORTALITY, SPLIT and MERGE quantity events with conservation
invariants and multi-session concurrency. Health/medicine/withdrawal,
vaccination, reproduction/pregnancy/breeding, individual Animal/RFID identity,
feed formulation/inventory/FCR, procurement, sales/receivables/revenue,
profitability, closeout, dairy, IAS 41 and fair-value accounting, GIS, IoT, AI,
and offline sync all remain out of scope.
