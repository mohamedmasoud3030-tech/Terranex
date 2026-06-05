# Codex Task — Terranex-Native Engine Extraction Stage 0

## Mission

Prepare an implementation plan for rebuilding the best ERPNext engine behaviors as Terranex-native TypeScript modules. Do not implement runtime features during this task.

ERPNext is a behavioral reference only. Terranex must remain an independent local-first application with no Frappe dependency and no direct ERPNext runtime dependency.

## Required reading order

1. Inspect the latest `main` branch from repository root.
2. Read `AGENTS.md`.
3. Read `IMPLEMENTATION_GUIDE.md`.
4. Read `docs/reference/Terranex-Product-Growth-Roadmap.md`.
5. Read `docs/reference/Terranex-Architecture-English.md`.
6. Read `docs/reference/Terranex-Product-Growth-Roadmap-Zoom-In.md`.
7. Read `docs/reference/Terranex-ERPNext-Engine-Inventory-Summary.md`.
8. Read `reference/erpnext/README.md`.
9. Read `reference/erpnext/selected-paths.txt`.
10. Read `reference/erpnext/expected-sha256.txt` as the integrity contract for the uploaded source-reading set.
11. Run `node tools/fetch-erpnext-reference.mjs` to create a verified ignored cache under `.reference-cache/erpnext/`.
12. Inspect the current source tree with `rg --files` and use `rg` for code search.
13. Inspect open pull requests before proposing landing points.
14. Read cached ERPNext files only when they are relevant to a proposed Terranex stage.

## Hard boundaries

- Do not write runtime code.
- Do not copy ERPNext Python files into `src/`.
- Do not add Frappe or ERPNext dependencies.
- Do not commit `.reference-cache/`.
- Do not add Supabase.
- Do not change storage schemas.
- Do not refactor unrelated files.
- Do not merge or modify other open pull requests.
- Do not create a broad implementation branch.

## Planning questions to answer

1. Which Terranex capabilities already exist on latest `main`?
2. Which gaps remain for each engine portfolio item in the zoom-in roadmap?
3. Which existing stores, domain types, migrations, routes, and tests are the correct landing points?
4. Which ERPNext reference files should be read first for each proposed engine stage?
5. Which business rules should be reimplemented natively rather than copied?
6. Which assumptions require explicit product decisions before coding?
7. What is the smallest safe first implementation increment after Stage 0?

## Required deliverable

Create one planning document only:

```text
docs/plans/terranex-native-engine-extraction-plan.md
```

The document must include:

1. Current repository inventory from actual code.
2. Existing capability matrix.
3. Missing engine matrix.
4. Proposed Terranex-native boundaries.
5. ERPNext reading map by stage.
6. Storage and migration impact notes.
7. Business-rule test matrix.
8. Ordered PR sequence, one narrow stage per PR.
9. Explicit deferrals and exclusions.
10. Recommended first implementation branch name and acceptance criteria.

## Validation

Because this task changes documentation only:

1. Review the final diff carefully.
2. Confirm no runtime files changed.
3. Confirm no generated bundles or copied ERPNext source files were added.
4. Confirm `.reference-cache/` remains ignored and uncommitted.
5. Return the planning document path, changed files, commit SHA, and recommended next branch.

Stop after creating the planning document. Do not begin Stage 1 implementation.
