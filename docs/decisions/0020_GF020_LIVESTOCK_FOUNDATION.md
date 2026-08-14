# ADR 0020 — GF-020 Livestock cohort-first foundation

**Status:** Accepted for GF-020  
**Date:** 2026-08-14

## Decision

Livestock begins with two project-scoped branches that meet at Cohort:

- `Investment Project → Livestock Profile`
- `Investment Project → Sites` and `Investment Project → Herds`
- `Cohort → Herd`, with one immutable opening placement at a Site

A Cohort—not an individual Animal—is the primary quantity-bearing object. Individual identity remains optional and deferred until breeding value, regulation, tags, or animal-specific history proves it necessary.

A Site is an operational farm, barn, pasture, or other location. It is **not** land ownership, legal title, a Property Asset, or an Agriculture Land Asset, and creating it has no asset or consideration side effect. A Herd is a project-scoped managerial grouping that owns species and purpose (`MEAT | BREEDING | MIXED`), but does not own a current Site. A Cohort belongs to a Herd and records exactly one immutable opening placement at a same-project Site. GF-021 may add explicit movement events; only then can current placement be derived from the placement/movement chain. GF-020 stores no mutable `current_site_id`.

Cohort origin and positive integer opening headcount are immutable operational provenance. No mutable `current_headcount` is stored; later quantity is derived from explicit rollforward events. Optional opening weight records value, kilograms, and one defensible basis: `INDIVIDUAL_MEASURED`, `COHORT_TOTAL`, or `ESTIMATED`. Sampled averages are deferred to GF-021 `WeightEvent`, where sample size and evidence can be represented rather than implying false precision.

Lifecycle history is one database-enforced causal linked list per Cohort: exactly one `PLANNED` root, same-Cohort predecessor links, predecessor-state agreement, one child per predecessor, and exactly one tip. GF-020 supports only `PLANNED → ACTIVE` through an idempotent append-only transition. Closing, sale, loss, split, and movement are omitted until their causal events exist.

`PURCHASED` means operational quantity entered by purchase. It does not create payment, obligation, journal, valuation, COGS, or profit. All Finance and investor truth remains in the shared core.

## Deferred

GF-021+ may add movement, headcount rollforward, mortality and weight events—including correctly evidenced sampled measurements—followed by health/medicine, reproduction and optional individual identity, feed controls, sale/collection, and profitability/closeout. GF-020 creates no Animal/RFID, movement, health, feed, breeding, sale, dairy, GIS, IoT, or livestock-accounting scaffolding.
