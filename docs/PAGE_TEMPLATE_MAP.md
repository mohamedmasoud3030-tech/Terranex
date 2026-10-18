# Page Template Map (Phase 7)

Five templates cover every route. Widths: `PageContainer` 1080 px default; finance tables may use `wide` (1360 px) later. All templates are RTL-structural (logical CSS properties), single `h1`, `main#content` landmark, skip link from `AppShell`.

## Templates

### T1 · Overview
- **Use:** orientation pages whose job is "what is the state, where do I go".
- **Regions:** PageHeader (eyebrow, h1, description, 1 primary + ≤ 1 secondary action) → attention banner(s) → StatGrid (≤ 8 tiles, each linking to source) → 1–3 Sections (list/table) → no forms.
- **Responsive:** tiles 2-across at 360, 4-across ≥ 960; sections stack.
- **Must not be used for:** anything with data entry or more than one primary decision.

### T2 · Index / List management
- **Regions:** PageHeader (h1 + "new" action) → optional FilterBar (text filter, when > 8 items) → Cards or DataTable → EmptyState / no-results.
- **Responsive:** cards 1-col mobile; table PC/T2C.
- **Must not be used for:** record detail or dashboards.

### T3 · Record / Workspace detail
- **Regions:** ProjectWorkspaceHeader or PageHeader with status badge → route-level WorkspaceNav tab strip (project routes) → optional SectionTabs (second level) → optional InPageTabs (sticky, monolith pages) → Sections in decision order: status/summary → primary table/cards → actions (collapsed forms) → history/audit (collapsed).
- **Responsive:** tabs scroll horizontally; sections stack; tables PC/T2C.
- **Must not be used for:** creating a brand-new record from scratch (T4).

### T4 · Create / Edit form
- **Regions:** PageHeader (h1, one sentence) → single-column form (max 720 px) → FormActions (primary + cancel).
- **Responsive:** sticky-safe; primary full width on mobile.
- **Must not be used for:** multi-entity flows (use T3 with stepper).

### T5 · Auth / Onboarding / System state
- **Regions:** centered card ≤ 480–600 px, one h1, one form or one message, one primary action, one text link.
- Used also by not-found, error, forbidden without shell.

## Route → template

| Route | Template | Notes |
|---|---|---|
| `/login`, `/forgot-password`, `/reset-password`, `/onboarding`, not-found, error | T5 | |
| `/` | T1 | signals list + conditional money + projects |
| `/projects`, `/portfolios`, `/assets`, `/intake` | T2 | `/assets` = table variant |
| `/projects/new`, `/portfolios/new` | T4 | |
| `/portfolios/[id]` | T3 | projects table first; management + histories collapsed |
| `/projects/[id]` | T1 (inside project shell) | |
| `/projects/[id]/overview` | T1 | |
| `/funding`, `/terms` | T3 + SectionTabs(رأس المال) | |
| `/costs`, `/cash` | T3 + SectionTabs(التكاليف والنقدية) | |
| `/revenue`, `/close`, `/budget`, `/integrity`, `/governance`, `/procurement`, `/controls`, `/investors`, `/pilot` | T3 | pilot & integrity use InPageTabs |
| `/operations`, `/agriculture`, `/livestock`, `/livestock/operations` | T3 + InPageTabs | |
| `/projects/[id]/intake` | T3 + stepper (custom region, justified: guided sequence with 7 steps) | |
