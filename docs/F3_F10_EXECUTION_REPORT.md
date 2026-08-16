# F3–F10 Execution Report — Contract Finance → Portfolio Control

**Date:** 2026-08-16
**Branch:** `arena/01a00890-terranex`
**Base SHA:** `8aafc694845f5565e215d3eb1b72afda80be0744` (merge of PR #145)

This session executes the remaining mission phases in order (F3 → F10) under the
canonical "Build Everything Independent First" rule: complete every feature whose
correctness does not depend on unresolved legal/economic policy, defer only the
smallest rule-dependent portion, and never invent a default or a guessed number.

## Phase outcomes

| Phase | Before this session | After this session |
|---|---|---|
| F3 — Obligations & Contract Finance | PARTIAL (obligation backbone only) | **COMPLETE** |
| F4 — Budget Control | NOT STARTED | **COMPLETE** |
| F5 — Approval & Exception Engine | Maker/checker + SoD only | **COMPLETE** |
| F6 — Currency & Tax Contract | Exact money only | **COMPLETE** |
| F7 — Period Close | mostly present, unaudited | **COMPLETE (audited)** — `docs/F7_PERIOD_CLOSE_AUDIT.md` |
| F8 — Evidence & Financial Integrity | Evidence only | **COMPLETE** |
| F9 — Project Performance | sector read models only | **COMPLETE** |
| F10 — Portfolio Control | Portfolio identity only | **COMPLETE** |

## What was built (per phase)

### F3 — Contract finance (migration `20260816050000_f3_contract_finance.sql`)
- `project_milestones` with PENDING→ACHIEVED lifecycle; an achieved milestone is immutable.
- `cost_obligation_terms` (FIXED_DATE / NET_DAYS / MILESTONE_SCHEDULE) with explicit retention; draft-only editing; retention must be strictly below the obligation amount.
- `cost_obligation_schedule_lines` with milestone linkage, retention-line flag, and statement-level totals guards (schedule ≤ obligation, scheduled retention ≤ declared retention).
- `cost_obligation_disputes` (append-only, one OPEN dispute per obligation, maker/checker resolution).
- `cost_obligation_retention_releases` (append-only, OWNER-gated, release ≤ declared retention, optional achieved-milestone requirement).
- Payment approval hardened: an open dispute blocks payment; withheld retention narrows the payable ceiling until explicitly released. The full payable is always posted at authorization — retention never creates a second ledger.
- Read models: `cost_obligation_due_read` (computed due date, aging buckets, dispute/retention flags), `cost_obligation_aging_read`, `cost_obligation_schedule_read`, `project_milestones_read`, `cost_obligation_retention_releases_read`.

### F4 — Budget control (migration `20260816051000_f4_budget_control.sql`)
- `project_budgets` (ORIGINAL/REVISED, versioned, DRAFT→APPROVED→SUPERSEDED), approved periods never overlap, approved budgets immutable except the controlled supersede transition.
- `project_budget_lines` with ceilings per canonical cost treatment (EXPENSE / CAPITALIZABLE_WIP — no invented account taxonomy).
- Maker/checker approval; OWNER-gated supersede that copies lines into version+1; preparer/OWNER-gated draft deletion.
- **Ceiling enforcement at obligation authorization**: an approved budget covering the transaction date caps the committed amount per treatment. Only an APPROVED `BUDGET_CEILING` exception (F5) raises the ceiling by its explicit amount.
- `project_budgets_read` + `project_budget_purchase_commitment_read` (PO open commitments reported as their own unallocated class — never silently mapped to a cost treatment).

### F5 — Approval & Exception engine (migration `20260816052000_f5_approval_exception_engine.sql`)
- `approval_policies`: a closed set of policy domains with optional per-currency thresholds that can only add strictness (evidence gate); OWNER-only. No generic rules engine; maker/checker and the OWNER floor are hard invariants no policy can relax.
- `approval_exceptions`: cross-domain exception registry (BUDGET_CEILING, PAYMENT_BLOCKED, INVOICE_TOLERANCE, CLOSE_GATE, DISPUTE_HOLD, OTHER_DISCLOSED) following violation → exception → evidence → authority → decision; append-only; opener cannot decide; VOID = opener's withdrawal.
- `f5_attach_payment_evidence` + payment policy gate wired into `approve_cost_payment`; obligation and budget approval policy gates wired in.
- `approval_exception_registry_read` unifies the three exception families (approval, procurement invoice tolerance, close-run gates) into one surface.
- `project_budget_consumption_read` lives here (joins the exception registry): plan vs committed vs paid vs exception relief vs remaining vs the honest forecast (max of ceiling+exceptions and committed).

### F6 — Currency & tax contract (migration `20260816053000_f6_currency_tax_contract.sql`)
- `fx_rate_snapshots`: immutable rational (numerator/denominator) rate facts with source and date; one per (org, pair, date).
- `fx_convert_exact()`: deterministic integer conversion (half-up); zero converts to zero; non-positive rates rejected.
- `fx_conversion_log`: append-only explicit conversions; rate snapshot must match the pair; snapshot date cannot follow conversion date. Nothing is ever converted implicitly.
- `organizations.reporting_currency` + OWNER-gated `f6_set_org_reporting_currency`.
- `tax_registry`: the explicit tax-treatment contract (WHO computes: external assessor recorded / not recorded / deferred pending advisory) — a registry, never a calculation engine; no computed tax is posted (BD-010 safe).
- Read models: `fx_rate_snapshots_read`, `fx_conversion_log_read`, `tax_registry_read`.

### F7 — Period close (migration `20260816054000_f7_period_close_health.sql`)
- Full audit against exit criteria: `docs/F7_PERIOD_CLOSE_AUDIT.md` — all close/correction criteria PASS.
- `period_close_health_read`: per-scope close pipeline health (open period, last closed, close runs, exceptions, corrections, F3 disputes/overdue) with an explicit `close_health` state.

### F8 — Financial Integrity Center (migration `20260816055000_f8_financial_integrity_center.sql`)
- `financial_integrity_signals_read`: derived signals over the whole stack — UNBALANCED_BATCHES (CRITICAL), OVERDUE_OBLIGATIONS, OPEN_DISPUTES (CRITICAL), RETENTION_DUE_FOR_RELEASE, UNRECONCILED_PAYMENTS, UNMATCHED_STATEMENT_LINES, OPEN_BUDGET_EXCEPTIONS (CRITICAL), OPEN_INVOICE_EXCEPTIONS, OPEN_CLOSE_EXCEPTIONS, OPEN_CORRECTION_REQUESTS, STALE_DRAFT_OBLIGATIONS, NO_APPROVED_BUDGET, BUDGET_NEAR_CEILING, ORG_FX_GAP (INFO). No invented score — every signal is computed from authoritative facts.

### F9 — Project performance (migration `20260816056000_f9_project_performance.sql`)
- `project_financial_position_read`: the authoritative per-project position (cash, receivable, revenue, cost of sale, expense, WIP, contributions, payable, paid, retention, dispute/overdue counts) derived only from un-reversed journal postings plus F3 registers. The prior phase report claimed this view existed; it did not — it now does.
- `project_performance_read`: position + budget-vs-commitment-vs-actual + close health. No ambiguous "profit" number; every KPI separates its facts.

### F10 — Portfolio control (migration `20260816057000_f10_portfolio_rollup.sql`)
- `portfolio_financial_rollup_read`: per-currency sums over current members' authoritative project facts; a roll-up is never a second ledger; currency sums are never mixed.
- `organization_financial_consolidation_read`: per-currency rows plus an honest CONSOLIDATED row. Converted columns exist only when the org declares a reporting currency AND a recorded rate snapshot (≤ today) exists per pair; otherwise the row says exactly why (NO_REPORTING_CURRENCY / NO_RATE_SNAPSHOT / CONSOLIDATION_INCOMPLETE_NO_RATE_SNAPSHOT). Converted values are never guessed.

## Management surfaces

- Project workspace: new `الموازنة` (budget) and `مركز النزاهة المالية` (integrity) sections in `src/features/workspace/nav.tsx` for every sector.
- `/projects/[projectId]/budget` — budget versions, consumption vs ceilings, create/approve/supersede/delete forms.
- `/projects/[projectId]/integrity` — integrity signals, unified exception registry, approval policies, FX snapshots/conversions, org reporting currency, consolidation, tax registry.
- `/projects/[projectId]/costs` — due/aging summary cards, aging bucket per obligation, payment terms, disputes, retention release and milestones management.
- `/portfolios/[portfolioId]` — financial roll-up table with conversion state.
- App layer: `src/features/control/{schema,actions,queries}.ts` with Arabic validation messages and exact money transport.

## Verification

- Real PostgreSQL replay (PGlite, actual PG engine): **all 82 migrations apply in order**.
- New behavioral gate `supabase/tests/88_f3_f10_finance_control.sql` exercises, with real actors and assertions: milestone immutability, terms/retention guards, schedule ceilings, budget overlap/maker-checker/ceiling/exception-relief/supersede, dispute blocking payment, retention narrowing payment, policy evidence gates, FX exact conversion + immutability, tax registry, integrity signals, project position reconciliation to posted facts, portfolio roll-up + org consolidation conversion, cross-tenant isolation. **PASS**.
- New forward-upgrade gate `supabase/tests/89_f3_f10_forward_upgrade.sh`: pre-F3 boundary replay (73 migrations) + F3–F10 upgrade phase with full surface verification and the pgcrypto qualification check. **PASS**.
- The F3–F10 family is excluded from the older stage fixtures' replay allowlists (S3/S4/S5/S6/S7 and agriculture stages), matching the established stage-boundary pattern.
- pgcrypto hosted-schema compatibility: migration `20260816057500` re-runs the bounded qualification pass so suite 33 sees zero unqualified `digest(` calls (caught by CI; fixed).
- Unit tests: `tests/f3-f10-control.test.ts` — schema contracts + migration invariants. `npm test`: **615/615 PASS**.
- `npm run typecheck`: PASS. `npm run lint`: PASS. `npm run build`: PASS.
- GitHub CI (PR #147): **app PASS · database PASS · SonarCloud quality gate PASS** (the database job replays every migration, SQL suite, forward-upgrade fixture and concurrency suite on real PostgreSQL 16).

## Still deferred (rule-dependent only — unchanged from the register)

- COGS / inventory valuation method, IAS 41 biological assets, tax *calculation* — company accounting policy.
- Investor entitlement, ownership, allocation, distribution formulas — `docs/OPEN_BUSINESS_DECISIONS.md` BD-001…BD-012 (R14 policy pack after R13).
- Full Company Simulation (R13) — now unblocked by F4/F10 and ready to be built next.

## Remaining before R13 (next logical increments)

- R13 Full Company Simulation (the hard-stop gate), then the R14 policy pack.
- R12 production-hardening closeout items (observability/export/DR evidence) remain as documented in `docs/P4_P17_PHASE_STATUS.md`.

*Report generated 2026-08-16 on `arena/01a00890-terranex`*
