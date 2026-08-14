# Terranex Greenfield

Terranex is an Arabic-first Investment Operations OS for Egyptian and MENA private investment operators. It is being rebuilt as a clean Greenfield product; legacy code is frozen and non-authoritative.

## Current status

- Phase: GF-019 — Agriculture Profitability, Cycle Closeout & Technical Gate is the active final Agriculture phase on top of merged GF-013–GF-018.
- S0-S7, GF-010, GF-011, and GF-012 are merged to `main`; the permanent realistic Real Estate showcase (`DEMO-RE-2026-001`) remains preserved as explicitly synthetic data.
- GF-013 expands `investment_projects.sector` to `REAL_ESTATE | AGRICULTURE` and ships Agriculture as a sibling feature under `src/features/agriculture`. No second ledger, no second audit trail, no weakened RLS, no fabricated finance.
- Architecture: one Next.js modular monolith + one Supabase/PostgreSQL backend, Arabic/RTL and EGP-ready, sectors Real Estate and Agriculture (bounded slices only; Livestock remains deferred).
- Hosted operator workspace: Real Estate keeps its nine business sections unchanged; Agriculture has its own project-scoped Arabic/RTL workspace at `/projects/[projectId]/agriculture` for land control, Farm/Field/CropCycle operations, activities, inputs, harvest/inventory, and bounded sales/collection. Project creation requires an explicit sector (`عقارات` / `زراعة`).
- **Status boundary:** Real Estate is technically implemented for its authorized scope. Agriculture GF-013 through GF-018 are merged and technically complete; GF-019 is the active final technical gate. The synthetic demo is never customer evidence and Phase 2/3 remain not passed.
- **Next construction sequence:** complete GF-018 sale/dispatch/revenue, then independently merge GF-019 profitability/closeout/technical gate. Livestock follows only after the Agriculture technical gate passes.

Read [`AGENTS.md`](AGENTS.md), [`GREENFIELD_EXECUTION.md`](GREENFIELD_EXECUTION.md), the eight files under [`docs/greenfield`](docs/greenfield), and the accepted decisions under [`docs/decisions`](docs/decisions) before implementation.
