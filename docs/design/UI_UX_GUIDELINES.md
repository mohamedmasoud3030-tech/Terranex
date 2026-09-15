# Terranex UI/UX Guidelines & Best Practices

> **Version:** v1 — based on the `design/ui-ux-upgrade` branch (PR #176). Arabic original: [`UI_UX_GUIDELINES_AR.md`](./UI_UX_GUIDELINES_AR.md).
> **Methodological sources:** inspired by [ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) (UX rules as data: do / don't / severity / code) and [shadcn/ui](https://github.com/shadcn-ui/ui) (composition first, semantic tokens, incorrect/correct code pairs).

---

## When this guide applies (borrowed from ui-ux-pro-max's "When to Apply / Skip")

**Apply it when:** building a new page or section, creating or changing a shared component, choosing colours/fonts/spacing, reviewing interface code, adding a data table or financial figure, changing navigation, forms, or loading/error/empty states.

**Skip it for:** pure backend work (DB/RLS/API), non-UI performance, infrastructure.

**The decisive test:** if the change alters *how a screen looks, how it is used, or how its numbers are read* — this guide applies.

---

## The governing rule (from the product's own soul)

> **Every number says where it came from. Every state is understandable without colour. Every consequential action explains its effect before it can be submitted.**

A screen that looks impressive while making an investment fact harder to verify is a failure of this system, however good it looks.

---

## The ten rule categories by priority (adapted from ui-ux-pro-max's priority table)

| # | Category | Severity | Key checks |
|---|---|---|---|
| 1 | Accessibility | Critical | Contrast ≥ 4.5:1, visible focus, named tables, `scope="col"` |
| 2 | Interaction & keyboard | Critical | Tab order = visual order, no focus traps, every action keyboard-operable |
| 3 | Loading / error / empty states | High | `loading.tsx` per dynamic route, `error.tsx`, `EmptyState` with a next step |
| 4 | Composition from shared components | High | No hand-rolled markup where a primitive exists — see the map below |
| 5 | RTL & responsiveness | High | Logical properties only, 360px target, no horizontal scroll |
| 6 | Tokens, type & colour | Medium | No literal colour outside `:root`, tabular figures via `.num` |
| 7 | Motion | Medium | `prefers-reduced-motion`, motion only where it means something |
| 8 | Forms & feedback | Medium-High | Visible labels, inline validation, feedback after submit |
| 9 | Navigation | High | Grouped labels, active state, no dead links |
| 10 | Financial data & tables | Terranex-specific | Basis + "as of" + currency on every figure |

---

## 1) Accessibility — critical

### 1.1 Contrast
- **Do:** every text token ≥ 4.5:1 on every background it can sit on (the project measures this from the tokens in `tests/design-system.test.ts` — which found a real AA failure: `--muted-2` at 3.77:1, since fixed).
- **Don't:** "grey on grey", or contrast judged by eye alone.

### 1.2 Tables
- **Do:** every `<table>` has an accessible name (`aria-label` or `aria-labelledby`), every header cell carries `scope="col"`. The PR covered 81/81 tables.

```tsx
// ✅ correct
<table aria-labelledby="suppliers-heading">
  <thead>
    <tr><th scope="col">المورد</th><th scope="col" className="num">الرصيد المفتوح</th></tr>
  </thead>

// ❌ wrong
<table>
  <thead><tr><td>المورد</td><td>الرصيد</td></tr></thead>
```

### 1.3 Label sections by their own heading
- **Do:** `<Section>` wires `aria-labelledby` for you.
- **Don't:** hand-rolled `<section className="card">` without the association (86 bare `<h2>` remain — see the gap table).

### 1.4 Never state by colour alone
- **Do:** every status tone (success/warning/danger/info/neutral) ships a glyph via `.status::before`; `.tone-open` / `.tone-void` stay distinguishable without colour.
- **Don't:** green/red alone for success/error.

### 1.5 Focus
- **Do:** `--focus` is deliberately not the brand colour (a focused control must never read as a selected one); the `:focus-visible` ring is always visible.
- **Don't:** remove outlines without a replacement, or hand-roll `z-index` above overlay components.

---

## 2) Interaction & keyboard — critical

- Tab order matches visual order; test every action without a pointer.
- Adequate touch target size for interactive elements; never below 24px with spacing.
- Never hide information or actions behind hover alone (ui-ux-pro-max "Touch & Interaction").
- `Section collapsible` uses native `<details>` — works without hydration and without JS. Keep it that way.

---

## 3) Loading / error / empty states — high

| State | Canonical component | Rejected alternative |
|---|---|---|
| Route loading | `PageSkeleton` in `loading.tsx` | A dangling spinner or white screen |
| Route error | `RouteError` in `error.tsx` | A stack trace or raw English message |
| No data | `EmptyState` + a next step | An unexplained empty table |
| No permission | `PermissionState` | Silent hiding or a raw 403 |
| In-page notice | `Banner` | A hand-coloured div |

Rules adapted from ui-ux-pro-max (Empty States, Loading Indicators, Submit Feedback):
- **Emptiness is a fact plus a next step:** "no suppliers yet — add the first one", not just "no data".
- **Feedback is immediate:** a clear submitting state (disabled button + indicator), then success/failure — never a silent freeze.
- **`aria-busy` / `role="status"`** on loading states (already in `PageSkeleton` — preserve it).

---

## 4) Composition from shared components — high (the shadcn way: "Compose, don't reinvent")

**The principle:** if a primitive exists in `src/shared/ui` — use it; do not write the markup by hand. The shared component bundles semantics, accessibility and tokens in one place.

### The "component instead of hand-rolled markup" map

| Instead of… | Use… |
|---|---|
| A hand-built `<header>` with title + button | `<PageHeader eyebrow title description actions badge backHref>` |
| A hand-rolled `<section className="card stack">` | `<Section title>` (gives `aria-labelledby` for free) |
| A hand-built `<div className="stat">` | `<StatGrid>` + `<Stat label value hint href tone>` |
| A coloured `<span>` for a state | `<StatusBadge tone>` (five semantic tones) |
| A custom notice div | `<Banner tone role>` |
| A hand-written "no data" | `<EmptyState title description action headingLevel compact>` |
| A spinner / blank screen | `<PageSkeleton blocks withNav>` |
| Hand-rolled link tabs | `<SectionTabs>` / `<InPageTabs>` |
| A hand-built sector chip | `<SectorChip sector>` |
| A big number without context | `<Figure value basis asOf negative>` |

### Rules adapted from shadcn's literal rulebook

- **`className` is for layout, not for overriding a component's colours or typography.**
- **Built-in variants before custom styles:** use the component's `tone` / `headingLevel` / `compact` before writing new CSS.
- **Icons are objects, not string keys**, and carry no sizing classes inside components.
- **Overlay containers always own a Title** — if any are added later, a `DialogTitle` equivalent is mandatory for accessibility.
- **Buttons have no `isLoading`:** compose (disabled + indicator), as the project's forms already do.

**A worked example:**

```tsx
// ✅ correct composition — everything from the shared kit
<PageHeader eyebrow="المحفظة الاستثمارية" title="مشاريع العقارات" badge={<SectorChip sector="REAL_ESTATE" />} />
<Section title="أوامر الشراء المفتوحة" description="بانتظار الاستلام">
  {orders.length === 0
    ? <EmptyState title="لا أوامر شراء بعد" description="أنشئ أول أمر شراء للمشروع" action={<Link className="button" href="…">أمر شراء جديد</Link>} headingLevel={3} />
    : <table aria-labelledby="…">…</table>}
</Section>

// ❌ hand-rolled — same look, weaker semantics, guaranteed drift
<section className="card stack">
  <h2>أوامر الشراء المفتوحة</h2>
  <p className="muted">لا توجد بيانات</p>
</section>
```

---

## 5) RTL & responsiveness — high

- **Logical properties only** in CSS: `inset-inline`, `border-inline`, `margin-inline` — never `left`/`right` (a foundational rule in `globals.css`).
- Numbers are end-aligned inside RTL via `.num` — built in; do not reinvent it.
- Wide tables: controlled horizontal scroll or the card-stack mode on mobile — never a broken layout.
- The **360px target** is expressed in the breakpoints but has **not been checked on a real device** (an acknowledged gap) — see the work plan.

---

## 6) Tokens, type & colour — medium (the shadcn way: semantic, never raw)

- **No literal colour outside the `:root` block** — `tests/design-system.test.ts` fails the build on violation (the equivalent of shadcn's "No raw hex in components").
- Semantic status colours: `--success/--warning/--danger/--info`, each with ink + wash + edge — never hand-mix shades.
- **Sector identity ≠ meaning:** `--sector-*` is for identity only (chip/rail/glyph); state always comes from the adjacent `StatusBadge`. A portfolio card with no sector gets the neutral rail.
- Focus `--focus` is not the brand colour — on purpose.
- **Tabular figures are mandatory** wherever two numbers can be compared: `.num` / `.stat-value` / `.facts dd`.
- No external webfont — the app renders identically offline with zero third-party requests. Keep it that way.
- Type: kufi/display for headings, text face for body, `--fs-300…800` — no custom sizes.

---

## 7) Motion — medium

- `prefers-reduced-motion` is supported — any new motion must respect it.
- One duration for everything is a bug (ui-ux-pro-max): short hover feedback (150–250ms); heavier transitions only where there is spatial meaning.
- Never animate `width`/`height` (layout thrashing) — animate transform/opacity.
- Depth comes from borders, not shadows (a serious financial system) — no decorative shadows.

---

## 8) Forms & feedback — medium-high (from ui-ux-pro-max form rules + shadcn patterns)

- **A visible label for every field** (`label` wired with `for`) — never a placeholder posing as a label.
- **Validate on blur** for most fields, keeping inline errors visible.
- **A focusable error summary** at the top of the form on failed submit, linking each item to its field, alongside inline errors.
- **Idempotent submission** — the project tests this in `*-forms-idempotency.test.tsx`; any new form needs the same test.
- An option set of 2–7 choices is a toggle group, not hand-rolled buttons with manual active state (shadcn).
- Submit button: disabled + indicator while in flight, then a clear success/failure.

---

## 9) Navigation — high

- **The grouped `WorkspaceNavGrouped`** presents four named groups; membership is declared explicitly in `GROUP_SPECS` and guarded by `assertSectionGroupingIsExact()` plus 20 tests. Any new section must declare its group explicitly.
- **A clear active state** for the current section.
- **No dead links:** `in-page-navigation.test.ts` parses every tab href against the ids the page actually renders — point every anchor at an existing `id`.
- **Decision order, not decoration order:** unresolved exceptions render above the money (attention before money).

---

## 10) Financial data & tables — the Terranex-specific rule

Every balance carries the triple:

1. **its basis** — what it was computed from;
2. **its "as of"** — when it was true;
3. **its currency.**

```tsx
<Figure basis="النقدية" value={formatMinorUnits(cash, currency)} asOf="بعد التحويل المعتمد" />
```

- No `Number()`, `parseFloat` or `toFixed` in money paths — bigint minor units through `formatMinorUnits`.
- **No raw enum codes on screen** (`PENDING` / `OWNER` in English inside an Arabic interface): `recordStatusLabel()` and `roleLabel()` with raw-code fallback, never a guess.
- Lead with the four decision figures, disclose the rest (decision-critical before supporting).
- A dashboard roll-up never authorizes a new ledger or cross-project accounting behaviour (an AGENTS.md governing rule).

---

## Pre-merge checklist for any UI PR

- [ ] No literal colour outside `:root` (test-enforced)
- [ ] No inline `style={{}}` in `src`
- [ ] Every table named + every header `scope="col"`
- [ ] Every `force-dynamic` route has `loading.tsx`; every workspace route its `error.tsx`
- [ ] Empty states via `EmptyState` with a next step (inline `<p className="empty">` notes are the documented exception)
- [ ] Numbers carry `.num` + currency + basis + asOf wherever compared
- [ ] No raw enum codes; Arabic labels through the label functions
- [ ] Logical properties only (no left/right)
- [ ] `prefers-reduced-motion` and `forced-colors` respected
- [ ] A new token must have a real user — no dead weight
- [ ] Regenerate `docs/design/design-system.html` via `node scripts/build-design-gallery.mjs` after any CSS change
- [ ] Regenerate `ROUTE_REVIEW.md` via `node scripts/route-review.mjs` after any route change

---

## The acknowledged gaps (from the honest ROUTE_REVIEW) and their state after two execution passes

| # | Gap | State after the passes |
|---|---|---|
| 1 | `<Section>` adoption: was 17 vs 101 hand-rolled | **Done:** every titled card section in the workspace now composes the primitive — **131 vs 6** remaining, all deliberate (three `shell-form` page shells, which are h1 form surfaces, not titled sections, plus three heading-less content cards inside logical sections). Mid-execution it also emerged that **the route-review counter itself was attribute-order-blind**: `<section id="x" className="card stack">` was never counted at all — twelve sections in close and pilot were invisible — and it now reads attributes in any order (the same order-sensitivity lesson) |
| 2 | 122 bare `<h2>` without `aria-labelledby` | **Done:** down to **17** (the remainder sits inside special structures such as the multi-step intake wizard) |
| 3 | "16 hand-rolled empty states" | **Evidence-based correction:** 14 are `<p className="empty">` inline notes, **a deliberate documented form**; the other two in agriculture were genuine offenders that escaped the regex by class order — migrated to `EmptyState`, and the guard is now order-insensitive |
| 4 | No real browser check (360px / focus order / motion) | **Mitigated:** the app now runs in a live preview with real Supabase keys, so 360px can be checked by hand; a full automated Playwright pass remains open |
| 5 | One workspace route without its own `error.tsx` | **Closed as documented-won't-fix:** `/statements` is a redirect-only route (waiting on the R14 policy pack) and renders nothing of its own — a route-level boundary there would be dead weight; the workspace boundary is the correct net, and the reason is recorded in ROUTE_REVIEW |

**Added in this pass:** the two hand-rolled "unauthorized" cards (investors, intake) now go through `PermissionState`; the readiness-result section (a topline pattern) was migrated by hand with its description passed as a ReactNode; a "no raw enum" guard landed (`tests/no-raw-enum-codes.test.ts`) together with two copy fixes for prose leaks ("فترة OPEN", "نسخة اتفاقية ACTIVE"); and `ROUTE_REVIEW.md` became a **CI merge gate** via `--check`.

**Migration rule:** no "redesign" — replace hand-rolled markup with the matching component only, changing no route, permission, business rule, or data source (the same contract as the current PR).

---

## How these guidelines are machine-enforced (lessons from both repos)

From **ui-ux-pro-max-skill** we learned that an uncheckable rule bleeds: their rules are CSV rows with severity and code. From **shadcn/ui** we learned that a rule is written as an incorrect/correct pair. This project already combines both through tests:

1. **Extend `tests/design-system.test.ts`** with every new textually-checkable rule (e.g. no `<section className="card` outside `src/shared/ui` — Section adoption can be ratcheted with explicit thresholds).
2. **The `empty-state` test is a standing lesson:** a guard that depends on class order is not a guard — two real states in agriculture escaped `card(?: stack)? empty` purely by being written `card empty stack`. Any textual markup check must be order-insensitive (`card[^"]*\bempty\b`).
3. **Add a "no raw enum" test:** grep the values the CHECK constraints permit against the label functions.
4. **`ROUTE_REVIEW.md` is a merge gate now:** a `node scripts/route-review.mjs --check` CI step fails the build on count drift (an unnamed table = a regression).
5. **Document a new rule as an incorrect/correct pair here first**, then turn it into a test — a rule lives where it is checked.

---

## Appendix: the source of each rule group

| Group | Origin | Terranex adaptation |
|---|---|---|
| Ten priority categories, do/don't/severity | ui-ux-pro-max (`ux-guidelines.csv`, quick-reference) | Re-ordered around a data-dense financial operations system |
| Empty states, loading, submit feedback, touch, keyboard | ui-ux-pro-max (119 UX rules) | Bound to the existing components (`EmptyState`, `PageSkeleton`, `Banner`) |
| "Component instead of hand-rolled markup", variants before styles, semantic colours, className for layout only | shadcn (`skills/shadcn/rules`) | Drawn onto the sixteen actual `src/shared/ui` primitives |
| Token discipline and status glyphs | Both repositories | Already the foundation of PR #176 and test-enforced |
| The basis/as-of/currency triple and tabular figures | Terranex-specific (anti-hallucination governance) | — |
