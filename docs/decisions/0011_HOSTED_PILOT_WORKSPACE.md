# ADR 0011 — One coherent hosted workspace for the Real Estate pilot

**Status:** Accepted
**Date:** 2026-08-13

## Decision

The hosted application presents one coherent project workspace in business
language instead of engineering slice names. The operator sees nine sections —
نظرة عامة، رأس المال، الأصول العقارية، التكاليف والنقدية، الإيراد والبيع،
الإغلاق والتوزيع، كشوف الشركاء، الاستيراد والمطابقة، الرقابة والجاهزية — each
backed by the existing canonical read models and RPCs. No second workflow engine
and no browser-side recomputation of accounting truth was introduced.

## What this adds

- A business-facing workspace shell and a shared `WorkspaceNav` (nine sections).
- A project **Overview** page aggregating only canonical numbers (capital, cash,
  obligations, realized result, distributions, accounting period, close and
  reconciliation status, unresolved control blockers).
- A **Revenue / sale** page, a **Partner Statements** page, and a **Controls /
  Audit** readiness panel.
- A pilot-readiness panel that keeps **technical readiness** and **real-world
  evidence** strictly separate: rehearsal success can never satisfy a buyer/UAT
  gate.

## Truthfulness rule

The permanent demo (DEMO-RE-2026-001) is synthetic. It is used for verification,
training, presentation, and regression only. It never satisfies canonical Phase 2
or Phase 3 evidence gates. The real-world evidence section stays explicitly not
satisfied for the demo.

## Consequences

- No new ledger, importer, or workflow engine. Operator actions continue to use
  the canonical RPC/command path with RLS, maker/checker, idempotency,
  append-only history, closed-period protection, balanced journals, and
  concurrency controls intact.
- Phase 2 remains a real-data gate: a real project's signed source balances must
  be imported and reproduced at zero unexplained variance.
- Phase 3 remains a real-data staging gate.
