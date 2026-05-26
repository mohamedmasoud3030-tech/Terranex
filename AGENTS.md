# Terranex Project Working Notes

Terranex is a standalone investment operating system repository.

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
- `.ai/skills/` contains reusable task skills.
- `.ai/pipelines/` contains batch-processing and analysis scripts.
- `tools/` may contain developer utilities when an executable does not belong under `.ai/`.

## Engineering preferences

- Prefer clear Markdown documentation before implementation.
- Keep financial logic auditable and traceable.
- Prefer deterministic parsing and explicit schema contracts.
- Prefer `rg` and `rg --files` for repository search when available.
- Keep generated outputs out of source control unless they are examples or fixtures.
