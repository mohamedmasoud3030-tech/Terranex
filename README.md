# Terranex Greenfield

Terranex is an Arabic-first Investment Operations OS for Egyptian and MENA private investment operators. It is being rebuilt as a clean Greenfield product; legacy code is frozen and non-authoritative.

## Current status

- Phase: `GF-002 / S0` — executable product foundation.
- Strategy: product-first; customer interviews are not a coding prerequisite.
- Architecture: one Next.js modular monolith + one Supabase/PostgreSQL backend.
- First market: Egypt; Arabic/RTL and EGP-ready configuration.
- First sector: Real Estate.
- Production: not deployed from this branch.

## Active implementation boundary

The next batch builds a runnable application and the first complete slice: authentication, organization isolation, and a Real Estate project shell. Agreements, finance posting, approvals, documents, offline/PWA, integrations, Agriculture, and Livestock remain deferred.

Read [`AGENTS.md`](AGENTS.md), [`GREENFIELD_EXECUTION.md`](GREENFIELD_EXECUTION.md), the eight files under [`docs/greenfield`](docs/greenfield), and the accepted decisions under [`docs/decisions`](docs/decisions) before implementation.