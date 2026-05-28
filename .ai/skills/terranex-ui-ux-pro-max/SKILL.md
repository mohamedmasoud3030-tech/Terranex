---
name: terranex-ui-ux-pro-max
description: Use this skill before any Terranex UI/UX design, review, or implementation task. It adapts the vendored UI/UX Pro Max design-intelligence references for Arabic-first, RTL-first, mobile-first, financial operating system work without changing runtime behavior by default.
---

# Terranex UI/UX Pro Max Adapter

## Required Invocation

Use this skill before changing any Terranex UI code, UI layout, component styling, dashboard presentation, form/dialog behavior, navigation, cards, lists, tables, empty states, charts, or design-system rules.

This adapter is a development-time design gate. It does not provide runtime React code and must not be imported by the app.

## Read Order Before UI Work

1. Read `docs/design-system/MASTER.md` as the Terranex source of truth.
2. Read `docs/design-system/ui-ux-pro-max-vendoring.md` for the vendoring boundary.
3. Review the vendored upstream references under `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/`.
4. Start with `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/ui-ux-pro-max/` for broad UI/UX guidance.
5. Add `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/design-system/` for design-system rules.
6. Add `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/ui-styling/` for styling, hierarchy, spacing, and polish checks.
7. Add `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/brand/` and `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/design/` only when brand or broader design decisions are relevant.

## Terranex Constraints

- Arabic-first: labels, flows, hierarchy, and examples must be natural Arabic, not translated placeholders.
- RTL-first: layout direction, reading order, sidebars, drawers, spacing, icons, and table alignment must be designed for RTL first.
- Mobile-first: every dashboard, form, drawer, list, and financial table must work at narrow mobile widths before desktop enhancement.
- Stack: Terranex UI uses React, Tailwind, and Radix-style primitives; do not introduce unrelated UI frameworks.
- Style: the product is a financial operating system, so prefer calm, precise, audit-friendly, data-dense, trustworthy interfaces.
- Data: never invent fake/demo business data, financial calculations, storage keys, or domain records.
- Currency: use Egyptian pounds as `EGP` / `ج.م` according to existing project conventions.
- Persistence: localStorage is currently the only app persistence layer; do not add Supabase, APIs, IndexedDB, seeds, or new storage.
- Product direction: preserve current routes, dashboard purpose, finance logic, domain model, and investment operating system direction.
- Runtime boundary: never import `.ai/vendor/ui-ux-pro-max/` or `.ai/skills/` files from `src/**`.

## UI Change Gate

Before editing UI runtime files, answer these questions in the task notes or implementation plan:

- Which vendored upstream folders were consulted?
- Which Terranex constraints apply to this UI surface?
- Does the change preserve existing routes, storage, calculations, EGP behavior, and domain data?
- What mobile, RTL, accessibility, and financial auditability checks will be run?
- Is any data shown from existing real application state rather than fake/demo fixtures?

If this is a vendoring/setup task only, do not edit `src/**` and do not change application behavior.

## Terranex UI Checklists

### Mobile Dashboard

- Primary financial question is visible without horizontal scrolling.
- KPI cards stack cleanly at 375px width.
- Period, sector, and source context remain visible.
- Secondary charts or lists do not hide critical totals.
- Loading, empty, and error states do not collapse the page shell.

### Mobile Forms and Dialogs

- Fields use visible labels, not placeholder-only labels.
- Inputs are at least 44px tall and use mobile-appropriate input modes.
- Dialogs and sheets preserve RTL reading order and clear close affordances.
- Errors appear beside the relevant field and focus moves to the first invalid field when appropriate.
- Destructive or dismiss-with-unsaved-changes flows require confirmation.

### Mobile Navigation and Drawer

- Main navigation remains reachable from deep pages.
- Drawer opens from the RTL-appropriate side unless existing app behavior says otherwise.
- Active route is visually clear with text, not color alone.
- Touch targets are at least 44x44px with enough spacing.
- Route paths and navigation destinations are not renamed during UI polish.

### KPI Cards

- Each KPI includes label, value, currency/unit, period, and source context when available.
- Profit/loss uses sign, label, and accessible color semantics.
- Numbers use locale-appropriate formatting and remain readable in RTL.
- Empty or unavailable metrics explain why data is missing.
- Cards do not rely on hover-only tooltips for essential values.

### Sector Cards

- Real estate, agriculture, livestock, and finance remain visually distinguishable but part of one system.
- Sector summaries use existing domain data only.
- Status is not conveyed by color alone.
- Cards remain tappable and readable on mobile.
- Cross-sector comparisons do not imply unsupported calculations.

### Empty States

- Explain what is missing and what the user can do next.
- Do not include fake/demo numbers or seeded examples.
- Keep tone professional, concise, and Arabic-first.
- Empty visuals must not distract from financial auditability.
- Calls to action must preserve existing routes and flows.

### RTL Spacing

- Use logical spacing utilities where possible.
- Icons, chevrons, drawer placement, table alignment, and breadcrumb order respect RTL.
- Numeric values remain scannable and aligned consistently.
- Mixed Arabic/Latin text, `EGP`, and `ج.م` do not break layout.
- Avoid left/right assumptions unless the existing component requires them.

### Accessible Touch Targets

- Interactive controls meet at least 44x44px.
- Adjacent controls have enough spacing to avoid mistaps.
- Focus rings are visible and not removed.
- Icon-only actions include accessible names.
- Hover interactions have tap and keyboard equivalents.

### Financial Tables and Lists

- Tables/lists remain usable at 375px width through responsive cards, horizontal overflow, or prioritized columns.
- Amounts include currency, sign, and status labels where relevant.
- Totals, periods, filters, and source context remain visible.
- Sorting/filtering affordances are accessible and not hover-only.
- Empty, loading, and error states preserve table/list structure.

## Anti-Patterns

Reject UI work that introduces fake data, changes routes, changes storage behavior, changes financial calculations, treats Arabic as an afterthought, uses decorative AI/crypto visuals, hides values behind hover-only tooltips, removes focus states, or imports design-intelligence files into runtime code.
