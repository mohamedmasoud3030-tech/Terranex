# Terranex Greenfield

Terranex is an Arabic-first Investment Operations OS for Egyptian and MENA private investment operators. It is being rebuilt as a clean Greenfield product; legacy code is frozen and non-authoritative.

## Current status

- Phase: GF-012 — governance, release control, and sector-sequencing closeout.
- S0-S7, GF-010, and GF-011 are merged to `main`; the permanent realistic Real Estate showcase (`DEMO-RE-2026-001`) remains preserved as explicitly synthetic data.
- Architecture: one Next.js modular monolith + one Supabase/PostgreSQL backend, Arabic/RTL and EGP-ready, first sector Real Estate.
- Hosted operator workspace: one coherent project workspace (نظرة عامة، رأس المال، الأصول العقارية، التكاليف والنقدية، الإيراد والبيع، الإغلاق والتوزيع، كشوف الشركاء، الاستيراد والمطابقة، الرقابة والجاهزية) built entirely on canonical read models and RPCs.
- **Status boundary:** Real Estate is technically implemented for its authorized scope, while its latest production-alias verification and real-customer validation remain separate evidence gates. The synthetic demo is never customer evidence and Phase 2/3 remain not passed.
- **Next construction batch:** GF-013 Agriculture Sector Foundation (`Farm → Field → CropCycle`), followed by later bounded Agriculture slices and then Livestock.

Read [`AGENTS.md`](AGENTS.md), [`GREENFIELD_EXECUTION.md`](GREENFIELD_EXECUTION.md), the eight files under [`docs/greenfield`](docs/greenfield), and the accepted decisions under [`docs/decisions`](docs/decisions) before implementation.
