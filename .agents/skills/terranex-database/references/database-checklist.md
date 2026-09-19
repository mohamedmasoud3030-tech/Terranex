# Terranex PostgreSQL / RLS Checklist

Apply only relevant items.

## Schema and grain

- Row grain is documented.
- organization_id is present on tenant-owned records.
- Cross-tenant foreign/reference paths are constrained.
- Monetary columns use an approved exact representation.
- Currency is part of the key/grouping whenever amounts from more than one currency can exist.
- Result basis/status/qualification is preserved when it changes meaning.
- Required uniqueness is enforced in PostgreSQL, not only TypeScript.

## RLS and privileges

- RLS is enabled where tenant-owned data requires it.
- Policies enforce the intended read/write scope.
- Policy predicates follow the repository's current membership/auth model.
- Application WHERE clauses are not the only tenant boundary.
- SECURITY DEFINER functions have the minimum required privilege, controlled search_path, safe qualification, and restricted EXECUTE exposure.
- Sensitive helper functions cannot be called by PUBLIC unless explicitly intended.
- Policy predicates and membership lookups have supporting indexes where needed.

## Migrations

- Existing applied migrations are untouched.
- Migration is forward-only and ordered.
- Backfill is deterministic and bounded.
- Destructive changes have compatibility/recovery handling.
- Views/functions dependent on changed objects are recreated in a safe order.
- Re-running the canonical migration chain succeeds from a clean database.
- Upgrade from the supported prior state is covered when relevant.

## Commands and accounting integrity

- Multi-table material writes are atomic.
- Idempotency key semantics match the logical command lifecycle.
- Duplicate retry cannot double-post.
- Concurrency cannot bypass uniqueness or state transitions.
- Posted facts are corrected by approved reversal/repost, not mutation.
- Period/status locks are enforced at the authoritative layer.

## Testing

- Positive path.
- Negative authorization path.
- Two-tenant isolation.
- Invalid cross-tenant reference.
- Dangerous legacy behavior negative control for a bug fix, when feasible.
- Currency/grain mixing case for financial aggregates.
- Replay/idempotency case.
- Concurrency case when the invariant is race-sensitive.
- SECURITY DEFINER/public-execute case when privileged functions change.
- Migration replay/upgrade.

## Performance

Use EXPLAIN/ANALYZE or production-like reasoning only when performance is in scope.

Prioritize:
1. missing/incorrect indexes on real query and RLS predicates;
2. connection behavior for serverless access;
3. schema design;
4. locking/concurrency;
5. access-pattern inefficiencies.

Do not optimize speculative workloads.
