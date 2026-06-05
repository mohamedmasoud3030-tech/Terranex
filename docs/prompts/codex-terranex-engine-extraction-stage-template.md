# Codex Task Template — Implement One Terranex-Native Engine Stage

## Use only after Stage 0 planning is reviewed

This template is for one narrow implementation branch only. Replace the bracketed fields from the approved planning document before starting.

## Mission

Implement exactly one Terranex-native increment:

```text
[APPROVED_STAGE_NAME]
```

Do not expand the scope beyond the approved acceptance criteria.

ERPNext remains a behavioral reading reference only. Do not copy ERPNext Python into `src/`, do not add Frappe, and do not add any ERPNext runtime dependency.

## Required setup

1. Start from latest `main`.
2. Create an isolated branch:

```text
[APPROVED_BRANCH_NAME]
```

3. Read:
   - `AGENTS.md`
   - `IMPLEMENTATION_GUIDE.md`
   - `docs/reference/Terranex-Product-Growth-Roadmap.md`
   - `docs/reference/Terranex-Architecture-English.md`
   - `docs/reference/Terranex-Product-Growth-Roadmap-Zoom-In.md`
   - `docs/reference/Terranex-ERPNext-Engine-Inventory-Summary.md`
   - `docs/plans/terranex-native-engine-extraction-plan.md`
4. Inspect the latest source tree with `rg --files` and use `rg` for searches.
5. Inspect open pull requests before editing.
6. Run `node tools/fetch-erpnext-reference.mjs` only when ERPNext behavioral references are needed. Keep `.reference-cache/` ignored and uncommitted.

## Approved scope

### Required behavior

[PASTE_APPROVED_BEHAVIOR]

### Relevant Terranex landing points

[PASTE_APPROVED_LANDING_POINTS]

### Relevant ERPNext reference files

[PASTE_APPROVED_REFERENCE_FILES]

### Explicit exclusions

[PASTE_APPROVED_EXCLUSIONS]

## Hard boundaries

- Implement one coherent increment only.
- Do not add Supabase.
- Do not add Frappe or ERPNext dependencies.
- Do not copy cached ERPNext files into source control.
- Do not perform broad refactors.
- Do not create duplicate helpers.
- Do not delete risky legacy data.
- Keep migrations versioned, conservative, idempotent, and tested when stored records change.
- Preserve document traceability, guarded deletion, cancellation history, and reversal history where applicable.

## Required tests

Add business-rule tests for:

[PASTE_APPROVED_TEST_MATRIX]

Do not rely only on UI rendering tests.

## Quality gate

Run the full gate before opening a pull request:

```bash
npm ci
npm run typecheck
npm run lint
npm run test
npm run build
```

Review the final diff carefully and verify that no unrelated files changed.

## Required completion report

Return:

1. implemented behavior;
2. exact files changed;
3. migration behavior, if any;
4. tests added or updated;
5. quality-gate results;
6. final diff review notes;
7. commit SHA;
8. pull-request URL;
9. remaining deferred items.
