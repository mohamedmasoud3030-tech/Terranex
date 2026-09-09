# Page Rationalization Plan (Phase 3)

Principle: **no route is removed or changed in behaviour until its replacement and compatibility path are verified**. Route paths are stable contracts (bookmarks, tests, `sectionHref`); the plan reorganizes *navigation and content*, not URLs, except where explicitly listed under Redirect.

## Keep

| Route | Evidence | Roles | Notes |
|---|---|---|---|
| `/login`, `/forgot-password`, `/reset-password`, `/auth/recovery`, `/onboarding`, `/api/health` | tested journeys (`login-redirect`, `password-recovery`, `proxy-auth`) | anon/auth | unchanged |
| `/projects`, `/projects/new`, `/portfolios`, `/portfolios/new`, `/portfolios/[id]`, `/assets` | distinct tasks, distinct data | both | content hierarchy fixes only |
| `/projects/[id]` and all 15 project sub-routes | each is a bounded context page; tests reference paths (`workspace.test.ts`) | both | receive shared header/nav; monoliths get in-page tabs |
| `/investors`, `/statements → /investors` redirect | policy block R14 (`workspace.test.ts`) | both | unchanged |

## Merge (navigation-level, same URLs)

| Decision | Evidence | Impact | Dependencies | Risk | Verification |
|---|---|---|---|---|---|
| `costs` + `cash` presented as one section "التكاليف والنقدية" with second-level tabs | `cash` is not in `WorkspaceNav`; only reachable from a lone chip on Costs | users find bank/reconciliation where the nav already promises it | `SectionTabs` component | low | both URLs render tabs; existing links keep working |
| `funding` + `terms` as "رأس المال" with tabs "الموقف الرأسمالي / الأطراف والاتفاقية" | `terms` unreachable except from Funding's empty gate | agreement setup discoverable | same | low | same |
| Home count tiles → removed; Home shows signals + projects | tiles were pure links duplicating index pages | less noise, attention-first | none | low | rendered check |
| Overview "روابط التشغيل" chips → removed (WorkspaceNav already present) | duplicate nav | shorter page | none | low | rendered check |
| Project shell: two "دخول مساحة القطاع" buttons → one | duplication | — | none | low | rendered |

## Split (in-page, progressive disclosure; no new routes yet)

| Page | Decision | Evidence | Risk | Verification |
|---|---|---|---|---|
| `/projects/[id]/intake` | Stepper: only the current/selected step expanded; readiness summary on top | 18.6k px mobile, 23 forms | medium (forms rely on server nonces; keep them mounted, hide with `<details>`) | idempotency tests still pass; height check |
| `/agriculture` | In-page sticky tabs (المزرعة / الأراضي / الأنشطة / المدخلات / الحصاد / المبيعات / النتائج) — the existing `#hash` anchors become the tab targets; remove `autoFocus` | 16.8k px, auto-scroll bug | medium | scroll position at load = 0; hash navigation still works |
| `/operations` (RE) | Existing chip nav becomes sticky in-page tabs | 12k px | low | — |
| Table row actions (costs, revenue, procurement) | Actions moved from stacked cells into a per-row disclosure ("الإجراءات") rendering below the row | row heights | low | forms unchanged |

Future (not in this milestone set): true route splits `/agriculture/{activities,inputs,harvest,sales,results}` once in-page tabs prove the information architecture; requires nav test updates and redirects from `#hash` anchors.

## Move

| Item | From | To | Evidence |
|---|---|---|---|
| "إدخال المشروع" | global nav | Home first-use checklist + project home ("إدخال مشروع حقيقي" while intake incomplete) + project workspace nav (RE already lists it under الرقابة) | per-project wizard mis-placed as global area |
| "المشاريع" global link | `/` | `/projects` | index unreachable |
| Reference/admin content on `/integrity` (FX contract, tax contract, org consolidation) | always expanded | collapsed reference group at bottom | daily operational vs reference |
| Create forms on list pages (obligation, capital call, contribution, supplier, budget draft) | above lists | after the data, collapsed behind the page's primary action button when the list is non-empty; expanded when list is empty | list-first hierarchy |

## Replace

| Current | Replacement | Reason |
|---|---|---|
| Global header of 4 button-links + stacked sign-out | `AppShell` top bar: brand, 3 primary links (الرئيسية / المشاريع / المحافظ / الأصول), overflow "المزيد" on mobile holding org switcher + sign-out | 240 px header on mobile |
| `WorkspaceNav` card grid (13 cards) | Horizontal scrollable tab strip with `aria-current`, descriptions moved to `title` | takes ~600 px on mobile before content |
| `ForbiddenCard` + inline `<p class="error">` variants | one `PermissionState` | consistency |
| `loading.tsx` text | `PageSkeleton` (header + 3 blocks) | perceived performance |
| Raw enums (`lifecycle_state`, `severity`, RE states) | shared Arabic label maps + `StatusBadge` | leaks |

## Remove (after migration and verification)

- `.context-nav` duplicate chip navs where `WorkspaceNav` is present (Overview).
- `Metric` local helper in `funding/page.tsx` once `Stat` is used.
- Unused CSS after consumers migrate (`.project-context` sticky variant replaced by `ProjectWorkspaceHeader`).

## Redirect

| From | To | Status |
|---|---|---|
| `/projects/[id]/statements` | `/projects/[id]/investors` | exists, keep |
| `/projects/[id]/overview` for AG/LS | sector landing | exists, keep |
| None added in this phase | — | URL surface intentionally unchanged |
