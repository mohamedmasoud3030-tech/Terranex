# Codex Prompt: Build Terranex First UI Shell

Use this prompt when asking Codex or another coding agent to start the first Terranex UI implementation.

```text
You are working in the Terranex repository.

Goal:
Build the first Arabic-first RTL UI shell and clickable dashboard foundation for Terranex, an investment operating system for real estate, agriculture, livestock, finance, documents, and decisions.

Read first:
1. AGENTS.md
2. README.md
3. docs/ui-ux-pro-max-adoption.md
4. docs/design-system/MASTER.md
5. docs/design-system/pages/dashboard.md
6. docs/design-system/pages/real-estate.md
7. docs/design-system/pages/agriculture.md
8. docs/design-system/pages/livestock.md
9. docs/design-system/pages/finance.md
10. docs/implementation/first-build-brief.md
11. .ai/skills/terranex-ui-ux-pro-max/SKILL.md

Scope:
Create a small, reviewable first implementation. Do not implement real financial logic yet. Do not connect to a real database yet unless the repo already has approved infrastructure. Use isolated mock fixtures only for visual scaffolding.

Required deliverables:
1. Arabic RTL app shell.
2. Sidebar navigation on the right.
3. Top bar with search placeholder, period selector, and user placeholder.
4. Executive dashboard page.
5. Sector cards for عقاري، زراعي، حيواني، مالي.
6. KPI cards with currency, period, loading/empty/error handling hooks or placeholders.
7. Placeholder pages or routes for:
   - real estate assets,
   - agriculture seasons,
   - livestock herds,
   - finance and obligations,
   - documents and decisions.
8. Base components:
   - AppShell,
   - SidebarNav,
   - TopBar,
   - PageHeader,
   - KpiCard,
   - SectorCard,
   - DataTableShell,
   - EmptyState,
   - LoadingSkeleton,
   - ErrorState,
   - StatusBadge,
   - MoneyValue,
   - PeriodFilter.

Rules:
- Use TypeScript.
- Use CSS variables for theme tokens.
- Prefer Tailwind and shadcn/ui patterns if the project is configured for them.
- Use SVG icons, not emoji.
- Do not hardcode raw colors inside components; use tokens/classes.
- Do not invent irreversible accounting logic.
- Do not create fake production services.
- Keep mock data in a clearly named fixture module.
- Add or update documentation explaining how to run the UI.

Accessibility and quality requirements:
- RTL must work globally.
- Keyboard focus states must be visible.
- Touch targets should be at least 44x44px.
- Tables must remain usable on mobile.
- Every page needs a meaningful empty state.
- Financial values must include currency and period context.
- Charts, if added, must include visible numeric summaries and not rely only on hover tooltips.

Validation:
Run the available project checks. At minimum attempt:
- package manager install status check,
- typecheck if configured,
- lint if configured,
- build if configured.

Report:
In the PR summary, include:
1. What was built.
2. Files changed.
3. How RTL was handled.
4. Where mock data lives.
5. What checks were run and their results.
6. What remains intentionally deferred.
```
