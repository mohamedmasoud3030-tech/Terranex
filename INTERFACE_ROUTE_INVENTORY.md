# Interface Route Inventory (Phase 1)

**Evidence basis:** the real application rendered on 2026-09-09 against the offline read-only preview mock (`scripts/ui-preview/`) at 360 / 768 / 1280 / 1600 px, plus source, tests (748 passing), `src/proxy.ts`, and the `getCurrentMembership` role checks. Numbers in "Rendered facts" come from `scripts/ui-preview/snapshot.mjs` (`ovf` = horizontal overflow px, `h` = full-page height px, `tap` = smallest interactive element height px).

## Roles and permission model (implementation facts)

| Role | Source | What it means in the UI |
|---|---|---|
| Anonymous | `src/proxy.ts` | Every path except `/login`, `/forgot-password`, `/auth/recovery`, `/api/health` redirects to `/login`. |
| Authenticated without organization | `getActiveOrganization()` returns `null` | Home/Projects/Portfolios/Assets/Intake render an "create organization" card; `/onboarding` is the only productive page. |
| `MEMBER` (active membership) | `memberships.role`, checked page by page via `getCurrentMembership` | Can read every project page and prepare drafts (obligations, risks, PR/PO, sector records). Cannot authorize, approve, post, close, reopen, or run sales/recognition commands. |
| `OWNER` | same | Everything above plus authorize/approve/post/close/reopen/recognize/collect; sees member access table on Controls/Pilot. |
| No membership / other org | RLS + `ForbiddenCard` on 9 pages | Forbidden card or empty data. Authorization is always enforced by the database; the UI only hides controls. |

There is no investor portal, no per-project role, no settings role. Multi-organization users get the header `OrganizationSwitcher` (cookie `terranex_active_org`).

## Global shell (all `(app)` routes)

- `src/app/(app)/layout.tsx`: brand link, 4 top links styled as buttons (المحافظ / المشاريع→`/` / الأصول / إدخال المشروع), organization switcher, sign-out form.
- Rendered facts: the header occupies **~240 px on 360 px mobile** (4 wrapped buttons + sign-out stacked vertically) before any page content; no compact/mobile navigation; "المشاريع" points to `/` (dashboard) while `/projects` (the actual index) is unreachable from global navigation; no current-page indication; no landmark for page content (`main.shell` wraps header + content together).
- Loading state: `loading.tsx` plain text "جارٍ تحميل البيانات…" (no skeleton). Error state: Arabic recoverable card (tested). Not-found: card whose CTA says "العودة إلى المشاريع" but links to `/`.
- Expired session: server actions return `redirect('/login')` through the proxy; no in-page message.

## Route table

Legend for **Pattern**: KPI = stat tiles; TBL = table in `.table-wrap`; CARDS = `.grid > .project`; FORM = server-action form; DET = key/value `.facts`; TL = `.timeline-row`; ACC = `<details>` accordion.

| # | Route / page | Roles | Purpose & user's primary question | Current content & actions | Data sources (read models) | Pattern | Mobile / desktop behaviour (rendered) | Confirmed problems | Dependencies / permission boundary |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `/login` | anon | Sign in | email, password, submit, forgot link | Supabase auth | FORM | Centered 480 px card; fine at all widths | Smallest tap 31 px (links). Signed-in users redirected to `/`. | `proxy.ts` |
| 2 | `/forgot-password`, `/reset-password`, `/auth/recovery` | anon / recovery session | Recover access | single-field forms, success state | Supabase auth | FORM | Fine | none material | recovery session gates `/reset-password` |
| 3 | `/onboarding` | auth, no org | Create first organization | name + submit | `create_organization` | FORM | Fine | Not linked once an org exists (correct); no explanation of what happens next | grants OWNER |
| 4 | `/` "لوحة الإدارة التنفيذية" | OWNER, MEMBER | "What needs my attention across the organization?" | 4 count tiles (portfolios, projects, assets, integrity subjects), consolidated money KPIs (or FX banner), sector performance table (8 cols), integrity signals list (top 8), 6 project cards, 2 CTAs | `investment_projects`, `investment_portfolios_read`, `cross_sector_asset_register_read`, `sector_performance_read`, `organization_financial_consolidation_read`, `financial_integrity_signals_read` | KPI + TBL + list + CARDS | h=3870 mobile / 1923 laptop. Three count tiles are just links to index pages. Signals list shows raw `signal_code` and English severity badge. Project cards link to sector landing, not project home. | Counts duplicate the index pages; "المشاريع" nav points here; signals have no drill-down; severity shown in English; sector table has 8 columns with no mobile strategy. | 6 parallel queries |
| 5 | `/projects` | OWNER, MEMBER | "Which project do I open?" | header + "مشروع جديد" + cards (name, description, sector, raw `lifecycle_state`, currency, reference) | `investment_projects` | CARDS | 1 col mobile / auto-fit ≥250 px | Raw English `lifecycle_state` (`DRAFT`, `FUNDING`); no search/filter/sort; card links to `/projects/[id]` shell while Home cards link to sector landing (inconsistent); unreachable from global nav. | none |
| 6 | `/projects/new` | OWNER, MEMBER | Create a project | sector radio (3), name, reference, description | `create_investment_project` RPC | FORM | 720 px card | Radio tap height 13 px; no cancel/back; sector explanation OK | idempotency nonce |
| 7 | `/portfolios` | OWNER, MEMBER | "Which portfolio?" | cards with status badge, assigned-project count | `investment_portfolios_read`, `portfolio_project_assignments_read` | CARDS | fine | no filter; fine otherwise | none |
| 8 | `/portfolios/new` | OWNER, MEMBER | Create portfolio | name, description | RPC | FORM | fine | tap 19 px | — |
| 9 | `/portfolios/[id]` | OWNER, MEMBER | "What is in this portfolio and is anything off?" | header + status badge; purpose card; financial roll-up (currently empty message); management data; lifecycle transitions; edit form (`<details>`); assigned projects table; assign form; assignment history table; status history table | `investment_portfolios_read`, `portfolio_project_assignments_read`, `investment_portfolio_state_history_read`, `portfolio_financial_rollup_read`, `memberships` | DET + TBL + FORM | h=3569 mobile; 6 forms on one page | Purpose card is a full-width card for one sentence; financial roll-up sits above the project list although projects are the primary content; lifecycle forms and edit form interleave with reading content; two history tables of low daily value are always expanded. | `assign_project_to_portfolio` etc. |
| 10 | `/assets` | OWNER, MEMBER | "Where does each asset stand across sectors?" | sector performance cards; asset register table (asset, project, state, cost, valuation, result, registered) | `sector_performance_read`, `cross_sector_asset_register_read` | CARDS + TBL | Table 640 px min-width scrolls inside `.table-wrap`; fine | None blocking; duplicates the sector table on Home | read-only |
| 11 | `/intake` | OWNER, MEMBER | Pick a project to continue guided intake | project cards → `/projects/[id]/intake` + "مشروع إضافي" | `investment_projects` | CARDS | fine | Third global nav item for a per-project wizard; duplicates `/projects` list | — |
| 12 | `/projects/[id]` (shell) | OWNER, MEMBER | "Where am I and what is the state of this project?" | sticky context header, demo banner, `WorkspaceNav` (9–13 cards), description, 4 KPI tiles (contributed, cash, realized result, period), "دخول مساحة القطاع" ×2 | `investment_projects`, `project_capital_position_read`, `project_cash_position_read`, `property_realized_result_read`, `accounting_periods_read`, `memberships` | KPI | h=2156 mobile; workspace nav = 2-col cards on mobile | Two identical "دخول مساحة القطاع" buttons; KPIs duplicate `/overview`; for AG/LS the RE `realized_result` query is still run; back link goes to `/`. | — |
| 13 | `/projects/[id]/overview` (RE only; AG/LS redirect to sector page) | member | Financial + operational status | 4 KPI groups (13 tiles), blockers banner, assets table, period/close tiles, "روابط التشغيل" chip nav duplicating `WorkspaceNav` | 10 read models | KPI + TBL | h=4350 mobile | Duplicate navigation (nav cards + chips); 13 KPI tiles stacked vertically on mobile; no per-tile drill-down link. | `ForbiddenCard` if no membership |
| 14 | `/projects/[id]/funding` | member (owner posts) | Capital commitments, calls, contributions | agreement-version gate (redirect to `/terms` CTA), 4 metrics, partner positions table, capital-call form, calls table (with nested `<ul>`), contribution form, contributions table | funding read models, `agreement_versions` | KPI + TBL + FORM | h=3214 mobile; tables 5 cols | Forms interleaved between tables; nested lists inside cells; no member/owner distinction in copy | `/terms` is a hidden prerequisite route |
| 15 | `/projects/[id]/terms` | member | Parties, participants, agreement versions/drafts | party form, participant form, active version, draft form, drafts list | `parties`, `project_participants`, `agreement_versions` | FORM + TBL | fine | **Not in `WorkspaceNav`**; only reachable from Funding's empty state | activation is owner-only |
| 16 | `/projects/[id]/operations` (RE) | member | Property assets, control, development, cost control, disposition, valuation, timeline | in-page chip nav (8), asset cards with facts, 14 forms, 11 accordions, timeline | 12 real-estate read models | CARDS + DET + FORM + ACC + TL | **h=11984 mobile / 7667 laptop**; all sections stacked | Subtitle renders literally `undefined` when no RE profile (`STRATEGY[profile.strategy]` is undefined for `DEVELOP_AND_SELL`); page is a monolith of 8 concerns; `WorkspaceChrome` without `sector` so no section nav on this page. | owner for approvals/recognition |
| 17 | `/projects/[id]/costs` | member (owner authorizes/approves) | Obligations, aging, payments, disputes, milestones, ledger | 6 metric cards, new-obligation form first, obligations table (8 cols with nested action accordions inside cells), milestones, ledger trace, audit log | finance + control read models | KPI + FORM + TBL + ACC | h=4274 mobile; table min 640 px | Create form placed above the list; row actions are `<details>` stacked in a cell (row height explodes); "النقدية والبنك" link is a lone chip; no section nav (`sector` prop missing). | `/cash` hidden sibling |
| 18 | `/projects/[id]/cash` | member (owner approves) | Cash accounts, payments, bank import, reconciliation, audit | 4 forms, tables, ledger accordion, audit | finance read models | TBL + FORM + ACC | h=3334 mobile | **Not in `WorkspaceNav`**; only linked from Costs/Procurement/Pilot | — |
| 19 | `/projects/[id]/revenue` | member (owner recognizes/collects) | Rental income, dispositions, realized result, collections, reconciliation | summary, rental form (owner), 6 tables, reconciliation forms in cells | revenue read models | TBL + FORM | h=3854 mobile | Rental + sale concerns interleaved; owner-only forms inline in table cells | — |
| 20 | `/projects/[id]/close` | member (owner opens/closes/reopens) | Periods, close runs/gates, snapshots, corrections | period lists, close run cards with gate list, snapshot accordions, correction forms | close read models | list + ACC + FORM | h=2244 mobile | Acceptable; gates list is good pattern | owner |
| 21 | `/projects/[id]/investors` (`/statements` redirects here) | member | Participant identity & agreement transparency | participants table, active version facts, policy note | funding | TBL + DET | fine | none | R14 policy block |
| 22 | `/projects/[id]/pilot` | member (owner approves) | Opening import, reconciliation checkpoints, exceptions, UAT, rehearsals, access | readiness metrics, pending approvals, staging form with row table, 8 tables, 4 forms | s7 read models | KPI + TBL + FORM | **ovf=790 px mobile, 396 px tablet** — page unusable below 1100 px; h=6799 mobile | Horizontal overflow caused by `.form-grid` inside `form.stack` grid child without `min-width:0` plus a 6-column input table; no section nav | owner |
| 23 | `/projects/[id]/controls` | member | "Is this project ready for real data / who has access?" | role card, 8 gate groups, members table | pilot + control read models | list + TBL | h=4253 mobile | Gates duplicate Pilot's readiness metrics | — |
| 24 | `/projects/[id]/intake` | member (owner for some steps) | Guided first-real-project intake | readiness result, 7 step sections, 23 forms, 9 accordions, 3 tables | intake read models | FORM-heavy | **h=18602 mobile / 14248 laptop** | Single-page wizard with 23 forms; smallest tap 13 px (radios); no step navigation state | — |
| 25 | `/projects/[id]/budget` | member (owner approves) | Budget versions, caps, consumption, FAC | tables, draft form | control read models | TBL + FORM | fine | none | — |
| 26 | `/projects/[id]/integrity` | member | Financial position, signals, policies, exceptions, FX, tax | 9 tables, 6 forms | control read models | TBL | h=7164 mobile | Reference/admin content mixed with operational; very long | — |
| 27 | `/projects/[id]/governance` | member | Risks & decisions | forms in `<details>`, 3 tables | governance | FORM + TBL | fine | none | — |
| 28 | `/projects/[id]/procurement` | member (owner approves) | Suppliers, PR, PO, receiving, invoices | supplier form, 4 tables, action accordions | procurement read models + storage | TBL + ACC + FORM | h=3142 mobile | none blocking | — |
| 29 | `/projects/[id]/agriculture` | member (owner posts sales) | Entire agriculture workspace | 7 hash-anchored sections, 21 forms, 15 tables, 12 accordions | agriculture read models | ALL | **h=16787 mobile / 12191 laptop**; `WorkspaceNav` "sections" are `#hash` anchors to the same page | `autoFocus` on farm/cycle inputs scrolls the page past the header on load (rendered); nav implies separate pages but is one page; `WorkspaceChrome` lacks `sector` on some branches | 3 `ForbiddenCard` branches |
| 30 | `/projects/[id]/livestock` | member (owner approves) | Sites, herds, cohorts, movements, weights, sales, profitability | 10 forms, 2 tables, cards | livestock read models | CARDS + FORM | h=8574 mobile; **two `<h1>`** | Two H1s (chrome + page); monolith | — |
| 31 | `/projects/[id]/livestock/operations` | member | Health, identity, breeding, feeding, FCR | 6 forms, 3 accordions | operations read models | FORM + list | two `<h1>` | as above | — |
| 32 | `/projects/*` not found | any | — | card | — | — | fine | CTA label says "المشاريع" but goes to `/` | — |
| 33 | `/api/health` | public | liveness | JSON | — | — | — | — | excluded from proxy |

## State coverage matrix (rendered / code)

| State | Present | Notes |
|---|---|---|
| Loading | text only (`loading.tsx` ×6) | No skeletons; several project routes have no `loading.tsx` (costs, cash, revenue, close, budget, integrity, governance, procurement, terms, investors, controls). |
| Empty (first use) | yes, per page | Copy varies; mostly good ("لا نعرض بيانات تجريبية"). |
| No-results (filtered) | n/a | No list filtering exists anywhere. |
| Error | app boundary + 6 route boundaries | Arabic, recoverable. |
| Permission denied | `ForbiddenCard` on 9 pages, inline `<p class="error">` on shell | Inconsistent between pages. |
| Offline | none | Server-action forms fail with generic error. |
| Expired session | proxy redirect | Form submit while expired → redirect to `/login`, losing input. |
| Success | `successCount` rotates idempotency key; no visible confirmation | Users infer success from list refresh only. |
| Demo data | `DemoBanner` | Good. |

## Cross-cutting confirmed problems (ranked)

1. **P0 — `/projects/[id]/pilot` overflows horizontally by 790 px at 360 px and 396 px at 768 px** (unusable on phone/tablet).
2. **P0 — Global header consumes ~240 px of a 780 px mobile viewport** on every page; no collapsed navigation.
3. **P1 — Section navigation missing on 10 of 15 project pages** (`WorkspaceChrome` called without `sector`), so the user loses the workspace map exactly where the work happens (costs, cash, funding, revenue, close, operations, pilot, controls, agriculture branches, livestock).
4. **P1 — Hidden routes** `/projects/[id]/terms` and `/projects/[id]/cash` are real workspaces reachable only through inline links.
5. **P1 — Monolithic pages**: agriculture (16.8k px), intake (18.6k px), operations (12k px), livestock (8.6k px) on mobile; hash-anchor "sections" pretend to be pages.
6. **P1 — Duplicate navigation**: WorkspaceNav cards + "روابط التشغيل" chips on Overview; two identical CTA buttons on project shell; Home count tiles duplicate index pages; "المشاريع" global link goes to dashboard.
7. **P2 — Raw enum / English leaks**: `lifecycle_state`, `severity`, `signal_code`, `IN_POSSESSION`, `REGISTERED`, `DEVELOPING`, and a literal `undefined` in the Operations subtitle.
8. **P2 — Duplicate `<h1>`** on livestock pages; not-found CTA label/target mismatch.
9. **P2 — Row actions rendered as stacked `<details>` inside table cells** (costs, revenue, procurement) — rows become 300+ px tall.
10. **P2 — `autoFocus` inside mid-page forms** (agriculture, portfolios) scrolls the user away from the page header on load.
11. **P3 — Tap targets**: radios 13 px, plain links 19 px; no minimum hit area.
12. **P3 — No `loading.tsx`** for most project pages; loading is plain text.
