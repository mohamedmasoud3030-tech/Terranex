# Terranex Agent OS

Terranex keeps a small set of project-specific Agent Skills under .agents/skills.

These skills are operational workflows. They do not replace AGENTS.md, canonical product/domain documents, ADRs, or OPEN_BUSINESS_DECISIONS.

## Installed project skills

| Skill | Use |
| --- | --- |
| terranex-architecture-decision | ADRs, system design, data/API boundaries, technology trade-offs |
| terranex-implementation-planning | Deterministic implementation plans and AI-to-AI handoffs |
| terranex-implementation | Source-driven implementation, proof-first fixes, bounded cleanup |
| terranex-code-review | Risk-routed review with review/fix separation |
| terranex-database | PostgreSQL, migrations, RLS, tenant isolation, financial/data grain |
| terranex-threat-model | Repository-grounded AppSec threat modeling |

## Design choice

Terranex intentionally does not vendor ten or thirty generic third-party skills.

The project skills synthesize the strongest ideas from the source registry while preserving Terranex-specific authority and current-stack constraints. Heavy detail lives in one-hop references so activation remains cheap and focused.

## Precedence

When guidance conflicts, use this order:

1. explicit user instruction for the current task;
2. AGENTS.md and canonical Terranex decisions;
3. task-specific project skill;
4. current implementation/tests for existing behavior;
5. official external technical documentation for version-specific mechanics;
6. generic external patterns.

External sources never authorize Terranex-specific business policy.

## Maintenance

Before adding another skill, read:
- docs/agent-os/SKILL_DESIGN_STANDARD.md
- docs/agent-os/GAP_ANALYSIS.md
- docs/agent-os/SOURCE_REGISTRY.md

Prefer MODIFY or MERGE over adding a new overlapping skill. Delete or retire superseded skill files in the same change so duplicate triggers do not accumulate.
