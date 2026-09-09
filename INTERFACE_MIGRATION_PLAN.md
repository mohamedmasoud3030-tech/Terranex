# Interface Migration Plan (Phase 8) — living status

Status labels: VERIFIED COMPLETE · IMPLEMENTED BUT NOT VERIFIED · BLOCKED BY OWNER OR EXTERNAL ACTION · NOT STARTED.

Verification tooling: `scripts/ui-preview/` (read-only synthetic mock + headless snapshots at 360/768/1280/1600). Every milestone must end with `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`, rendered snapshots, and a diff review.

| # | Milestone | Scope | Priority reason | Status |
|---|---|---|---|---|
| M1 | **Foundations & broken/critical fixes** | `AppShell` compact header + mobile "المزيد"; `WorkspaceNav` tab strip; `WorkspaceChrome` resolves sector automatically (nav on all 15 pages); `.form-grid` containment (pilot overflow); `PageSkeleton` loaders incl. missing routes; remove stray `autoFocus`; fix `undefined` subtitle; duplicate `h1`; not-found CTA; "المشاريع" → `/projects`; `src/shared/ui` primitives (PageHeader, Section, StatGrid/Stat, StatusBadge, Banner, EmptyState, PermissionState, SectionTabs, InPageTabs, form helpers); Arabic lifecycle/severity labels | P0/P1 unusable mobile + severe RTL/mobile failures + highest cross-project value | VERIFIED COMPLETE |
| M2 | **Representative journey: Home → Projects → Project home → Costs/Cash → Funding/Terms** | Home re-hierarchy (`PageHeader`, `StatGrid` with drill-down links, Arabic severity badges, compact recent-projects list, primary CTA = "مشروع جديد"); `/projects` cards with Arabic lifecycle/sector badges; project home: single CTA, KPIs linked to their sections, section list replaces duplicated dashboards; Costs/Cash and Funding/Terms `SectionTabs`; Cash/Terms/Funding now use `WorkspaceChrome` (were outside the workspace nav) | incorrect content/action hierarchy on the daily path | VERIFIED COMPLETE (scope note: Costs form-after-list reorder and row-action disclosure were deferred to M4 — not done) |
| M3 | **Monolith pages progressive disclosure** | `InPageTabs` sticky anchor strips on Agriculture (13 anchors), Operations (8), Pilot (9), Livestock (10, new section ids); Intake stepper markup (numbered steps, done/current state, `aria-current="step"`) | severe mobile length | VERIFIED COMPLETE (rendered at 4 widths, overflow 0; page length itself unchanged by design — anchors only, no content hidden) |
| M4 | Remaining route migration to templates (portfolio detail order, Costs/revenue/procurement row actions, integrity reference collapse, livestock cards, remaining pages to `PageHeader`/`Section`) | consistency | NOT STARTED |
| M5 | `DataTable` mobile stack mode (`data-label`) on the six finance tables | table usability on phones | NOT STARTED |
| M6 | Remove obsolete CSS/helpers after zero consumers (`.context-nav` route-level, local `Metric`, `ForbiddenCard` alias, `.overview-kpis`) | cleanup | NOT STARTED |
| M7 | Polish: hit areas everywhere (`/projects/new` radios still 20 px targets inside 44 px labels), expired-session form message | low impact | NOT STARTED |

## Verification evidence (2026-09-09, against mock Supabase fixtures `DEMO-UI-*`; real Supabase host is unreachable from the sandbox)
- Gate: `npm run lint` ✓ · `npm run typecheck` ✓ · `npm test` ✓ 748/748 (61 files) · `npm run build` ✓.
- Snapshot harness (`scripts/ui-preview/snapshot.mjs`, 4 widths × 38 routes): `overflowX = 0` on every route (pilot was 790 px mobile / 396 px tablet before M1).
- App header height at 360 px: 62 px (was ≈240 px). Mobile menu opens via native `<details>`; contains nav + org switcher + sign-out.
- Keyboard walk on `/costs` at 1280 px: skip-link → brand → 4 nav links → sign-out → back-link; all with visible focus ring; `main#content`, `dir="rtl"`, `aria-current` on primary nav, workspace tab, and section tab.
- Single `h1` on every route (livestock pages previously had two). No literal `undefined` subtitles (fixture enum corrected + raw-code fallback).
- Contract tests unchanged except two that asserted primary nav markup lives inline in `layout.tsx`; they now assert `AppNav` (same hrefs/labels).

## Not verified / limitations
- Real Supabase data, write actions (server actions hit a read-only mock and return 405) and the login round-trip against production auth were not exercised.
- Visual review was by screenshot at 360/768/1280/1440 only; no physical device or screen-reader run.
