# ADR 0010 — Guided real-project intake is an overlay, not a second engine

**Status:** Accepted  
**Date:** 2026-08-13

## Decision

The first real Real Estate project is entered through one Arabic guided workspace that calls the existing S0–S7 commands. Completeness is derived from those records. A thin declaration schema stores only facts the product did not already hold (freeze date, signed control totals, agreement title, conditional applicability, modelling gaps, evidence identifiers).

## Consequences

- No second ledger, no second opening importer, no browser writes to financial tables.
- Unmappable balances stop and become modelling gaps; they are never forced into a nearby S7 mapping code.
- Phase 2 remains a real-data gate. The overlay never self-advances it.
