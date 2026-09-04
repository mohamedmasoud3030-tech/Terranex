# Terranex Agent Skill Source Registry

Terranex uses external skills as design evidence, not as automatic vendored dependencies.

## Tier 1 references

| Source | Strongest signal used by Terranex | Project use |
| --- | --- | --- |
| OpenAI / skills | Security best-practice workflow; repository-grounded threat modeling | Secure implementation/review principles and terranex-threat-model |
| Anthropic / knowledge-work-plugins | ADR and system-design framing | terranex-architecture-decision |
| GitHub / awesome-copilot | Deterministic AI-executable implementation plans | terranex-implementation-planning |
| Trail of Bits / skills | Workflow skill design, trigger quality, progressive disclosure, anti-patterns | Terranex skill design standard |
| EveryInc / compound-engineering-plugin | Risk-selected review personas, deduplication, severity/confidence, review/fix separation | terranex-code-review |
| Addy Osmani / agent-skills | Source-driven development and proof-first TDD | terranex-implementation |
| Supabase / agent-skills | PostgreSQL performance, schema, locking, RLS/security | terranex-database |

## Primary locations reviewed

- https://github.com/openai/skills/tree/main/skills/.curated/security-best-practices
- https://github.com/openai/skills/tree/main/skills/.curated/security-threat-model
- https://github.com/anthropics/knowledge-work-plugins/tree/main/engineering/skills/architecture
- https://github.com/anthropics/knowledge-work-plugins/tree/main/engineering/skills/system-design
- https://github.com/github/awesome-copilot/tree/main/skills/create-implementation-plan
- https://github.com/trailofbits/skills/tree/main/plugins/workflow-skill-design/skills/designing-workflow-skills
- https://github.com/EveryInc/compound-engineering-plugin/tree/main/skills/ce-code-review
- https://github.com/addyosmani/agent-skills/tree/main/skills/source-driven-development
- https://github.com/addyosmani/agent-skills/tree/main/skills/test-driven-development
- https://github.com/supabase/agent-skills/tree/main/skills/supabase-postgres-best-practices
- https://github.com/agentskills/agentskills

## Current non-adoptions

### Nx official agent skills

Not installed. Terranex currently has no Nx workspace and AGENTS.md defines a single deployable application without a monorepo.

Reconsider only if Nx becomes an approved, committed architecture decision.

### NestJS patterns

Not installed. Terranex currently has no NestJS dependency or service boundary.

Reconsider only after an approved architecture change and an actual NestJS dependency lands.

### Drizzle / Better Auth skills

Not installed because those technologies are not present in the current repository.

## Source policy

When a project skill depends on behavior that changes over time:
1. detect the exact installed version;
2. read the relevant official documentation page;
3. reconcile it with repository contracts;
4. record material sources in the delivery summary.

External technical sources never establish Terranex-specific business policy.

## Vendoring policy

Do not copy entire third-party skill folders into Terranex by default.

Prefer a project-specific synthesis with attribution in this registry. If a future skill requires vendored code or substantial copied text, review the upstream license and record the exact revision.
