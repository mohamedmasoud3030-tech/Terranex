# ADR 0026 — Roadmap Alignment: R0–R17, Hard Stop Moved to R13

- **Status:** Accepted
- **Date:** 2026-08-15
- **Scope:** Canonical roadmap alignment (governance/documentation only; no runtime, schema, migration, UI, or database behavior changes)
- **Depends on:** ADR 0001 (product-first build), ADR 0002 (vertical slices), ADR 0012 (sector expansion sequence), ADR 0025 (R1 Portfolio Foundation), `docs/OPEN_BUSINESS_DECISIONS.md`, `docs/ROADMAP_R0_R17.md`
- **Reconciled lineage note:** this ADR was authored on the pre-R1 parallel branch as `0025_ROADMAP_ALIGNMENT_R0_TO_R17.md`. The canonical R1 Portfolio Foundation ADR kept `0025`, so this ADR is renumbered `0026` in the no-loss reconciliation. Its decision text is preserved; only references and numbering are reconciled.

## Context

The previous roadmap placed a hard stop at R5 for portfolio/investor economics, which risked asking the target company owner for business-policy answers while the product was still largely incomplete. The product owner has directed a re-alignment: **Build Everything Independent First** and move the hard stop from R5 to R13.

Real Estate (S0–S7/GF-010/GF-011), Agriculture (GF-013–GF-019), and Livestock (GF-020–GF-024) are already technically implemented for their authorized scopes. R0 — Canonical Portfolio Realignment & Anti-Hallucination Governance — is merged. The R1 — Portfolio Foundation slice (PR #139) is merged as the first runtime slice of the independent build. The remaining independent build (R4 procurement, remaining R2/R3 portfolio roll-ups + budget/forecast/commitment, R10 investor-transparency read-models, R11/R9 reporting/workspaces, R12 hardening, R13 full simulation) can proceed without waiting for any unresolved legal/economic decision.

## Decision

1. Adopt the **R0–R17** sequence defined in `docs/ROADMAP_R0_R17.md` as canonical, replacing the R1–R5-with-hard-stop-at-R5 framing in `docs/greenfield/08` and the stale "next active batch" text in `GREENFIELD_EXECUTION.md`.
2. Move the hard stop to **R13**: implement every feature whose correctness does not depend on unresolved legal/economic policy through R13; defer only the smallest rule-dependent portion.
3. After R13, ask the owner only the small **R14 policy pack** (the 13 questions in `docs/greenfield/08` section 16, mapping to `OPEN_BUSINESS_DECISIONS.md` BD-001…BD-012); then complete R15–R17.
4. The deferral rule: build the independent 90% of any feature now; keep only the entitlement/allocatable-number surface inert until the policy is fixed. Never invent a default, a fake percentage, an `OTHER` enum, a generic rules engine, or a guessed entitlement rule. Never display an investor profit/entitlement number computed from an unapproved basis.
5. No new fund/legal/SPV/investor-pool semantics at Portfolio level; Portfolio remains a management/reporting parent over project-authoritative truth.
6. This is documentation/governance only: it authorizes no schema, migration, route, service, runtime behavior, UI component, or placeholder.

## Consequences

- `AGENTS.md` "Current delivery gate" now describes the R0–R17 sequence and the R13 hard stop; R0 and the R1 Portfolio Foundation slice are recorded as merged.
- `docs/greenfield/08` sections 15–17 replace the R1–R5 + R5-hard-stop text with R1–R13 independent build, R13 hard stop, and R15–R17 policy-tail.
- `GREENFIELD_EXECUTION.md` "Next active batch" now lists the shared Procurement operational foundation as the first remaining independent gate and records that GF-023/GF-024 are merged.
- `README.md` current status now reflects the closed sector sequence, the merged R1 Portfolio Foundation, and the R0–R17 roadmap.
- Next bounded implementation slice: **R4 — Procurement & Shared Operations** (a fresh branch off current `origin/main`, zero commits behind, full changed-layer verification).
