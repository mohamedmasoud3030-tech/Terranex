# Shared Component Architecture (Phase 5)

**Stack constraint:** Next.js 16 App Router, React 19 server components, plain global CSS (`src/app/globals.css`), no UI library. The canonical system stays **server-component-first, class-based, zero new dependencies**. Components live in `src/shared/ui/` and are tiny wrappers that encode one convention each; pages keep owning data and business copy.

## Inventory of current UI building blocks

| Current | Kind | Used in | Decision | Canonical replacement |
|---|---|---|---|---|
| `main.shell > header.top` (layout) | layout | every app page | **REPLACE** | `AppShell` (`src/shared/ui/app-shell.tsx`) |
| `WorkspaceChrome` (`features/workspace/chrome.tsx`) | project header + nav | 15 pages | **IMPROVE** (keep name/export; render via `PageHeader` + `WorkspaceNav`; make `sector` mandatory-by-default by resolving from project when absent) | same file |
| `WorkspaceNav` card grid | nav | shell + chrome | **IMPROVE** → tab strip; keep `sectionsFor`, ids, hrefs (tested) | same file |
| `DemoBanner` | banner | chrome, shell | **KEEP** → uses `Banner` | — |
| `ForbiddenCard` | permission state | 9 pages | **MERGE** into `PermissionState` (keep export as thin alias) | `src/shared/ui/states.tsx` |
| `.card`, `.stack`, `.grid` | layout classes | everywhere | **KEEP** (CSS) + `Section` wrapper for titled cards | `Section` |
| `.top` div used as page header inside pages (Home, Projects, Portfolios) | header | 4 pages | **REPLACE** | `PageHeader` |
| `.overview-kpis > .overview-kpi`, `.metric-grid > .metric`, `.grid > .card` metric trios, local `Metric()` in funding | stats | 8 pages, 4 variants | **MERGE** | `StatGrid` + `Stat` |
| `.status`, `.role-badge`, `.intake-badge-*`, `.status-*`, `PORTFOLIO_STATUS_BADGE_CLASS` | badges | everywhere | **MERGE** into one `StatusBadge` with `tone` | `StatusBadge` |
| `.table-wrap > table` | table | 30+ places | **IMPROVE** → `DataTable` wrapper providing caption, `scope`, sticky first column, mobile stack mode via `data-label` | `DataTable` (progressive: wrapper first) |
| `.facts` `<dl>` | key-value | operations, terms, close | **KEEP** → `KeyValueList` | `KeyValueList` |
| `.milestone`, `.timeline-row`, `.gate` | list/timeline | home, close, controls, operations | **KEEP** CSS; `Timeline`/`GateList` later | — |
| `.context-nav` chips | in-page nav | overview, operations, pilot, costs | **SPLIT**: route-level → `SectionTabs`; in-page → `InPageTabs` (sticky anchors) | new |
| `.banner`, `.banner.info` | alert | many | **KEEP** → `Banner` component with `tone` | `Banner` |
| `loading.tsx` text ×6 | loading | — | **REPLACE** | `PageSkeleton` |
| `error.tsx` ×6 | error | — | **KEEP** (already consistent, tested) | — |
| `.empty` sections | empty state | many | **MERGE** | `EmptyState` |
| forms (`label > input`, `.form-grid`, `.error[role=alert]`, pending button) | forms | 60+ forms | **KEEP** HTML conventions; add `FormActions`, `FieldHint`, `FormError` helpers; fix `.form-grid` min-width | `src/shared/ui/form.tsx` |
| `<details><summary>` for inline forms | disclosure | many | **KEEP** (no-JS, accessible) + `Disclosure` styling class | — |
| `OrganizationSwitcher` | nav | layout | **KEEP** (tested) | — |
| `JournalTrace` | domain | finance | **KEEP** | — |

## Canonical component set (smallest justified)

### Layout
- **AppShell** — top bar (brand, primary links with `aria-current`, "المزيد" overflow on ≤ 720 px via `<details>`), `main#content` landmark, skip link. RTL: logical properties only. States: current link. Anti-pattern: never put page actions in the shell.
- **PageContainer** — `.shell` width (1080 px; `wide` variant 1360 px for finance tables). 
- **PageHeader** — eyebrow (org/project), `h1`, description, `actions` slot (primary first). Mobile: actions wrap below title, primary full-width. Long titles wrap; never truncate `h1`.
- **Section** — `<section class="card stack" aria-labelledby>` with `h2`, optional description, `actions`, `collapsible` (renders `<details>`). Only one `h1` per page—Section never renders `h1`.
- **StatGrid / Stat** — `dl`-based; `href` makes the tile a link; `tone: neutral|negative|positive`; `hint` text. Never colour-only.
- **SectionTabs** — route-level second-level tabs (`nav` + `aria-current`). **InPageTabs** — sticky anchor strip for monolith pages.

### Actions
- Existing `button`/`.button`/`.secondary` classes are the Button system (KEEP). Add `.button.ghost`, `.button.danger`, `.button.sm`, and min hit-area 40 px via padding. `FormActions` aligns primary/secondary/cancel (`margin-inline-start:auto` for cancel).
- **RowActions** — `<details class="row-actions">` whose summary reads "الإجراءات" and whose content renders below the row (full-width `td colspan`), removing stacked forms inside cells.

### Forms
- Conventions codified in `FORM_COMPONENT_STANDARD.md`. Helpers: `Field` (label + control + hint + error id wiring), `FormError` (`role=alert`), `FormActions`, `PendingButton` (client). Native controls only.

### Data display
- **DataTable** — wraps `.table-wrap` with `caption` (visually hidden), `stickyFirstColumn`, `mobile: 'scroll'|'stack'` (stack uses `data-label` on `td` via CSS). Progressive: pages keep writing `<thead>/<tbody>`.
- **KeyValueList** — `.facts` `dl`.
- **StatusBadge** — `tone: neutral|success|warning|danger|info` + label; label maps live in feature `labels.ts`.
- **EmptyState**, **PermissionState**, **ErrorState** (client, used by `error.tsx`), **PageSkeleton**, **Banner** (`tone: info|warning|danger`, `role` note/alert/status).

### Deliberately not built
Toast, Dialog, Drawer, Popover, Tooltip, Combobox, FileUpload, ChartContainer: no current consumer needs them; the app is server-rendered with native disclosure. Adding them now would be premature abstraction.

## Usage locations and migration priority

| Component | Priority | First consumers (milestone) | Remaining |
|---|---|---|---|
| AppShell | P0 | layout (M1) | — |
| PageSkeleton | P0 | all `loading.tsx` (M1) | add missing route loaders |
| WorkspaceNav tab strip + chrome sector resolution | P0 | all 15 project pages via chrome (M1) | — |
| `.form-grid` min-width fix | P0 | pilot (M1) | global |
| PageHeader / Section / StatGrid / StatusBadge / Banner / EmptyState / PermissionState | P1 | Home, Projects, project shell, Overview (M2) | rest by route priority |
| SectionTabs | P1 | costs/cash, funding/terms (M2) | — |
| DataTable (wrapper) + RowActions | P2 | Costs (M3) | revenue, procurement, portfolio |
| InPageTabs | P2 | agriculture, operations, intake stepper (M3/M4) | — |

## Deprecation plan
1. Keep old class names working during migration (CSS is additive).
2. When every consumer of `.overview-kpi`, `.metric`, `.project-context`, `.context-nav` (route-level) is migrated, delete the CSS and the local helpers.
3. `ForbiddenCard` stays exported as an alias to `PermissionState` for one release, then is removed with a grep-verified zero consumers.
