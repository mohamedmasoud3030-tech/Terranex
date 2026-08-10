# ADR-0001 — Product-First Build and Egypt-First Launch

**Status:** Accepted
**Date:** 2026-08-10
**Decision owner:** Mohamed

## Context

Terranex is being rebuilt as a Greenfield Investment Operations OS. A previous Phase 0 proposal made three qualified customer interviews and one design partner prerequisites for implementation. That gate conflicts with the chosen execution strategy: build the established common product first, then configure or extend it for companies as real onboarding needs appear.

The first operating company is expected to be in Egypt.

## Decision

1. Start implementation without customer interviews, a design partner, or customer documents.
2. Build the common Investment Operations Core from the approved Greenfield model, established industry patterns, authoritative standards, and executable acceptance scenarios.
3. Keep real estate as the default first sector pack unless Mohamed explicitly changes it.
4. Treat Egypt as the first operating market: Arabic/RTL and EGP-ready configuration are launch priorities.
5. Handle company differences through tenant configuration, versioned policies, templates, mappings, feature flags, or explicit bounded extensions. Do not fork the product per company and do not hardcode customer-specific behavior into the common core.
6. Treat customer onboarding as validation and controlled adaptation, not as permission to begin coding.
7. Require qualified Egyptian accounting/legal review before production reliance on country-specific tax, statutory accounting, e-invoicing, investment-regulation, or contractual conclusions.

## Evidence hierarchy

For common behavior, use this order:

1. applicable authoritative standards and law;
2. mature industry workflow patterns and primary vendor documentation;
3. the approved Greenfield product/accounting decisions;
4. executable accounting, security, and workflow acceptance scenarios;
5. customer-specific practice, which remains configuration or an extension unless proven broadly applicable.

Legacy Terranex behavior has no authority.

## Consequences

- Phase 0 product foundation is complete and Phase 1 may begin.
- No commercial interview workspace or three-company GO/NO-GO gate is required.
- Synthetic test fixtures are allowed when clearly labeled; fabricated customer claims are forbidden.
- The platform must remain multi-tenant, multi-currency, and sector-bounded even though Egypt and real estate are launch priorities.
- First-company feedback can correct or extend the product, but cannot silently redefine the universal domain model.
