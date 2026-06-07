# Terranex Project Working Notes

Terranex is a standalone investment operating system repository.

## Read before editing

1. `IMPLEMENTATION_GUIDE.md`
2. `docs/ai/README.md`
3. `docs/ai/data-safety.md`
4. `docs/ai/release-policy.md`
5. `docs/ai/agent-skills.md`
6. `docs/decisions/README.md`
7. `.ai/workflows/README.md`

When a task touches roadmap, ERPNext-reference work, or another external reading source, read the relevant files under `docs/reference/`, `docs/plans/`, and `reference/` before editing.

## Project boundary

This repository is independent from Rentrix and any other application. Product scope, domain model, documents, and automation assets in this repository belong to Terranex only.

## Product north star

The product should help the company answer four core questions:

1. What assets and projects do we own or operate?
2. What did each project cost and earn?
3. Did each project, season, herd, or asset make profit or loss?
4. Who owes money to the company, and who should the company pay?

## Repository organization

- `docs/` contains product, domain, roadmap, and decision documents.
- `.ai/agents/` contains role descriptions for AI-assisted project work.
- `.ai/skills/` contains Terranex-specific reusable task skills.
- `.ai/workflows/` contains repeatable Terranex execution playbooks.
- `.ai/pipelines/` contains batch-processing and analysis scripts.
- `reference/` contains pinned external reading contracts.
- `.reference-cache/` contains ignored local materialized references.
- `tools/` may contain developer utilities when an executable does not belong under `.ai/`.

## Source-locked engineering skills

Agents may use the pinned Addy engineering workflow pack recorded in `reference/agent-skills/source-lock.json`.

- Read `docs/ai/agent-skills.md` for local setup commands and the Terranex routing map.
- Load only task-relevant upstream skills. Do not flood context with the entire pack.
- Do not edit cached upstream files or import them into production code.
- Keep Terranex-specific rules in this repository's docs, workflows, and approved planning files.
- When generic upstream guidance conflicts with Terranex policy, Terranex policy wins.

## Engineering preferences

- Prefer clear Markdown documentation before implementation.
- Keep financial logic auditable and traceable.
- Prefer deterministic parsing and explicit schema contracts.
- Prefer `rg` and `rg --files` for repository search when available.
- Keep generated outputs out of source control unless they are examples or fixtures.
- Preserve dirty worktrees and avoid destructive Git operations.
- Keep each PR bounded to one approved stage.
