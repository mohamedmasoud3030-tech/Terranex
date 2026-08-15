# ADR 0029 — Target-Company Pilot Focus Without Policy Invention

**Status:** Accepted  
**Date:** 2026-08-15

## Context

Terranex now has a concrete first target company identified by the product owner under the working name **المجموعة العربية المتحدة**, operating/intending to operate in Egypt across Real Estate, Agriculture and Livestock.

Owner-provided audio/transcript evidence establishes a multi-project private investment-operator model with project-separated accounting, sector-level diversification, durable assets, operator-managed opportunity/feasibility/execution, and strong investor transparency expectations. It also describes a Real Estate strategy that can include discounted cash acquisition, holding, rental income, approved value appreciation and eventual disposal.

The source does not establish the target company's legal vehicle structure, investor legal ownership, allocation/loss rules, operator economics, cross-project netting/recycling, reserve policy, tax treatment, asset legal owner, or investor lifecycle rules.

## Decision

1. Treat the target company as the **first pilot/design target**, not as permission to fork Terranex or hard-code tenant-specific behavior.
2. Keep the shared product model:
   `Organization → Investment Portfolio → Investment Project → Assets / Sector Operations → shared Finance/Control → derived Portfolio reporting`.
3. Prioritize completion of all target-company-relevant work that is independent of unresolved investor/legal/economic policy before asking the owner for the R14 policy pack.
4. The immediate execution order from the current merged baseline is:
   - Procurement Financial Integration;
   - remaining shared Asset/Budget/Forecast/Commitment/Portfolio-roll-up gaps;
   - target-company Real Estate holding/rental-income gap;
   - cross-sector owner performance and management UX/reporting;
   - safe Investor Transparency read models with entitlement fields inert;
   - production hardening;
   - full-company R13 simulation.
5. R13 must prove at least one multi-project Portfolio so separate Project accounting and diversification roll-up are real system behavior rather than a diagram.
6. The Real Estate proof must keep rental income, approved valuation and realized disposal result distinct.
7. Transparency features may expose published project/portfolio updates, evidence, documents, spend/progress and approved management facts, but may not compute or display investor entitlement without a resolved policy basis.
8. R14 remains the first point at which company-specific owner/contracts/accounting/legal evidence is required for the investor-policy tail.

## Consequences

- No new fund/SPV/legal-vehicle semantics are implied.
- No target-company fee/share/waterfall/netting rule is introduced.
- No customer-specific fork is allowed.
- Existing Real Estate/Agriculture/Livestock bounded contexts remain intact.
- Shared Procurement/Finance/Asset/Reporting components are completed once and reused across sectors.
- Work whose correctness is independent proceeds without waiting for interviews or policy answers.
- Work whose correctness depends on `BD-001`…`BD-012` remains fail-closed until resolved.

## Evidence references

- `docs/TARGET_COMPANY_REFERENCE.md`
- `docs/CURRENT_DELIVERY_STATUS.md`
- `docs/ROADMAP_R0_R17.md`
- `docs/OPEN_BUSINESS_DECISIONS.md`

This ADR records product prioritization and evidence boundaries only. It is not legal, accounting, tax, securities, or investment advice and does not assert that the working company name is the verified legal entity name.
