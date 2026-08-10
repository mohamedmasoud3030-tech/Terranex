# Greenfield Execution Status

**Updated:** 2026-08-10
**Working branch:** `greenfield/foundation`
**Strategy:** Product-first, Egypt-first, vertical slices

## Completed foundation

- Legacy product frozen at `legacy/pre-greenfield-20260810`; it is not a source for Greenfield behavior.
- Eight Greenfield product documents approved as the conceptual baseline.
- Product-first Egypt launch recorded in `docs/decisions/0001_PRODUCT_FIRST_BUILD.md`.
- Simple modular-monolith delivery recorded in `docs/decisions/0002_SIMPLICITY_AND_VERTICAL_SLICES.md`.
- Customer interviews and a design partner are not build prerequisites.

## Active batch

`GF-002 / S0 — Executable Foundation and Project Shell`

Build one runnable Next.js application and one complete vertical slice:

1. Arabic-first responsive shell with authentication entry.
2. Organization creation/current-organization resolution.
3. Real Estate investment project shell: create, list, and open.
4. Supabase migration with organizations, memberships, projects, minimal audit events, default-deny RLS, and cross-tenant integrity.
5. Server-authoritative validation and commands.
6. Truthful loading, empty, error, forbidden, and mobile/RTL states.
7. Targeted unit/database/integration tests, including two-tenant isolation.
8. Minimal CI for format/lint, typecheck, tests, and build.

## Explicitly deferred

- agreements, participants, capital calls, postings, ledger, payments, allocation, and distributions;
- approvals engine, documents/storage, notifications, outbox/queues, integrations, and country tax/e-invoicing;
- PWA installation, service worker, IndexedDB, offline drafts, and sync/conflict handling;
- Agriculture and Livestock runtime modules;
- generic repositories, CQRS/event-sourcing frameworks, plugin/rules engines, package workspaces, and speculative shared layers.

## Exit gate

GF-002 is complete only when a fresh checkout can install, validate environment inputs, replay migrations, run the targeted gates, build successfully, and demonstrate that:

- an authenticated organization member can create and open a Real Estate project;
- a second organization cannot read or mutate that project through UI, server command, or database policy;
- the implementation contains no legacy code, duplicate source of truth, unused architecture scaffolding, or secrets.

## Next after GF-002

GF-003 will implement the smallest Terms & Funding slice required for project agreement activation and contribution recording. Its exact scope is decided from the verified GF-002 codebase, not pre-scaffolded now.

## Decision rules

- One canonical implementation per concept.
- Search and extend before creating.
- A shared abstraction requires two real consumers.
- Every batch finishes one user workflow across all affected layers.
- No production deployment or production data changes without explicit authorization.