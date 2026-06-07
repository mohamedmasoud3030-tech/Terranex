# Terranex — Addy Agent Skills Integration

Terranex may use the upstream engineering workflow pack from `addyosmani/agent-skills` as a pinned local reading reference.

## Source lock

The pinned upstream source is recorded in `reference/agent-skills/source-lock.json`.

```text
Repository: https://github.com/addyosmani/agent-skills
Commit:     2e0dfbfb436ef3307bbe8ba172f14996de980784
Cache:      .reference-cache/agent-skills
```

The cache directory is intentionally ignored by Git. Do not commit copied upstream files. Do not edit cached upstream files. Terranex-specific rules belong in `AGENTS.md`, `docs/ai/`, `.ai/workflows/`, and approved planning documents.

## Materialize the pinned cache locally

Run from the repository root:

```bash
mkdir -p .reference-cache
git clone https://github.com/addyosmani/agent-skills.git .reference-cache/agent-skills
git -C .reference-cache/agent-skills checkout --detach 2e0dfbfb436ef3307bbe8ba172f14996de980784
```

For an existing cache:

```bash
git -C .reference-cache/agent-skills fetch origin 2e0dfbfb436ef3307bbe8ba172f14996de980784
git -C .reference-cache/agent-skills checkout --detach 2e0dfbfb436ef3307bbe8ba172f14996de980784
```

## Loading rule

Start by reading:

```text
.reference-cache/agent-skills/skills/using-agent-skills/SKILL.md
```

Load only the skills relevant to the current task. Do not load the entire pack into context.

## Terranex routing map

| Task | Load these upstream skills | Also follow |
|---|---|---|
| Repository audit | `context-engineering`, `code-review-and-quality` | `.ai/workflows/README.md` → Repository audit |
| Bug fix | `debugging-and-error-recovery`, `test-driven-development`, `code-review-and-quality` | `.ai/workflows/README.md` → Safe bug fix |
| New domain engine stage | `spec-driven-development`, `planning-and-task-breakdown`, `incremental-implementation`, `test-driven-development` | Approved Terranex roadmap stage |
| Storage or migration change | `deprecation-and-migration`, `test-driven-development`, `code-review-and-quality` | `docs/ai/data-safety.md` and storage workflow |
| UI change | `frontend-ui-engineering`, `browser-testing-with-devtools`, `code-review-and-quality` | Arabic RTL and responsive checks |
| External ERP behavior study | `source-driven-development`, `doubt-driven-development`, `documentation-and-adrs` | Terranex external-reference workflow |
| Release check | `shipping-and-launch`, `ci-cd-and-automation`, `code-review-and-quality` | `docs/ai/release-policy.md` |

## Precedence

When an upstream generic workflow conflicts with Terranex policy, Terranex policy wins. In particular:

- Keep Terranex independent from Rentrix and other applications.
- Keep production runtime local-first and free from automatic demo records.
- Preserve financial traceability, deletion guards, and audit history.
- Treat external ERP code as behavioral reference only.
- Rebuild approved behavior as Terranex-native TypeScript.
