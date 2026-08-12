# ADR 0008 — S5 Allocation & Distribution

**Status:** Implemented · **Date:** 2026-08-12

S5 consumes only an approved S6 close snapshot and persists its content hash, close identifiers, governing-version identifier, category, currency, and algorithm version. It never reads live S1–S4 facts to change an approved source. Allocation and distribution are separate models and distribution approval is distinct from payment.

The migration extends the locked S2 semantic account registry with `PROJECT_RESULT_CLEARING`, `PARTNER_CAPITAL`, and `DISTRIBUTION_PAYABLE`, and extends journal source types without creating a second ledger. All browser access is SELECT-only; commands are SECURITY DEFINER with a locked search path.

Money is PostgreSQL `bigint` minor units and is transported as text. Allocation weights are integer numerator/denominator pairs. The intended deterministic algorithm is exact rational entitlement, integer floor, then residual minor units by largest remainder with stable participant UUID ordering as tie-breaker. Advanced waterfalls, tax, FX, amendments, and bank execution remain deferred.
