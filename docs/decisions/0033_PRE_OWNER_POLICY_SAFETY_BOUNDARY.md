# ADR 0033 — Pre-Owner Policy Safety Boundary

**Status:** Accepted (corrective engineering; not a business-policy decision)
**Date:** 2026-08-16
**Scope:** policy-dependent investor-economics runtime

## Context

The independent pre-owner evidence audit (`docs/PRE_OWNER_POLICY_AUDIT.md`)
established that R1–R13 contain valid policy-independent product work, but that
several investor/funding/allocation/distribution mechanisms remain
policy-reachable while BD-001…BD-012 are still OPEN:

- the S5 allocation/distribution RPC chain has execute grants and internal
  membership/OWNER/maker-checker gates, but no separate policy-activation gate,
  so it is database-executable rather than policy-inert;
- the OWNER-gated `attach_contribution_cash` posts Dr BANK_CASH /
  Cr CONTRIBUTED_CAPITAL, imposing an equity classification before BD-002/005
  (funding source / funding mechanism) are resolved;
- any active MEMBER can activate the one governing agreement and issue
  policy-bearing capital calls (BD-002/003/005 OPEN);
- live intake mandates investor + agreement + positive commitment for every
  project (BD-002/003/005 OPEN);
- pilot/control surfaces expose partner-capital and investor-statement values
  as technical readiness;
- the S5 allocable-result source is RE-sale-only yet labeled the universal
  `REALIZED_RESULT`, and the S5 capacity bridge is labeled "distributable cash";
- S5 distribution payments have no shared bank-reconciliation path.

This corrective mission makes policy-dependent runtime **fail closed** until an
explicit, approved policy authority exists. It resolves no BD, invents no
company economics, and does not start R15.

## Decision

Introduce a **policy-activation boundary** with six explicit layers:

1. **Mechanism availability** — every existing table/view/RPC/journal/reversal
   mechanism is preserved intact (no second ledger, no rules engine, no deleted
   history).
2. **Business-policy activation** — a per-organization `policy_authority`
   registry records an *approved* policy for a scope
   (`INVESTOR_ECONOMICS`, `CAPITAL_CONTRIBUTION`). It ships **EMPTY**: no target-
   company policy is approved, so the current state is inert.
3. **Professional determination** — the registry row is created only by an
   owner/professional approval flow outside this migration; it is never seeded
   with fake rows, placeholder percentages, or environment flags.
4. **Owner/business approval** — the registry's `approved_by` + `evidence_reference`
   + `policy_version` make an activation an auditable, versioned authority.
5. **Runtime authorization** — a canonical gate `require_policy_activated` is
   enforced at the database boundary (triggers on the S5 write tables; the
   `attach_contribution_cash` command; OWNER gates on S1 activation/call).
6. **Historical evidence** — reads, journals, reversals and audit facts remain
   readable and reversible regardless of activation.

Concrete runtime changes (migration `20260816062000_pre_owner_policy_safety.sql`):

- `policy_authority` table + `require_policy_activated(org, scope)` gate.
- S5 write tables (`s5_allocation_rule_sets`, `s5_allocation_runs`,
  `s5_distributions`, `s5_distribution_payments`) are policy-gated for
  `INVESTOR_ECONOMICS`.
- `attach_contribution_cash` requires `CAPITAL_CONTRIBUTION`.
- `activate_agreement_version` and `create_capital_call` require OWNER.
- `s5_realized_result_as_of_snapshot` (source category `REALIZED_RESULT`) is
  truthfully read-labeled via `COMMENT ON FUNCTION` / `COMMENT ON COLUMN` and
  the terminology matrix — Real Estate sale result only, never a universal
  Project realized result.
- `s5_distribution_capacity_read.distributable_cash_minor_units` →
  `technical_capacity_bridge_minor_units`.
- S5 distribution payments reconcile through the shared
  `bank_statement_reconciliation_allocations` one-line reservation with match
  type `DISTRIBUTION_PAYMENT`.
- `s7_pilot_acceptance_report_read` no longer derives partner-capital or
  investor-statement values.

Intake readiness (`src/features/intake/readiness.ts`) reclassifies
`DS03_PARTIES` / `DS04_AGREEMENT` / `DS05_COMMITMENTS` from MANDATORY to
CONDITIONAL: their absence is `NOT_APPLICABLE` (policy-blocked), never a
readiness gate, and never instructs the operator to "add an investor first".

## Consequences

- **Positive:** policy-dependent writes are inert before owner/professional
  approval; R1–R13 policy-independent capabilities (Organization → Portfolio →
  Projects → sector operations → finance → evidence) are untouched; the target-
  company operating model is preserved; all historical rows and reversals remain
  readable.
- **Negative:** the S5 mechanism can no longer be exercised by an unactivated
  tenant — intended. Test fixtures that verify the mechanism now establish a
  clearly-labeled synthetic policy activation (test data only).
- **Blocked:** BD-001…BD-012 remain OPEN; R15 is not started; no company
  economics are invented.

## Rejected alternatives

- Revoking all S5 execute grants — breaks the mechanism's own verification and
  any historical/reversal surface, and is a blunt "revoke everything" that this
  boundary deliberately avoids.
- An environment flag as business authority — not a versioned, auditable
  authority and explicitly prohibited.
- Seeding a fake "approved policy" row — prohibited; the registry starts empty.

## Related

- `docs/PRE_OWNER_POLICY_AUDIT.md`
- `docs/OPEN_BUSINESS_DECISIONS.md` (BD-001…BD-012 OPEN)
- `docs/R14_POLICY_IMPACT_MATRIX.md`
- `docs/TERMINOLOGY_REALIZED_RESULT.md`
