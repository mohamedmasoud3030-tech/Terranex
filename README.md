# Terranex Greenfield

Terranex is an Arabic-first Investment Operations OS for Egyptian and MENA private investment operators. It is being rebuilt as a clean Greenfield product; legacy code is frozen and non-authoritative.

## Current status

- Phase: GF-013 — Agriculture sector foundation (`Farm → Field → CropCycle`) implemented on top of the merged Real Estate path.
- S0-S7, GF-010, GF-011, and GF-012 are merged to `main`; the permanent realistic Real Estate showcase (`DEMO-RE-2026-001`) remains preserved as explicitly synthetic data.
- GF-013 expands `investment_projects.sector` to `REAL_ESTATE | AGRICULTURE` and ships Agriculture as a sibling feature under `src/features/agriculture`. No second ledger, no second audit trail, no weakened RLS, no fabricated finance.
- Architecture: one Next.js modular monolith + one Supabase/PostgreSQL backend, Arabic/RTL and EGP-ready, sectors Real Estate and Agriculture (bounded slices only; Livestock remains deferred).
- Hosted operator workspace: Real Estate keeps its nine business sections unchanged; Agriculture has its own project-scoped workspace at `/projects/[projectId]/agriculture` for `Farm → Field → CropCycle` and lifecycle transitions. Project creation now requires an explicit sector (`عقارات` / `زراعة`).
- **Status boundary:** Real Estate is technically implemented for its authorized scope. Agriculture is technically implemented for its first bounded slice. The synthetic demo is never customer evidence and Phase 2/3 remain not passed.
- **Next construction batch:** later bounded Agriculture slices (FieldActivity, InputItem, InputApplication, HarvestEvent, HarvestLot, etc.) per the deferred list in `supabase/migrations/20260813001000_agriculture_foundation.sql`, followed by Livestock after Agriculture reaches its technical sector gate.

Read [`AGENTS.md`](AGENTS.md), [`GREENFIELD_EXECUTION.md`](GREENFIELD_EXECUTION.md), the eight files under [`docs/greenfield`](docs/greenfield), and the accepted decisions under [`docs/decisions`](docs/decisions) before implementation.
