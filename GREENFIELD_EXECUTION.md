# Greenfield Execution Status

**Updated:** 2026-08-11
**Working branch:** `greenfield/foundation`
**Strategy:** Product-first, Egypt-first, vertical slices

## Completed foundation

- Legacy product frozen at `legacy/pre-greenfield-20260810`; it is not a source for Greenfield behavior.
- Eight Greenfield product documents approved as the conceptual baseline.
- Product-first Egypt launch recorded in `docs/decisions/0001_PRODUCT_FIRST_BUILD.md`.
- Simple modular-monolith delivery recorded in `docs/decisions/0002_SIMPLICITY_AND_VERTICAL_SLICES.md`.
- Customer interviews and a design partner are not build prerequisites.

## Completed batches

### GF-002 / S0 — Executable Foundation and Project Shell

Status: **COMPLETE**.

Merged through PR #84 into `greenfield/foundation` after the Greenfield CI gate passed in full.

Delivered and verified:

- Arabic-first responsive Next.js App Router shell with authentication entry.
- Organization creation/current-organization resolution.
- Real Estate investment project shell: create, list, and open.
- Supabase migration with organizations, memberships, projects, minimal append-only audit events, default-deny RLS, and cross-tenant integrity.
- Server-authoritative validation and commands.
- Deterministic npm dependency lock and Greenfield CI using `npm ci`.
- PostgreSQL 16 fresh replay and two-tenant isolation.

### GF-003 / S1 — Terms & Funding

Status: **COMPLETE — VERIFIED FOR INTEGRATION**.

Integration PR: **#88**, reconstructed directly from the current `greenfield/foundation` after the original Arena PR #87 was found to be based on a stale Greenfield lineage.

Delivered:

1. Tenant-scoped parties and project investors for the S1 workflow.
2. One project agreement envelope with immutable commitment-bearing versions.
3. One governing activated version in S1; participant changes and agreement amendments are frozen after activation until a dedicated amendment/carry-forward workflow exists.
4. Capital calls against the governing version with commitment ceilings.
5. Append-only contributions linked to exact project, investor, capital call, and governing agreement version.
6. Exact project/partner capital positions derived from authoritative records rather than editable balance columns.
7. Arabic/RTL Terms and Funding workflows with normal user-facing currency input rather than minor-unit entry.
8. Exact money transport: PostgreSQL `bigint` storage, text transport to JavaScript, decimal-text parsing with integer arithmetic, and no floating-point financial calculation.
9. Payload-bound idempotency for agreement drafts, capital calls, and contributions.
10. Database-enforced tenant/project scope plus browser table-write denial.

Verified on PostgreSQL 16 and the application CI gate:

- `npm ci` — PASS
- lint — PASS
- focused unit/contract tests — PASS
- production Next.js build — PASS
- TypeScript typecheck — PASS
- fresh migration replay S0 → S1 — PASS
- two-organization RLS isolation — PASS
- same-tenant cross-project reference rejection — PASS
- activated agreement/commitment immutability — PASS
- idempotent same-payload retries and mismatched-payload rejection — PASS
- exact capital rollforward — PASS
- real two-session concurrent over-call protection — PASS
- real two-session concurrent over-contribution protection — PASS
- direct authenticated browser DML denial — PASS

Canonical S1 decision: `docs/decisions/0003_S1_TERMS_AND_FUNDING.md`.

### GF-004 / S2 — Cost & Cash

Status: **COMPLETE — VERIFIED FOR INTEGRATION**.

Delivered:

1. Project cash accounts whose balances are derived exclusively from posted journal lines; no editable balance column exists anywhere.
2. Controlled contribution-to-cash attribution for S1 contributions (`Debit Bank/Project Cash / Credit Contributed Capital`); each contribution posts at most once unless an explicit linked reversal exists; no free-form opening-balance shortcut.
3. Supplier cost obligations reusing the S1 `parties` concept, with explicit `EXPENSE` / `CAPITALIZABLE_WIP` treatment chosen by the user.
4. Smallest real authorization boundary: any active member prepares drafts and imports statements; the organization OWNER authorizes obligations, posts payments, reconciles, voids reconciliations, and reverses batches — with actor and timestamp recorded on rows and in audit events.
5. First balanced project subledger: `journal_batches`/`journal_lines` under five locked semantic account roles, immutable once posted, with database-enforced balance (debits = credits, single currency, project-scope) enforced by a statement-level trigger, so no posted batch can be unbalanced even from privileged writers.
6. OWNER-only partial/full payments bound to obligation, cash account, currency, and project, serialized by obligation row locking, with payload-bound idempotent retries and exact outstanding payable.
7. Deterministic CSV bank-statement import (date, signed amount, currency, description, provider reference) with server-computed SHA-256 fingerprints, duplicate rejection, and idempotent replay; import never creates journal economics.
8. Exact one-to-one reconciliation (same account, currency, amount/sign semantics) with no journal effect, active-match uniqueness per payment and per statement line, and a controlled audited void as the only correction.
9. Linked journal reversal that creates the exact inverse batch, preserves the original, rejects invalid reversal order (payments before obligation; void reconciliation before payment reversal), and is idempotent and audited.
10. One canonical exact money implementation promoted to `src/shared/money` with two consumers (S1 and S2): bigint storage, exact decimal-text parsing including signed amounts, text transport, no JavaScript floating-point financial arithmetic, int64 range protection.
11. Arabic/RTL project-centered UI: `/projects/[id]/costs` and `/projects/[id]/cash` with truthful draft/authorized/paid/reversed/reconciled states, journal drill-down, and audit trail.
12. One ADR for the implemented decisions: `docs/decisions/0004_S2_COST_AND_CASH.md`.

Verified on PostgreSQL 16 and the application CI gate:

- `npm ci`, lint, unit/contract tests (34), production build, typecheck — PASS
- fresh migration replay S0 → S1 → S2 — PASS
- forward upgrade: S2 applied on the current S1 schema with S1 objects intact — PASS
- two-organization isolation and same-tenant cross-project rejection — PASS
- MEMBER vs OWNER authorization boundary and direct browser financial DML denial — PASS
- exact balanced postings for expense, WIP, payment, and contribution attribution — PASS
- unbalanced/partial/mixed-currency batch rejection by the database — PASS
- posted batch/line immutability and exact derived balances from journal lines — PASS
- partial payments, exact outstanding, overpayment rejection, idempotent retries, mismatched-payload rejection — PASS
- real two-session races: concurrent overpayment, duplicate posting, duplicate statement fingerprint, reconciliation against one line — PASS
- duplicate fingerprint rejection, import-without-economics, wrong account/currency/amount reconciliation failure, double reconciliation failure — PASS
- exact inverse reversals, double-reversal rejection, dependency-order rules, contribution repost after linked reversal — PASS
- exact integer/decimal money round-trips and values beyond JavaScript safe integer — PASS

## Explicitly deferred

- agreement amendment/supersession and funding carry-forward rules;
- capital-call cancellation accounting beyond the minimal state representation;
- generic approvals/role framework beyond the S2 OWNER/MEMBER maker–checker boundary;
- accounts payable suite beyond this obligation/payment slice; customer invoices and revenue; VAT/tax;
- statutory/general ledger, chart-of-accounts editor, external accounting adapters, bank APIs/open banking;
- fuzzy, split, or many-to-many reconciliation; multi-currency/FX;
- period close/reopen, allocation and distributions;
- documents/storage platform, notifications, outbox/queues, integrations, and country tax/e-invoicing;
- PWA/offline sync;
- Agriculture and Livestock runtime modules;
- generic repositories, CQRS/event-sourcing frameworks, plugin/rules engines, package workspaces, and speculative shared layers.

## Next active batch

`GF-005 / S3 — Sector Operation` (per the delivery roadmap) or the next material vertical slice chosen by Mohamed. GF-004 closed the Cost & Cash slice end-to-end; the next slice should not restart or duplicate its ledger, money, or authorization primitives.

## Decision rules

- One canonical implementation per concept.
- Search and extend before creating.
- A shared abstraction requires two real consumers.
- Every batch finishes one user workflow across all affected layers.
- Resolve architecture only when the active slice requires it.
- Money and ownership semantics must be exact, server-authoritative, tenant-safe, and auditable.
- Start every implementation branch from the exact latest `origin/greenfield/foundation`; before delivery it must be zero commits behind that target and show no unrelated legacy churn.
- No production deployment or production data changes without explicit authorization.
