# Use All Terranex Skills

This document defines how Terranex should use the prepared skill and agent stack.

## External skill stack

Terranex should use these external references as the base skill layer:

- anthropics/knowledge-work-plugins
- multica-ai/andrej-karpathy-skills
- Lum1104/Understand-Anything
- nextlevelbuilder/ui-ux-pro-max-skill

## Internal Terranex layer

Terranex-specific guidance lives in:

- AGENTS.md
- plugin/manifest.json
- plugin/README.md
- plugin/agents
- plugin/skills
- docs
- tools

## Operating order

1. Read AGENTS.md.
2. Read docs/product-vision.md.
3. Read docs/domain-model.md.
4. Read plugin/README.md.
5. Inspect external skills under external/skills when present.
6. Use repository understanding before implementation.
7. Use domain understanding before data model changes.
8. Use UI/UX Pro Max before creating product screens.
9. Use pipeline builder for batch analysis and automation.
10. Keep Terranex independent from Rentrix.

## Roles

- repository analyst: understands codebase structure and gaps.
- domain analyst: extracts Terranex business model and flows.
- data architecture lead: turns domain rules into schema and relationships.
- UI notes layer: guides dashboard and workflow design.
- pipeline builder: creates repeatable analysis workflows.

## First practical workflow

For any new Terranex feature:

1. Understand the domain need.
2. Map affected entities.
3. Define data records and documents.
4. Design UI flow.
5. Implement only after the above are clear.
6. Validate profitability and obligation traceability.
