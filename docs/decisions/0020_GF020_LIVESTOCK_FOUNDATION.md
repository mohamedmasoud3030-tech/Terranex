# ADR 0020 — GF-020 Livestock cohort-first foundation

**Status:** Accepted for GF-020  
**Date:** 2026-08-14

## Decision

Livestock starts with `Investment Project → Livestock Profile → Site → Herd → Cohort`. A Cohort—not an individual Animal—is the primary quantity-bearing object. Individual identity remains optional and deferred until breeding value, regulation, tags, or animal-specific history proves it necessary.

A Site is an operational farm, barn, pasture, or other location. It is **not** land ownership, legal title, a Property Asset, or an Agriculture Land Asset, and creating it has no asset or consideration side effect. A Herd is the stable managerial grouping that owns Site, species, and purpose (`MEAT | BREEDING | MIXED`); a Cohort is a count-bearing group sharing an origin. Cohort placement, species, and purpose derive through Herd, avoiding contradictory editable facts.

Cohort origin and positive integer opening headcount are immutable operational provenance. No mutable `current_headcount` is stored; later quantity is derived from explicit rollforward events. Optional opening weight records value, kilograms, and its honest basis together, distinguishing total, measured, sampled-average, and estimated evidence.

`PURCHASED` means operational quantity entered by purchase. It does not create payment, obligation, journal, valuation, COGS, or profit. All Finance and investor truth remains in the shared core.

GF-020 supports only `PLANNED → ACTIVE`, through an idempotent causal append-only transition. Closing, sale, loss, split, and movement are omitted until their causal events exist.

## Deferred

GF-021+ may add movement, headcount rollforward, mortality and weight events, followed by health/medicine, reproduction and optional individual identity, feed controls, sale/collection, and profitability/closeout. GF-020 creates no Animal/RFID, health, feed, breeding, sale, dairy, GIS, IoT, or livestock-accounting scaffolding.
