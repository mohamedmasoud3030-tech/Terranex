# Greenfield Execution Status

**Updated:** 2026-08-10
**Working branch:** `greenfield/foundation`
**Strategy:** Product-first; Egypt is the first operating market

## Completed foundation

- The former Terranex product is frozen on `legacy/pre-greenfield-20260810`.
- Legacy runtime, migrations, tests, integrations, CI, agent instructions, and non-Greenfield documents are removed from the Greenfield working tree.
- The eight Greenfield documents remain the product baseline, updated only through explicit recorded decisions.
- Agent policy prevents accidental inheritance of legacy business logic.
- Product-first execution is recorded in `docs/decisions/0001_PRODUCT_FIRST_BUILD.md`.
- `main` is unchanged and remains a temporary safety point until a future explicitly approved replacement.

## Active phase

Phase 0 foundation is complete. **Phase 1 — architecture runway and executable product foundation is authorized.**

Customer interviews, a committed design partner, or customer documents are not build prerequisites. Terranex will implement the common Investment Operations Core and the first sector pack from the approved Greenfield model, established industry patterns, authoritative standards, and executable acceptance scenarios.

## Launch assumptions

- First operating market: Egypt.
- Primary language and layout: Arabic/RTL, with English/LTR support.
- Launch currency/configuration: EGP-ready; the shared core remains multi-currency.
- First sector-pack default: real estate, unless Mohamed explicitly changes it.
- Company differences are handled through configuration, policies, templates, and bounded extensions—not tenant-specific forks or hardcoded customer logic.
- Egypt-specific legal, tax, statutory accounting, and e-invoicing behavior stays isolated until reviewed by qualified Egyptian professionals before production reliance.

## Next bounded batch

Execute GF-002: establish the maintained Next.js/TypeScript repository and CI foundation, write the required architecture/accounting ADRs, define the common command/state/authorization contracts, and add executable acceptance fixtures for J1–J8 before implementing material financial posting.

## Decision rules

- Approved Greenfield decisions and authoritative standards outrank legacy behavior.
- Common behavior belongs in the shared core; sector behavior belongs in its bounded context; company variation belongs in configuration or explicit extensions.
- Synthetic fixtures are allowed for tests and must be clearly labeled; fabricated customer evidence is forbidden.
- Customer feedback may improve or extend the product after onboarding, but it does not retroactively make one company’s workflow the universal model.
- No production deployment or production financial use occurs until the relevant security, accounting, data-migration, and Egypt-specific compliance gates pass.
