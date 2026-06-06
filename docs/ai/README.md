# Terranex AI Operating Guide

`AGENTS.md` is the canonical repository policy. `IMPLEMENTATION_GUIDE.md` is the current runtime map.

## Read in order

1. `../../AGENTS.md`
2. `../../IMPLEMENTATION_GUIDE.md`
3. `data-safety.md`
4. `release-policy.md`
5. `../decisions/README.md`
6. `../../.ai/workflows/README.md`

When a task touches roadmap or ERPNext-reference work, also read the relevant documents under `docs/reference/` and `docs/plans/`.

## Documentation rules

- Keep Terranex independent from Rentrix and other applications.
- Keep durable product and architecture decisions under `docs/decisions/`.
- Put repeatable execution playbooks under `.ai/workflows/`.
- Treat actual runtime code and versioned migrations as the source of truth when documentation drifts.