# UI/UX Pro Max Adoption for Terranex

## Decision

Terranex will use the uploaded UI/UX Pro Max sources as a design intelligence layer, not as a visual theme dump.

The current Terranex source-manifest and adapter contract now lives in `docs/design-system/ui-ux-pro-max-vendoring.md` and `.ai/skills/terranex-ui-ux-pro-max/SKILL.md`. The internal upstream folder tree is manifest-only until actual UI/UX Pro Max source files can be fetched. Future UI tasks must use the Terranex adapter first and must not import UI/UX Pro Max references into runtime React code.

The goal is to turn the design source into enforceable product rules for an Arabic-first investment operating system covering:

1. real estate assets and projects,
2. agricultural farms, crops, and seasons,
3. livestock herds and animal operations,
4. cross-sector finance, obligations, documents, and decisions.

## Sources inspected

- `UI_UX Pro Max - The Ultimate AI Design Intelligence Tool.pdf`
- `ui-ux-pro-max_slides.pdf`
- `ui-ux-pro-max-skill-main.zip`
- `Agent-Skills-for-Context-Engineering-main.zip`
- `multi-agent-orchestrator.skill`
- `pipeline-builder 3.skill`

## What matters from UI/UX Pro Max

The strongest usable parts are:

- searchable design database covering product type, style, colors, typography, charts, UX, and stack rules,
- priority-based design rules where accessibility and touch interaction come before polish,
- design system generation with a master source of truth and page-specific overrides,
- stack-specific recommendations for React, shadcn/ui, forms, tables, performance, and dashboard layouts,
- pre-delivery checklist: contrast, focus states, reduced motion, responsive sizes, cursor states, and non-emoji SVG icons.

## Adopted Terranex design direction

The generated source recommendations were useful but need product correction for Terranex:

- The default generated typography leaned toward luxury real estate. Terranex is not a brochure product; it is an enterprise operating system. We override it with Arabic-first dashboard typography.
- The visual style should be data-dense, financial, accessible, and trust-oriented. It should not look like a crypto dashboard, generic SaaS landing page, or decorative real estate website.
- The interface must optimize for auditability: every number should have a source, period, sector, project, and owner where applicable.

## Final design stance

Terranex should feel like:

> A professional investment command center: calm, precise, Arabic-first, financial-grade, and operationally traceable.

Not like:

> A flashy AI app, luxury property brochure, or generic admin dashboard.

## Implementation rules

1. Use `docs/design-system/MASTER.md` as the global design source of truth.
2. Use page override files under `docs/design-system/pages/` before building or changing each screen.
3. Prefer shadcn/ui primitives, TanStack Table for complex tables, React Hook Form for forms, and chart components that always provide visible numerical fallback.
4. Never ship a number-only UI without drill-down to records or audit trail.
5. Do not create feature pages before defining their domain record types and empty/loading/error states.
6. Any UI PR must include a checklist result for mobile, keyboard navigation, contrast, loading states, and Arabic RTL layout.

## Agent architecture adoption

From the multi-agent and context-engineering sources, Terranex should use a controlled supervisor model only for planning and review:

- Product/domain agent: defines entities and business rules.
- UI/UX agent: applies the design system and page overrides.
- Data/schema agent: validates tables, relationships, and auditability.
- QA agent: checks accessibility, responsiveness, and financial traceability.

Execution should still land in small, reviewable PRs. Avoid uncontrolled multi-agent changes that modify code without a validated contract.

## First build target

The first UI build should be a clickable shell and dashboard, not the full product:

1. Arabic RTL app shell.
2. Executive dashboard.
3. Sector cards: عقاري، زراعي، حيواني، مالي.
4. Placeholder record tables with realistic columns.
5. Empty/loading/error states.
6. Design tokens and base components.
7. No fake irreversible financial logic.
