# Terranex Reviewer Routing

Select lenses from the diff; do not run every lens mechanically.

| Signal in the change | Reviewer lens | Primary questions |
| --- | --- | --- |
| Domain/business semantics, status, lifecycle | Canonical/domain | Is behavior authorized? Was any open business rule invented? |
| Money, capital, result, revenue, cost, valuation, FX | Financial semantics | Is amount qualified by currency/basis/grain? Any cross-currency sum, floating point, double count, or misleading label? |
| SQL, migrations, functions, views, policies | PostgreSQL/data integrity | Is grain correct? Forward migration safe? Constraints/indexes/policies correct? Upgrade/replay safe? |
| organization_id, membership, RLS, auth.uid, permissions | Tenant isolation/authz | Can one tenant read/write another tenant's data? Is authorization enforced server/database side? |
| Material commands, retries, posting, approvals | Reliability/audit | Atomic? Idempotent? Concurrency-safe? Version-aware? Auditable? Retry key lifecycle correct? |
| UI/components/forms/pages | UX/RTL/accessibility | Arabic/RTL correct? Failure/empty/loading states truthful? Keyboard/ARIA/responsive behavior preserved? |
| Uploads/private storage/evidence | Storage security | Private by default? Path authorization and object ownership correct? Signed access bounded? |
| Package/dependency/framework API | Source/version | Exact version detected? Official docs support the API? Deprecation/behavior change handled? |
| ADR/docs/architecture boundary | Architecture/governance | Does the change create duplicate cores or violate settled architecture? |
| Tests only | Test quality | Does the test prove behavior, or encode current implementation? Are negative controls missing? |

## Minimum lenses

Every non-mechanical review includes:
- correctness/regression;
- canonical-intent consistency.

Add specialized lenses based on the table.

## High-risk combinations

Use extra scrutiny when a change combines:
- money + currency conversion or aggregation;
- RLS + SECURITY DEFINER;
- migration + destructive rewrite/backfill;
- auth + server action/route handler;
- idempotency + retries/concurrency;
- reporting + cross-sector/cross-project aggregation;
- uploads + tenant paths;
- dependency upgrade + authentication/session behavior.
