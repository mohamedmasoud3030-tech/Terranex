---
name: terranex-ui-ux-pro-max
description: Use this skill when designing, reviewing, or implementing Terranex UI/UX. It adapts the uploaded UI/UX Pro Max sources into Arabic-first, financial-grade, data-dense, accessible product rules for Terranex.
---

# Terranex UI/UX Pro Max Skill

## Use when

- Creating a new Terranex page or component.
- Reviewing dashboard, table, form, chart, or navigation design.
- Selecting colors, typography, chart types, or layout density.
- Preparing a UI implementation prompt for Codex or another coding agent.

## Source of truth

Read these files first:

1. `docs/design-system/MASTER.md`
2. The relevant file under `docs/design-system/pages/`
3. `docs/implementation/first-build-brief.md`

## Product stance

Terranex is a professional Arabic-first investment operating system. The UI must be calm, precise, audit-friendly, data-dense, and accessible.

## Required checks

Before building or reviewing UI, verify:

- RTL layout is correct.
- Arabic labels are clear.
- Financial numbers show currency, period, sign, and source path.
- Tables are sortable/filterable where needed.
- Complex tables have mobile handling.
- Forms have visible labels and field-level errors.
- Charts have visible numeric fallback.
- Focus rings and keyboard navigation work.
- Touch targets are at least 44x44px.
- Loading, empty, and error states exist.

## Recommended implementation defaults

- Use shadcn/ui primitives.
- Use CSS variables for theming.
- Use TanStack Table for complex tables.
- Use React Hook Form + Zod for forms.
- Use `Noto Kufi Arabic` or `Cairo` for Arabic-first UI.

## Anti-patterns

Reject UI that:

- looks like a crypto dashboard,
- uses decorative AI gradients,
- uses emojis as icons,
- hides numbers behind hover-only tooltips,
- has weak contrast,
- omits audit trail paths,
- treats Arabic as an afterthought,
- mixes mock financial logic with production logic.
