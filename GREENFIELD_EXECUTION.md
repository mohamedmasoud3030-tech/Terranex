# Greenfield Execution Status

**Updated:** 2026-08-11
**Working branch:** `greenfield/foundation`
**Strategy:** Product-first, Egypt-first, vertical slices

## Completed foundation

- Legacy product frozen at `legacy/pre-greenfield-20260810`; it is not a source for Greenfield behavior.
- Eight Greenfield product documents approved as the conceptual baseline.
- Product-first Egypt launch recorded in `docs/decisions/0001_PRODUCT_FIRST_BUILD.md`.
- Simple modular-monolith delivery recorded in `docs/decisions/0002_SIMPLICITY_AND_VERTICAL_SLICES.md`.
- Customer interviews and a design partner are not build prerequisites.

## Completed batches

### GF-002 / S0 — Executable Foundation and Project Shell

Status: **COMPLETE**.

Merged through PR #84 into `greenfield/foundation` after the Greenfield CI gate passed in full.

Delivered and verified:

- Arabic-first responsive Next.js App Router shell with authentication entry.
- Organization creation/current-organization resolution.
- Real Estate investment project shell: create, list, and open.
- Supabase migration with organizations, memberships, projects, minimal append-only audit events, default-deny RLS, and cross-tenant integrity.
- Server-authoritative validation and commands.
- Deterministic npm dependency lock and Greenfield CI using `npm ci`.
- PostgreSQL 16 fresh replay and two-tenant isolation.

### GF-003 / S1 — Terms & Funding

Status: **COMPLETE — VERIFIED FOR INTEGRATION**.

Integration PR: **#88**, reconstructed directly from the current `greenfield/foundation` after the original Arena PR #87 was found to be based on a stale Greenfield lineage.

Delivered:

1. Tenant-scoped parties and project investors for the S1 workflow.
2. One project agreement envelope with immutable commitment-bearing versions.
3. One governing activated version in S1; participant changes and agreement amendments are frozen after activation until a dedicated amendment/carry-forward workflow exists.
4. Capital calls against the governing version with commitment ceilings.
5. Append-only contributions linked to exact project, investor, capital call, and governing agreement version.
6. Exact project/partner capital positions derived from authoritative records rather than editable balance columns.
7. Arabic/RTL Terms and Funding workflows with normal user-facing currency input rather than minor-unit entry.
8. Exact money transport: PostgreSQL `bigint` storage, text transport to JavaScript, decimal-text parsing with integer arithmetic, and no floating-point financial calculation.
9. Payload-bound idempotency for agreement drafts, capital calls, and contributions.
10. Database-enforced tenant/project scope plus browser table-write denial.

Verified on PostgreSQL 16 and the application CI gate:

- `npm ci` — PASS
- lint — PASS
- focused unit/contract tests — PASS
- production Next.js build — PASS
- TypeScript typecheck — PASS
- fresh migration replay S0 → S1 — PASS
- two-organization RLS isolation — PASS
- same-tenant cross-project reference rejection — PASS
- activated agreement/commitment immutability — PASS
- idempotent same-payload retries and mismatched-payload rejection — PASS
- exact capital rollforward — PASS
- real two-session concurrent over-call protection — PASS
- real two-session concurrent over-contribution protection — PASS
- direct authenticated browser DML denial — PASS

Canonical S1 decision: `docs/decisions/0003_S1_TERMS_AND_FUNDING.md`.

## Explicitly deferred

- agreement amendment/supersession and funding carry-forward rules;
- capital-call cancellation accounting beyond the minimal state representation;
- project subledger / double-entry posting;
- supplier/customer obligations, payments, reconciliation, and bank statement handling;
- allocation and distributions;
- generic approvals engine, documents/storage, notifications, outbox/queues, integrations, and country tax/e-invoicing;
- PWA/offline sync;
- Agriculture and Livestock runtime modules;
- generic repositories, CQRS/event-sourcing frameworks, plugin/rules engines, package workspaces, and speculative shared layers.

## Next active batch

`GF-004 / S2 — Cost & Cash`

Implement the smallest production-grade Real Estate slice that records one project obligation, applies the required authorization/approval boundary without introducing a generic approvals framework, posts the resulting project financial effect through a balanced immutable subledger, records payment from a project cash/bank account, and reconciles the book payment to an imported bank-statement fact. The exact states, posting semantics, reversal behavior, and UI are decided from the verified S0/S1 implementation plus the Greenfield finance contract.

GF-004 must preserve the separation between obligation, expense/capitalizable cost, payment, bank statement, reconciliation, and posting. It must not infer project economics from bank movements alone, and it must not expand into general ledger, tax, allocation/distribution, external accounting, or unrelated sector workflows.

## Decision rules

- One canonical implementation per concept.
- Search and extend before creating.
- A shared abstraction requires two real consumers.
- Every batch finishes one user workflow across all affected layers.
- Resolve architecture only when the active slice requires it.
- Money and ownership semantics must be exact, server-authoritative, tenant-safe, and auditable.
- Start every implementation branch from the exact latest `origin/greenfield/foundation`; before delivery it must be zero commits behind that target and show no unrelated legacy churn.
- No production deployment or production data changes without explicit authorization.
