# Terranex Architecture Decisions

*Authored by the autonomous architect. Last updated: 2026-05-28.*

---

## ADR-001 — Base currency and exchange rate strategy

**Decision:** Egyptian Pound (EGP) is the absolute base for all consolidated P&L reporting.
Every transaction stores its native currency and amount, PLUS `amount_egp` (the EGP-equivalent at capture time) and `fx_rate` (the rate used). The profitability engine always sums `amount_egp` for cross-currency aggregation.

**Rationale:** Storing the converted value at transaction time avoids retroactive P&L swings caused by rate changes. The raw foreign-currency amount is preserved for audit.

**Supported currencies:** `EGP | USD | OMR | SAR | AED | EUR | GBP`. Extensible via the `Currency` union type.

---

## ADR-002 — Hybrid partner model

**Decision:** A `Partner` record carries a `role` discriminated union:
- `equity_partner` — has `equity_pct` on each project via a `ProjectPartner` join table. Profit/loss split is computed by the profitability engine.
- `counterparty` — appears only as a transaction counterparty (supplier, client, service provider). No ownership stake.

A single partner can be an equity partner on one project and a counterparty on another. This is enforced at the `ProjectPartner` level, not the `Partner` level.

---

## ADR-003 — Livestock / Agriculture dual-track operations

**Decision:** Two parallel systems coexist and are never forced to merge:

1. **Event Sourcing track** — `OperationalEvent` entity with a `type` discriminator (`birth | death | vaccination | feed_consumption | harvest | treatment | weighing`). Each event may optionally create a linked `Transaction` (e.g., a vet visit creates both a `treatment` event and an `expense` transaction). Herd/crop counts are derived by replaying events.

2. **Direct adjustment track** — A `StockAdjustment` entity for manual quantity/value corrections without an event chain. Used for data import, opening balances, and ad-hoc corrections.

**Rationale:** Event sourcing is the correct model for operations that need full audit trails (livestock mortality, crop yield). But forcing every adjustment through event sourcing makes onboarding and data import painful. Both tracks write to the same `asset_balances` materialized view.

---

## ADR-004 — Routing strategy

**Decision:** TanStack Router (file-based routes in `src/routes/`). No Next.js — the project is a pure SPA; server-side rendering adds complexity with zero benefit for a private ERP.

Routes:
```
/                     → redirect to /dashboard
/dashboard            → executive overview
/real-estate          → sector list
/real-estate/$id      → project detail
/agriculture          → sector list
/agriculture/$id      → project detail
/livestock            → sector list
/livestock/$id        → project detail
/finance              → obligations + P&L
/finance/obligations  → receivables/payables
/finance/profitability→ consolidated P&L
/documents            → document vault
/partners             → partner registry
/settings             → app settings (currency, locale)
```

---

## ADR-005 — State management

**Decision:** No global state store (no Redux, no Zustand). State layers:
- **Server state:** TanStack Query (`@tanstack/react-query`). All data fetching, caching, invalidation.
- **URL state:** TanStack Router search params for filters, pagination, selected period.
- **Form state:** React Hook Form + Zod for all data entry.
- **Local UI state:** `useState` / `useReducer` inside components.

**Rationale:** The ERP's complexity is in data, not UI state. Query + Router covers 95% of what a global store would handle, without the boilerplate.

---

## ADR-006 — i18n strategy

**Decision:** Custom lightweight i18n using React Context + typed translation keys. No heavy library (react-i18next) in Phase 1 — the translation surface is finite and known.

- Arabic (ar) — primary, RTL, `dir="rtl"`
- English (en) — secondary, LTR, `dir="ltr"`
- Translation files: `src/i18n/ar.ts` and `src/i18n/en.ts` — typed against a `TranslationKey` union so missing keys are compile errors.
- `html[dir]` is toggled at the root. Tailwind's `rtl:` / `ltr:` variants handle directional layout.

---

## ADR-007 — Component architecture (SOLID)

**Decision:** Components are organized by responsibility, not by feature:

```
src/
  components/
    layout/        # AppShell, Sidebar, TopBar, PageHeader
    ui/            # Primitives: Button, Badge, Card, Input, Select, Table, Drawer, Skeleton, etc.
    domain/        # Business-aware: KpiCard, SectorCard, ObligationRow, TransactionForm, etc.
    charts/        # Recharts wrappers with numeric fallback
  features/
    dashboard/
    real-estate/
    agriculture/
    livestock/
    finance/
    documents/
    partners/
    settings/
  core/
    types/         # All TypeScript domain interfaces — source of truth
    lib/           # Pure utilities: format, fx, date, validation
    hooks/         # Shared hooks: useTranslation, usePeriodFilter, useDebounce
    i18n/          # Translation files and context
    query/         # TanStack Query client + query key factories
  routes/          # TanStack Router route definitions
  data/            # Fixture data (isolated, easily removed)
```

---

## ADR-008 — Error handling / SelfHealingCode pattern

**Decision:** All async operations (data fetching, form submission, file upload) follow this contract:
1. Loading state: skeleton or spinner shown immediately.
2. Error state: `ErrorBoundary` at feature level catches render errors; query errors surface via `ErrorState` component with retry action.
3. Empty state: every list/table has an explicit empty state component.
4. Optimistic updates: mutations use TanStack Query's `onMutate` / `onError` rollback pattern.
5. Form validation: Zod schemas are the single source of truth for both client and (future) server validation. Errors surface inline, never as alert dialogs.

---

## ADR-009 — Database schema (Supabase, future)

**Core tables:** `sectors`, `projects`, `assets`, `partners`, `project_partners`, `transactions`, `operational_events`, `stock_adjustments`, `documents`, `obligations`, `exchange_rates`

**Profitability view:** `v_project_profitability` — computed from `transactions.amount_egp` grouped by project, with equity split applied via `project_partners.equity_pct`.

**RLS strategy:** Row-level security by `company_id` for future multi-company support, even though Phase 1 is single-company.

---

## ADR-010 — Package additions (Phase 2)

| Package | Purpose |
|---|---|
| `@tanstack/react-router` | Type-safe routing |
| `@tanstack/react-query` | Server state |
| `@tanstack/react-table` | Complex data tables |
| `react-hook-form` | Form state |
| `zod` | Schema validation |
| `recharts` | Charts |
| `@radix-ui/react-*` | Accessible UI primitives (shadcn base) |
| `class-variance-authority` | Component variant system |
| `clsx` + `tailwind-merge` | Class merging |
| `date-fns` | Date utilities |

