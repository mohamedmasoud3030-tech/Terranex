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

### GF-005 / S3 — Real Estate Sector Operation

Status: **COMPLETE — VERIFIED FOR INTEGRATION**.

Delivered:

1. One immutable Real Estate project profile (strategy and optional jurisdiction), multiple economic property assets per project, and cadastral parcels with exact decimal quantity plus an explicit area unit.
2. Command-driven property lifecycle and immutable predecessor-linked history for `CANDIDATE → DUE_DILIGENCE → ACQUIRING → HELD → DEVELOPING → HELD`; every transition records actor, time, reason, and material evidence, and concurrent commands cannot consume the same prior state twice.
3. Acquisition as an operational/legal fact reusing the S1 Party and exact shared money implementations. An optional consideration obligation must match the existing S2 project, seller, amount, and currency; acquisition itself creates neither payment nor journal economics.
4. Typed acquisition-check, title, possession, permit, and inspection facts with responsible actor, dates/result, evidence reference, and immutable confirmation. `HELD` requires a recorded contract plus separate effective passed title and possession evidence; payment is displayed independently and cannot imply control.
5. Property/optional-parcel development phases and phase-owned milestones with planned dates, derived actual dates, bounded planned/active/completed/cancelled transitions, actor/time/reason history, and no task-management or construction-ERP framework.
6. Confirmed Real Estate events with occurred/recorded time, normalized project/property/parcel/phase/milestone hierarchy, responsible member, notes/location/evidence, and optional quantity that is valid only with an explicit unit.
7. Numbered immutable proposed/approved property budget versions, OWNER-only approval, and preserved prior approved versions rather than mutable budget balances.
8. `PropertyCostItem` as a normalized operational dimension on one authoritative S2 obligation, with property/optional parcel/phase/category and policy reference but no amount or balance column. Composite database references reject cross-tenant, cross-project, and wrong property/parcel/phase combinations.
9. Exact cost control derived from existing S2 facts: latest approved budget; committed as the outstanding amount on active authorized obligations; actual/cost-to-date as debit-minus-credit on posted Project Expense / Development WIP journal lines including reversals; variance as budget minus actual. Every amount drills to the S2 obligation and originating batch.
10. Proposed/approved management valuation with date, source, method, exact amount, assumptions, confidence, reviewer, and evidence, explicitly isolated from cash, revenue, realized result, journal posting, and automatic accounting classification.
11. Existing MEMBER prepare / OWNER material-confirm authorization, default-deny RLS, SELECT-only browser tables, authenticated locked-search-path RPC writes, payload-bound idempotency, immutable confirmed facts, and append-only audit history; no generic roles or approval engine.
12. Arabic/RTL project Operations workspace covering current state, assets/parcels, acquisition/control, phases/milestones, valuation, cost control/drilldown, and operational timeline, with responsive 360px reflow and truthful loading, empty, error, and forbidden handling.
13. Metadata-only evidence references were sufficient for this slice; no private Storage/DMS or offline/PWA machinery was scaffolded.
14. Canonical decision: `docs/decisions/0005_S3_REAL_ESTATE_OPERATIONS.md`.

Verified on PostgreSQL 16 and the application CI gate:

- `npm ci`, lint, focused/unit contract tests (47), production build, and typecheck — PASS
- fresh migration replay S0 → S1 → S2 → S3 — PASS
- forward upgrade from the exact merged S2 schema with S2 objects preserved — PASS
- two-organization RLS isolation and same-tenant cross-project rejection — PASS
- wrong property/parcel/phase/milestone hierarchy and finance-dimension rejection — PASS
- invalid lifecycle rejection, valid complete lifecycle/history, and effective title + possession gate for `HELD` — PASS
- acquisition/title/possession/payment independence and acquisition-without-journal/payment — PASS
- immutable/versioned exact budget history and OWNER approval boundary — PASS
- committed and actual reproduction from S2 obligations/payments/journal facts plus originating-batch drilldown — PASS
- management valuation approval with no cash/revenue/result/journal effect — PASS
- direct authenticated browser DML denial and material command idempotency — PASS
- real two-session property-lifecycle race: exactly one command consumed the same predecessor state — PASS

### GF-006 / S4 — Revenue & Realized Result

Status: **COMPLETE — VERIFIED FOR INTEGRATION**.

Delivered:

1. Whole-property-only disposition with one database-unique disposition per property, exact proceeds/currency, buyer Party, agreement and evidence references, dates, audit, and payload-bound idempotency.
2. Explicit `DRAFT → APPROVED → CONTROL_TRANSFERRED` disposition lifecycle. Agreement, control transfer, recognition, receivable, and collection remain separate facts; no `PAID = SOLD` state exists.
3. Minimal S3 property lifecycle extension `HELD → EXITING → DISPOSED`. Each transition remains an explicit history command and has no implicit journal effect.
4. One atomic S2 journal batch for sale recognition: Dr Customer Receivable / Cr Real Estate Sale Revenue and Dr Real Estate Cost of Sale / Cr the existing authoritative Development WIP account.
5. Carrying cost derived only from active posted S2 `COST_OBLIGATION` WIP lines classified to the property through S3 dimensions and `CAPITALIZABLE_WIP` policy. Budget, commitment, payment, acquisition consideration, and management valuation are excluded; missing authoritative carrying cost fails recognition.
6. Immutable carrying-cost provenance from the recognized amount to S3 property classification, S2 obligation, journal batch, and journal line.
7. Independent partial/multiple collection posting through existing S2 project cash accounts: Dr Bank Cash / Cr Customer Receivable, with recognition-row locking and a database ceiling that prevents over-collection.
8. Collection reconciliation to existing positive S2 bank-statement lines, with one cross-payment/collection statement-line allocation boundary safe under concurrency.
9. Posted S2 selling expenses classified to the existing S3 property cost dimension as `SELLING`, kept separate from carrying cost and included in realized result only after posting.
10. Realized-result read models for revenue, carrying cost derecognized, selling costs, realized result, collected cash, outstanding receivable, and latest approved management valuation as a separate labelled measure, plus source/evidence drilldown.
11. Existing active-member prepare / OWNER material-action authorization, default-deny RLS, SELECT-only browser tables, locked-search-path RPC writes, append-only audit facts, and no new roles/workflow engine.
12. Arabic/RTL responsive sections inside the existing Real Estate Operations workspace for Disposition, Sale & Collection, and Realized Result, including empty, loading, error, read-only, permission, and drilldown states.
13. Canonical decision: `docs/decisions/0006_S4_REVENUE_AND_REALIZED_RESULT.md`.

Verified by Greenfield CI on PostgreSQL 16 and the application gate:

- `npm ci`, lint, unit/contract tests (59), production build, and typecheck — PASS
- fresh migration replay S0 → S1 → S2 → S3 → S4 — PASS
- forward upgrade from the exact merged S3 schema with S2/S3 objects preserved — PASS
- two-organization RLS and same-tenant cross-project/property integrity — PASS
- balanced revenue/carrying-cost recognition and balanced partial/multiple collection — PASS
- revenue ≠ cash, valuation ≠ realized result, and draft/unposted facts excluded — PASS
- payload-bound recognition/collection retries and one-effect duplicate handling — PASS
- real two-session recognition race: exactly one sale recognition and one batch — PASS
- real two-session collection race: exactly one 70% collection and no ceiling breach — PASS
- sold property cannot receive a second disposition or recognition — PASS
- S1/S2/S3 SQL and concurrency regressions remain green — PASS
- SonarCloud Quality Gate — PASS

## Explicitly deferred

- agreement amendment/supersession and funding carry-forward rules;
- capital-call cancellation accounting beyond the minimal state representation;
- generic approvals/role framework beyond the S2 OWNER/MEMBER maker–checker boundary;
- accounts payable suite beyond this obligation/payment slice; customer invoices and revenue; VAT/tax;
- statutory/general ledger, chart-of-accounts editor, external accounting adapters, bank APIs/open banking;
- fuzzy, split, or many-to-many reconciliation; multi-currency/FX;
- period close/reopen, allocation and distributions;
- private file storage/versioned documents and a generic document-management platform; metadata-only S3 evidence references remain implemented;
- notifications, outbox/queues, integrations, and country tax/e-invoicing;
- partial-property disposition and S5 proceeds/cost allocation; investor allocations/distributions and payouts;
- S6 sale/collection correction, reversal orchestration, and period close/reopen;
- leasing/property management and full construction ERP/procurement/BOQ/contractor/change-order scope;
- PWA/offline sync;
- Agriculture and Livestock runtime modules;
- generic repositories, CQRS/event-sourcing frameworks, plugin/rules engines, package workspaces, and speculative shared layers.

## Next active batch

`GF-007 / S5 — Allocation & Distribution` (per the delivery roadmap) or the next material vertical slice chosen by Mohamed. GF-006 closed the whole-property disposition-to-realized-result path; S5 may allocate realized results under approved terms without treating allocation as cash distribution or reopening S4 sale accounting.

### GF-007-prep / S6 — Period Close and Controlled Correction (delivered between S4 and S5)

Status: **COMPLETE — verified locally through Vitest + PGlite and the
Greenfield CI gates (app + database)**. The delivery order on the
slice is `S0 → S1 → S2 → S3 → S4 → S6 → S5` so that the allocation
slice can consume authoritative, content-hashed close snapshots rather
than re-deriving the S1–S4 state at allocation time. S6 remains a
forward-only extension of the merged S0–S4 foundation: it does not
introduce an accounting ledger, a generic workflow engine, a chart-of-
accounts editor, an allocation engine, a tax/FX engine, an Agriculture
or Livestock module, microservices, CQRS, or event sourcing.

Delivered and verified:

1. Forward-only S6 migrations `20260811000600_s6_period_close_and_
   correction.sql` and `20260811000610_s6_close_read_models.sql` —
   no prior migration is edited.
2. Accounting periods with versioned, immutable closed rows and a
   non-overlap guard. A partial unique index on `status = 'OPEN'`
   enforces at most one open period per `(organization, project,
   currency)`. Reopen creates a new authoritative row with
   `version + 1` and a back-pointer to the superseded period.
3. Database-enforced period lock on every `journal_batches` and
   `journal_lines` insert through `s6_validate_posting_in_open_period`
   and `s6_validate_line_in_open_period`. Closed-period postings
   fail at the database even via direct DML.
4. Versioned `close_runs` (per-period version, partial unique
   index on `status = 'PREPARED'` for race safety), `close_run_gates`
   (ten gates — nine concrete + composite `CLOSE_REPORT_AND_EXCEPTIONS`),
   `close_run_exceptions` (request → approve flow), and
   `close_run_snapshots` (append-only, content-hashed).
5. Server-authoritative RPCs: `s6_create_accounting_period`,
   `s6_evaluate_gate`, `s6_prepare_close_run`, `s6_request_close_run_
   exception`, `s6_approve_close_run_exception`, `s6_approve_close_run`
   (three-argument authoritative command — the project is derived
   from the close run row inside PostgreSQL), `s6_reopen_period`,
   `s6_request_correction`, `s6_approve_correction`,
   `s6_reject_correction`, `s6_execute_correction`. All S6 commands
   are OWNER-gated through `s2_require_owner` and active-member
   checked. Same-user prepare+approve is allowed but actor and time
   are recorded in `audit_events`.
6. S4 correction integration: `s4_guard_deferred_reversal` widened
   to allow a reversal under an APPROVED correction request;
   `s4_guard_recognition_status_transition` and
   `s4_guard_collection_status_or_link` permit the controlled
   `ACTIVE → REVERSED` status transition with provenance. The hard
   `CONTROL_TRANSFERRED → WIP reversal` path still requires reopen.
7. Six `security_invoker=on` read views: `accounting_periods_read`,
   `close_runs_read`, `close_run_gates_read`, `close_run_exceptions_
   read`, `close_run_snapshots_read`, `correction_requests_read`.
   Money is transported as text.
8. Arabic/RTL close workspace at `/projects/[projectId]/close` with
   server actions for prepare, approve, request/approve exception,
   reopen, request/approve/execute correction.
9. SQL behavioural tests: `16_s6_period_close.sql`,
   `17_s6_close_concurrency.sh`, `18_s6_forward_upgrade.sh`. The
   concurrency test covers two-session close race, two-session
   approve race, and posting-into-closed-period race. The forward-
   upgrade test replays S0–S4 on a separate database, then applies
   the S6 family and asserts every S0–S4 and S6 primitive is present.
10. Vitest schema tests: `tests/s6-period-close.test.ts` (15 tests
    covering each Zod schema, the new projectId requirement on the
    approve-related schemas, and the surface contract with the
    PostgreSQL functions).

ADR: `docs/decisions/0007_S6_PERIOD_CLOSE_AND_CORRECTION.md`.

The S5 allocation slice remains the next material batch. S6 freezes
the S1–S4 state into a content-hashed snapshot so S5 can read the
authoritative closed-period totals without re-deriving them.

## Decision rules

- One canonical implementation per concept.
- Search and extend before creating.
- A shared abstraction requires two real consumers.
- Every batch finishes one user workflow across all affected layers.
- Resolve architecture only when the active slice requires it.
- Money and ownership semantics must be exact, server-authoritative, tenant-safe, and auditable.
- Start every implementation branch from the exact latest `origin/greenfield/foundation`; before delivery it must be zero commits behind that target and show no unrelated legacy churn.
- No production deployment or production data changes without explicit authorization.
