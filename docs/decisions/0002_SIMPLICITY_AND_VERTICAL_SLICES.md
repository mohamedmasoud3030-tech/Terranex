# ADR-0002 — Simplicity Contract and Vertical-Slice Delivery

**Status:** Accepted
**Date:** 2026-08-10
**Decision owner:** Mohamed

## Decision

Terranex will be built as one production-grade modular monolith, delivered through small end-to-end slices. Simplicity is a constraint, not a later cleanup task.

1. Use one Next.js App Router application, one Supabase project, and one PostgreSQL database.
2. Organize code by business feature under `src/features`; use `src/shared` only for code with at least two real consumers.
3. Keep one canonical implementation for each concept. Before creating an entity, service, route, component, formatter, permission helper, or migration, search for the existing owner and extend it.
4. Build only what the active user workflow requires. Conceptual domain models describe boundaries; they are not a checklist of tables or packages.
5. Finish each slice across UI, server command, database/RLS, validation, audit, Arabic/RTL states, and targeted tests before starting another slice.
6. Use Supabase Auth, RLS, Storage, PostgreSQL constraints, and transactions instead of recreating platform capabilities.
7. Prefer direct, typed application code over speculative abstractions. Introduce an interface only for a real external boundary or when multiple implementations exist.
8. Company variation uses small typed configuration, templates, and explicit bounded extensions. Never fork the application or duplicate a feature per tenant.

## Forbidden until proven necessary

- microservices or multiple deployables;
- monorepo/internal package workspaces;
- CQRS frameworks, event sourcing, generic repositories, service locators, plugin engines, or generic rules engines;
- transactional outbox/inbox, queues, webhooks, or integration infrastructure without an actual external consumer;
- PWA service worker, IndexedDB, offline sync, conflict engine, or background jobs before a validated offline workflow;
- Agriculture and Livestock runtime modules before the Common Core and Real Estate slice are working;
- empty layers, placeholder domain entities, unused APIs, prebuilt dashboards, or “future-proof” dependencies;
- a second design system, money formatter, permission model, status vocabulary, or competing source of truth.

## Initial repository shape

```text
src/
├── app/
├── features/
│   ├── auth/
│   ├── organizations/
│   └── projects/
└── shared/
    ├── ui/
    ├── validation/
    └── money/
supabase/
├── migrations/
└── tests/
```

Folders are created only when the first file that belongs there is implemented.

## First executable slice

`GF-002 / S0` must produce a runnable Arabic-first application where an authenticated user can create or join an organization, create a Real Estate investment project shell, and list/open that project. The database must enforce organization isolation and project ownership. The slice includes minimal audit evidence, truthful empty/loading/error states, and two-tenant tests.

It does not implement agreements, postings, approvals, documents, offline behavior, other sectors, or external integrations.

## Extraction rule

A module or service may be extracted only when all are true:

- at least two real consumers or implementations exist;
- ownership and dependency direction are clear;
- the extraction removes measured duplication or isolates a real external boundary;
- targeted tests prove behavior before and after extraction.

## Consequences

- Working software begins immediately; ADRs are written only when the active slice needs a material decision.
- Architecture grows from verified workflows instead of speculation.
- Financial and tenant-safety invariants remain strict even while the codebase stays small.
- Deferred capabilities remain documented product options, not installed infrastructure.