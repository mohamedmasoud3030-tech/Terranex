# Terranex Greenfield

Terranex is an Arabic-first Investment Operations OS for Egyptian and MENA private investment operators. It is being rebuilt as a clean Greenfield product; legacy code is frozen and non-authoritative.

## Current status

- Phase: GF-010 — hosted Real Estate pilot workspace and real-project intake readiness.
- S0–S7 vertical slices merged to `main`; the permanent realistic Real Estate showcase (DEMO-RE-2026-001) is preserved and operable from the hosted application.
- Architecture: one Next.js modular monolith + one Supabase/PostgreSQL backend, Arabic/RTL and EGP-ready, first sector Real Estate.
- Hosted operator workspace: one coherent project workspace (نظرة عامة، رأس المال، الأصول العقارية، التكاليف والنقدية، الإيراد والبيع، الإغلاق والتوزيع، كشوف الشركاء، الاستيراد والمطابقة، الرقابة والجاهزية) built entirely on canonical read models and RPCs.
- **Truthfulness:** the permanent demo is synthetic demonstration data. It is used for verification, training, presentation, and regression — it is **not** customer evidence and does not satisfy canonical Phase 2 or Phase 3 exit gates. Phase 2/3 remain **not passed** until a real project's signed source balances are imported and reproduced at zero variance.

Read [`AGENTS.md`](AGENTS.md), [`GREENFIELD_EXECUTION.md`](GREENFIELD_EXECUTION.md), the eight files under [`docs/greenfield`](docs/greenfield), and the accepted decisions under [`docs/decisions`](docs/decisions) before implementation.
