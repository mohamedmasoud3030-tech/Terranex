# Terranex First Build Brief

## Scope

Build the first clickable product shell and dashboard foundation. Do not attempt to implement every business workflow yet.

## Target stack

- React + TypeScript.
- Vite or Next.js is acceptable, but choose one and document why.
- Tailwind CSS.
- shadcn/ui components.
- TanStack Router or framework router.
- TanStack Query when data fetching starts.
- TanStack Table for complex tables.
- React Hook Form + Zod for forms.
- Recharts or equivalent chart primitives, with visible numeric fallback.

## Required first screens

1. Arabic RTL app shell.
2. Login placeholder or landing-to-app entry.
3. Executive dashboard.
4. Real estate sector list.
5. Agriculture sector list.
6. Livestock sector list.
7. Finance obligations list.
8. Documents and decisions list.

## Required base components

- AppShell
- SidebarNav
- TopBar
- PageHeader
- KpiCard
- SectorCard
- DataTableShell
- EmptyState
- LoadingSkeleton
- ErrorState
- StatusBadge
- MoneyValue
- PeriodFilter
- RecordDetailDrawer

## Non-negotiable UI requirements

- RTL works from the start.
- No emoji icons; use SVG icons.
- CSS variables for colors.
- No hardcoded raw color values inside components.
- Every financial value must show currency and period context.
- Every page/component must have loading, empty, and error state hooks or placeholders.
- Use accessible semantic HTML.
- Keep mock data isolated and easy to replace.

## Mock data rule

Mock data is allowed only for UI scaffolding. It must live in a single clearly named fixture module and be removed or replaced when services are connected.

## PR strategy

Create small PRs:

1. design tokens + RTL shell,
2. dashboard components,
3. sector list pages,
4. finance obligations page,
5. documents page,
6. accessibility and responsive audit.

Do not mix database schema, business logic, and visual system in one PR.
