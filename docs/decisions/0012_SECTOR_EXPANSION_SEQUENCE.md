# ADR 0012 — Technical Sector Expansion Sequence

**Status:** Accepted
**Date:** 2026-08-13
**Decision owner:** Mohamed

## Context

Terranex has implemented the authorized Real Estate path through S0-S7, the coherent hosted workspace in GF-010, and the presentation-readiness changes in GF-011. Its permanent Real Estate showcase is synthetic by design. Terranex has not yet been presented to or operated by a real customer, so buyer UAT, commercial validation, and the real-evidence Phase 2/3 exits remain pending.

The previous roadmap could be read as making real-customer evidence a prerequisite for any second-sector construction. That is not the chosen product strategy. Customer evidence governs validation and commercial claims; it does not grant permission to continue building the already-approved three-sector product.

## Decision

The authorized construction sequence is **Real Estate first, Agriculture second, Livestock third**.

1. Real Estate remains the first implemented sector and is technically complete for the currently authorized scope.
2. Synthetic rehearsals and the permanent demo prove technical behavior only. They never count as customer acceptance, buyer UAT, a paid pilot, or real-evidence Phase 2/3 completion.
3. Agriculture is the second active sector. Its first batch is the bounded `Farm → Field → CropCycle` foundation.
4. Livestock is the third sector and begins only after Agriculture reaches its technical sector gate.
5. Sector construction is sequential. Each sector reuses the canonical Investment Core, Finance & Capital, Party, Documents, Workflow, authorization, audit, and workspace primitives.
6. A sector must not create a separate ledger, ownership model, payment engine, investor balance, approval framework, or audit truth.
7. Customer validation remains mandatory before any sector is described as commercially validated, production-proven, or accepted by a buyer.

## Consequences

- GF-013 may start after GF-012 closes governance and CI alignment even if no customer data exists.
- Agriculture is delivered through thin end-to-end slices, not by scaffolding every conceptual entity.
- The Real Estate pilot evidence track remains open and truthful without blocking Agriculture development.
- Livestock stays deferred until Agriculture proves the shared-core boundary and its own quantity/inventory lifecycle.
- Existing financial, tenant-isolation, maker-checker, immutability, reversal, and audit controls remain unchanged.
