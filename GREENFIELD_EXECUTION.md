# Greenfield Execution Status

**Updated:** 2026-08-10
**Working branch:** `arena/019fed07-terranex` (GF-003 implementation; targets `greenfield/foundation`)
**Strategy:** Product-first, Egypt-first, vertical slices

## Completed foundation

- Legacy product frozen at `legacy/pre-greenfield-20260810`; it is not a source for Greenfield behavior.
- Eight Greenfield product documents approved as the conceptual baseline.
- Product-first Egypt launch recorded in `docs/decisions/0001_PRODUCT_FIRST_BUILD.md`.
- Simple modular-monolith delivery recorded in `docs/decisions/0002_SIMPLICITY_AND_VERTICAL_SLICES.md`.
- Customer interviews and a design partner are not build prerequisites.

## Completed batches

### GF-002 / S0 — Executable Foundation and Project Shell

Status: **COMPLETE** (merged through PR #84 into `greenfield/foundation` at `29e14e4`).

Delivered the Arabic-first Next.js shell, organization creation/membership, Real Estate project shell, default-deny RLS, append-only audit events, and server-authoritative commands.

### GF-003 / S1 — Terms & Funding

Status: **IMPLEMENTED AND VERIFIED ON BRANCH** (pending PR review; not merged).

Outcome delivered: **activate agreement → call capital → receive contribution → show exact capital position/history.**

Verified evidence (run on the reported commit):

1. Fresh migration replay from an empty database: S0 then S1 migrations apply in order.
2. Upgrade from the GF-002 schema: S1 migration applies on top of S0 without editing the prior migration.
3. PostgreSQL behavioral gate passes: two-organization isolation and cross-tenant participant/project rejection.
4. Agreement activation immutability and single-active-version rejection pass.
5. Capital calls reject non-active versions, invalid participants, and amounts exceeding commitments.
6. Contribution commands are idempotent (same key returns the same contribution and creates one economic effect), reject over-payment, and use row locking to prevent concurrent over-pay.
7. Exact integer minor-unit money and derived project/partner rollforwards assert to the exact pound.
8. Append-only triggers protect activated versions, commitment terms, contributions, and call lines.
9. Arabic/RTL workflow states for terms, funding status, calls, contributions, and history are rendered truthfully.
10. `npm run lint`, `npm run test`, `npm run build`, and `npm run typecheck` all pass.
11. Greenfield database gate passes against an embedded PostgreSQL 18-compatible runtime locally; CI uses the PostgreSQL 16 service defined in `.github/workflows/greenfield-ci.yml`.

Delivered:

- Tenant-scoped parties and `INVESTOR` project participants.
- One agreement per project with append-only `agreement_versions`; only one version may be active.
- Version-scoped `commitment_terms` in integer minor units.
- Issued capital calls with immutable lines and a commitment ceiling.
- Append-only contributions with exact governing version/call/participant and an organization-scoped idempotency key.
- Derived `project_capital_position` and `partner_capital_position` views; no editable balance columns.
- Arabic-first `/projects/[projectId]/terms` and `/projects/[projectId]/funding` pages.
- ADR `docs/decisions/0003_S1_TERMS_AND_FUNDING.md`.

Schema/domain decisions: see ADR 0003. Key choices: one agreement envelope per project; S1 introduces only `INVESTOR`; no ownership/equity percentage is derived from cash; single-currency contributions; no approvals engine, GL, documents, or distributions.

## Explicitly deferred

- Postings/subledger, receipts/payments beyond the S1 contribution fact, bank reconciliation, and period close;
- ownership/allocation terms, result allocation, distributions, and investor self-service;
- agreement amendment beyond append-only version superseding, notices/signatures, and document storage;
- generic approvals engine, notifications, outbox/queues, integrations, and country tax/e-invoicing;
- PWA/offline infrastructure;
- Agriculture and Livestock runtime modules;
- generic repositories, CQRS/event-sourcing, plugin/rules engines, package workspaces, and speculative shared layers.

## Next active batch

`GF-004 / S2 — Cost & cash` (to be defined in `GREENFIELD_EXECUTION.md` after GF-003 merges).

## Decision rules

- One canonical implementation per concept.
- Search and extend before creating.
- A shared abstraction requires two real consumers.
- Every batch finishes one user workflow across all affected layers.
- Resolve architecture only when the active slice requires it.
- Money and ownership semantics must be exact, server-authoritative, tenant-safe, and auditable.
- No production deployment or production data changes without explicit authorization.
