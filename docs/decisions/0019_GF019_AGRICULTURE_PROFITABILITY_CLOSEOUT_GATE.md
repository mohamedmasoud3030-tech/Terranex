# ADR 0019 — Agriculture Profitability, CropCycle Closeout & Technical Gate

- **Status:** Accepted
- **Date:** 2026-08-14
- **Scope:** GF-019, the final Agriculture implementation phase
- **Depends on:** ADR 0013–0018, S2 Finance Core, S5 allocation/distribution, S6 period close/correction

## Context

GF-013 through GF-018 established the Agriculture chain from land control,
Farm, Field and CropCycle through activity, input traceability, harvest physical
inventory, buyer dispatch, control-transfer revenue, receivable and collection.
The final phase must make the CropCycle result reproducible and operationally
closeable without inventing a seasonal ledger, harvest valuation, editable
profit, input stock, or investor/distribution subsystem.

## Decision

### 1. Finance Core is authoritative; Agriculture stores only attribution

The eligible cost source is an **active posted Finance Core journal line** whose
batch source is `COST_OBLIGATION` and semantic debit role is
`PROJECT_EXPENSE`. A Payment is settlement and is never treated as the cost
source. `CAPITALIZABLE_WIP`, draft obligations, reversed postings and unrelated
journal lines are ineligible.

`crop_cycle_cost_attributions` is an append-only dimension from that source to
one CropCycle and optionally one Field already assigned to it. It records a
positive amount, policy/evidence and source ID, but posts no debit or credit and
holds no independently editable expense. A source-row lock serializes the sum
of active attributions, which cannot exceed the posted debit. Stable
organization-scoped payload idempotency returns the original result on replay.
Correction is an explicit append-only offset fact; an attributed Finance source
cannot be reversed until its active attributions are offset. The monetary
correction then continues through the existing S6/S2 linked reversal path.

There is no Agriculture expense ledger or journal.

### 2. Land investment remains outside the seasonal result

Agricultural Land Asset consideration is investment/control truth, distinct
from CropCycle operating cost. A `PROJECT_EXPENSE` line linked as the
consideration obligation of purchased land is explicitly ineligible for cycle
attribution under the current policy. Purchased, leased, contributed-in-kind
and managed-for-owner positions remain visible separately in the result.

GF-019 adds no land depreciation, amortization, fair value, tax basis, carrying
amount or lease accounting. A future professionally approved accounting policy
would require a new forward decision; GF-019 does not guess one.

### 3. Revenue, collection and receivable stay separate

Recognized revenue comes only from GF-018 control-transfer recognitions and
immutable Sale Lines. Draft and approved-but-undelivered sales contribute no
revenue. Collection remains cash against the receivable and never creates
revenue. Outstanding receivable is recognized revenue less immutable
collections.

For the supported but uncommon sale containing Harvest Lots from more than one
CropCycle, the read model allocates the sale-level collection proportionally to
recognized line value using deterministic largest-remainder minor-unit
rounding. It is a reproducible read projection, not a new cash fact; it exactly
reconciles to the sale collection total.

### 4. Remaining harvest inventory is physical, not valued

The result derives gross harvest, net accepted quantity, harvest loss,
spoilage, Sale Issue quantity and remaining lot quantity from immutable harvest
and movement facts. Remaining inventory can survive close. Because no approved
harvest measurement/cost policy exists, its value is explicitly
`UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY`. GF-019 does not infer value from
the latest sale, estimate COGS, claim an unrealized gain, or treat physical
inventory as realized profit.

### 5. CropCycle result is a reproducible read model

`crop_cycle_results_read` derives CropCycle identity, Farm/Field/area, activity
and input counts, quantity rollforward, recognized revenue, cash, receivable,
authoritative attributed operating cost, operating result to date, per-area
measures, realized average sale price, evidence completeness, land position and
open exceptions. Values are recomputed from canonical facts. There is no
stored or editable `profit` or mutable summary balance.

Mixed area or harvest units are not converted. Metrics that require a common
unit are unavailable rather than guessed. Per-area and average-money displays
use explicit nearest-minor-unit rounding while the underlying totals remain
exact integers.

### 6. Closeout reuses the canonical lifecycle

`close_crop_cycle` validates then invokes the existing
`transition_crop_cycle` transition `HARVESTING → CLOSED`; it does not create a
second state machine. It records immutable close metadata — actor from
`auth.uid()`, timestamp, reason, evidence and closing history ID — and relies on
the single canonical lifecycle audit event rather than duplicating success
audits.

Hard blockers include missing assignment/harvest, a broken lifecycle chain,
negative or incoherent inventory, Sale Line / `SALE_ISSUE` mismatch, revenue or
collection mismatch and a broken cost ceiling. A harvest-ready cycle with no
Harvest Event cannot be described as a successfully closed crop; a genuine
no-output outcome belongs on the existing `GROWING → FAILED` path before a
successful-harvest assertion.

Close **does not** require zero inventory or a settled receivable. Those are
warning/open commercial positions, remain visible after close and continue to
change from later canonical sales/collections. Close means seasonal operating
activity is concluded and its result basis is reproducible.

### 7. Shared S6 period and correction controls remain authoritative

GF-018 revenue and collection batches and the S2 expense source pass through
the existing `journal_batches` / `journal_lines` open-period guards. Cost
attribution is non-monetary and cannot bypass those guards because it can only
reference a posted source. No Agriculture period, reopen command or correction
calendar exists. Unsupported sale-return/credit-note correction remains
blocked rather than reversing only the journal side of an immutable physical
sale.

### 8. S5 compatibility, not duplication

Agriculture revenue and expense already live in the shared balanced project
journal and therefore remain visible to S6 close snapshots and shared project
result. CropCycle close creates no allocation run, partner capital movement,
distribution payable or distribution payment. S5 remains the sole owner of
investor allocation/distribution, and no funds are auto-distributed at close.

### 9. Input stock decision: Option A — keep deferred

Input Item and Input Lot continue to provide application traceability only.
InputApplication validates item/lot/activity/date/unit/expiry/area coherence but
does **not** claim stock-availability validation. The canonical v1 has no input
purchase, receipt or opening-stock fact; inventing a balance would create false
control. Procurement, receiving, input-stock movement, valuation, supplier ERP,
WMS and purchase orders remain deferred farm-ERP scope.

Agronomy Observation, weather, GIS, satellite, IoT and AI remain outside the
investment operating flow and are not added.

### 10. Security and concurrency

Both GF-019 tenant tables carry organization and project scope, composite
foreign keys, enabled and forced RLS, active-member read policy and no browser
DML. Read views are `security_invoker`. Commands are authenticated
`SECURITY DEFINER` functions with `search_path=pg_catalog,public`, actor derived
from Auth, OWNER authorization for material finance dimension/close actions,
and PUBLIC/anon denial.

The source journal line lock makes competing cost allocations a real serialized
ceiling. Canonical tests retain the GF-016 harvest and GF-018 sale/collection
two-session races and add a GF-019 two-session cost attribution race.

## Agriculture technical gate

Agriculture may be marked technically implemented only when the final merged
head proves:

1. tenant/project isolation, forced RLS, RPC grants and direct-DML denial;
2. stable idempotency, append-only facts and source-ceiling concurrency;
3. CropCycle lifecycle, assignment, activity/input and harvest rollforward;
4. sale oversell, revenue recognition and collection ceiling;
5. authoritative cost attribution and land-cost exclusion;
6. reproducible result with truthful revenue/cash/inventory distinctions;
7. safe close with open inventory/receivable allowed and hard integrity blocked;
8. shared S6 period controls and S5 compatibility without auto-distribution;
9. exact forward upgrade from the merged GF-018 boundary;
10. Arabic/RTL, mobile/accessibility contracts and all application/database/CI
    quality gates green.

Synthetic fixtures prove technical behavior only. They are not Agriculture
customer UAT, a paid pilot, commercial validation or production evidence.

## Consequences

Agriculture is the second technically implemented sector after the gate passes.
**Livestock becomes the next authorized sector only after GF-019 is merged and
the evidence supports PASS.** This ADR creates no Livestock schema, UI or
runtime behavior.
