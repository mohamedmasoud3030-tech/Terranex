# ERPNext source-reading references for Terranex

This directory prepares Codex to study selected ERPNext engine files while rebuilding the required behavior as Terranex-native TypeScript modules.

## Boundary

ERPNext is a reference specification only. Do not import ERPNext Python files into `src/`, do not add Frappe as a dependency, and do not turn Terranex into an ERPNext fork.

## Pinned reference

- Official repository: `frappe/erpnext`
- Pinned commit: `e1f6bb70bc2ddffc923ac6430b79d2ecea422a7a`
- Curated source-reading paths: `selected-paths.txt`
- Expected integrity contract: `expected-sha256.txt`

## Intended use

Read ERPNext validation rules, status transitions, schemas, reports, and tests. Then implement the smallest stable Terranex-native contract that fits the existing local-first architecture.

## Non-negotiable rules

- Inspect latest Terranex `main` before editing.
- Implement one narrow engine stage per branch and pull request.
- Preserve current local-first storage and migrations.
- Keep Supabase deferred until the final migration stage.
- Run lint, typecheck, tests, build, and final diff review before merge.
