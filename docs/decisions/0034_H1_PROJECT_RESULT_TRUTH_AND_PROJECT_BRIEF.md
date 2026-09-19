# ADR 0034 — H1: Project Result Truth and the Project Brief

**Status:** ACCEPTED
**Effective:** 2026-09-04
**Authorizes:** the H1 tranche defined below
**Supersedes:** nothing. Extends ADR 0032 (R8 read projection) and ADR 0033 (pre-owner policy safety).
**Canonical references:** `docs/ROADMAP_R0_R17.md`, `docs/OPEN_BUSINESS_DECISIONS.md`, `AGENTS.md`

---

## 1. Architectural principle (recorded for the whole product)

> **A shared management projection may normalize the shape of an answer, but never erase the
> sector-specific basis, incompleteness, or policy boundary that produced it.**

This is the governing rule for every cross-sector read model built from this ADR onward. It is the
reason R8 (`cross_sector_asset_register_read`) is a projection and not a table, and it is the reason
the management result defined below is an object rather than a number.

Corollary: **if a fact can be stripped of its qualification by a careless consumer, the
qualification is not part of the contract — it is only a comment.** Contracts must be structurally
enforced, not documented.

---

## 2. Decision 1 — A qualified management operating result is authorized

TERRANEX may state a **management-basis project operating result**, subject to a strict contract.

### 2.1 The contract

A surfaced result is **inseparable** from:

```
amount + currency + basis + cost_classification_status + evidence_status
+ policy_availability + as_of
```

Therefore:

- **No shared read model intended for management UI exposes a bare result scalar.** There is no
  column named `operating_result_minor_units` anywhere a UI can select it. The result is delivered
  as a single `jsonb` object so that selecting it necessarily selects its qualification.
- Component columns (revenue by source, attributed cost, overhead, unclassified) **are** exposed, so
  any consumer may recompute the arithmetic. What is not exposed is the *headline* stripped of its
  basis.
- Enforced by: view shape (no scalar column), a single sanctioned React renderer, and a permanent
  characterization test.

### 2.2 Reserved terminology

The following are **reserved for future policy-defined concepts** and must not be used for this
measure in any migration, view, column, label, or UI string:

`profit` · `ربح` · `return` · `عائد` · `investor return` · `realized investment return` ·
`IRR` · `MOIC` · `TVPI` · `equity multiple` · `cash-on-cash` · `distributable cash`

Authorized term: **`MANAGEMENT_OPERATING_RESULT` / نتيجة التشغيل الإدارية**.

Rationale for the reservation: every multiple metric requires *cash returned to investors* over
*equity contributed*, which depends on BD-002, BD-005 and BD-008. Computing any of them before those
decisions are recorded would fabricate company policy. This is a hard, permanent block — not a
deferral.

`النتيجة المحققة` (realized result) remains valid **only** as the Real-Estate-specific result of a
recognized disposal, because that is a realized operating fact owned by the sector. It is not a
cross-sector comparative measure and must never be presented as one.

---

## 3. Decision 2 — The cost-classification remainder (amends the original H1 proposal)

### 3.1 The error being corrected

The original proposal defined `unattributed = expense_posted − attributed` and interpreted the whole
remainder as incomplete coverage. That is wrong: a project with genuine farm/site-level overhead
would permanently report PARTIAL even when perfectly classified.

### 3.2 There is no existing attributability axis

Verified by inspection of the current schema:

| Existing column | What it actually is | Why it is not attributability |
|---|---|---|
| `cost_obligations.cost_treatment` | `EXPENSE` \| `CAPITALIZABLE_WIP` | Accounting treatment. Says nothing about whether a cost belongs to an operating unit. |
| `crop_cycle_cost_attributions.cost_category`<br>`livestock_cohort_cost_attributions.cost_category`<br>`property_cost_items.cost_category` | Destination category | Recorded **only when attribution has already happened**. Its absence is exactly the unknown we are trying to measure. |

Therefore new authoritative facts are required. The minimum necessary is defined below.

### 3.3 The four states

Every posted project expense line falls into exactly one state:

| State | Meaning | Who asserts it |
|---|---|---|
| `ATTRIBUTED_TO_OPERATING_UNIT` | Attributed to a crop cycle, livestock cohort, or property asset | Existing sector attribution rows — no new fact needed |
| `PROJECT_OVERHEAD` | Intentionally unallocated; belongs at project/farm/site level | **Operator assertion** (new) |
| `EXCLUDED_FROM_MANAGEMENT_RESULT` | Operator declares this cost out of the management result | **Operator assertion** (new) |
| `UNCLASSIFIED` | Eligible, not yet classified | Residual — never a default, never inferred |

Plus one disclosure bucket:

| Bucket | Meaning |
|---|---|
| `EXPENSE_OUTSIDE_CLASSIFICATION_SCOPE` | Expense with no `cost_obligation_id` (e.g. opening import). Reported separately with its amount; **never** silently folded into `UNCLASSIFIED`, so it can never masquerade as "you forgot to attribute supplier invoices". |

### 3.4 Default is `UNCLASSIFIED`, never `PROJECT_OVERHEAD`

If `PROJECT_OVERHEAD` were the default, the product would launder incompleteness into "overhead"
by omission — the exact failure this ADR exists to prevent. Overhead must be **stated**, and it is
stated with a mandatory `reason` (3–500 chars), mirroring `property_cost_items.policy_reference`.

### 3.5 Scope

Classification applies to obligations with `cost_treatment = 'EXPENSE'` that are `AUTHORIZED` and
whose authorization batch is neither a reversal nor reversed. `CAPITALIZABLE_WIP` obligations post
to `DEVELOPMENT_WIP`, not `PROJECT_EXPENSE`; they reach the result through COGS derecognition at
disposal, so including them in expense classification would double count.

### 3.6 Result arithmetic (basis-dependent)

```
AGRICULTURE / LIVESTOCK   basis = *_ENTERPRISE_OPERATING
    + sale revenue recognized
    − cost attributed to crop cycles / cohorts
    − declared project overhead
    = management operating result

REAL ESTATE               basis = REAL_ESTATE_DISPOSAL_AND_RENTAL
    + realized disposal result        (sector-owned: revenue − COGS derecognized − selling costs)
    + rental revenue recognized
    − property operating expense attributed, EXCLUDING category 'SELLING'
    − declared project overhead
    = management operating result
```

The `SELLING` exclusion is required because `property_realized_result_read.selling_costs` already
nets selling costs inside the realized disposal result. This is the one place where the sector's own
result is not a simple sum, and it is gated.

`EXCLUDED_FROM_MANAGEMENT_RESULT` cost is subtracted from nothing and disclosed with its amount.

---

## 4. Decision 3 — Three independent credibility dimensions, never one score

A single confidence percentage would destroy information. Three dimensions are reported separately:

| # | Dimension | Question | Values |
|---|---|---|---|
| 1 | `cost_classification_status` | Have relevant costs been classified? | `COMPLETE` · `PARTIAL` · `NONE` · `NOT_APPLICABLE_NO_OPERATING_COST` — always accompanied by `unclassified_eligible_minor_units` |
| 2 | `evidence_status` | Do underlying facts carry evidence? | `COMPLETE` · `PARTIAL` · `INCOMPLETE` · `NOT_APPLICABLE_NO_EVIDENCE_CONTRACT` — reported as `evidenced_count / subject_count`, never as a bare percentage |
| 3 | `policy_availability` | Which concepts are deliberately unavailable? | Text list, e.g. `COGS_NOT_RECOGNIZED`, `INVENTORY_VALUE_NOT_RECOGNIZED`, `BIOLOGICAL_ASSET_VALUE_NOT_RECOGNIZED`, `RETURN_MULTIPLES_UNAVAILABLE_PENDING_POLICY` |

A project may be `COMPLETE` on cost and weak on evidence, or fully evidenced while COGS remains
deliberately unavailable. Neither may cancel the other out.

**H1 scope for dimension 2:** money facts carrying an optional evidence reference, plus the
sector operational facts that already expose one. The scope is stated in the UI text, not implied.
Facts whose evidence reference is **mandatory** are excluded by design: they always score 100%
and would dilute the measure into a number that looks reassuring and means nothing.

### 4.1 `INVESTOR_ENTITLEMENT_NOT_ACTIVATED` is scoped per organization, never globally

`policy_availability` includes `INVESTOR_ENTITLEMENT_NOT_ACTIVATED` while the organization has
no approved `policy_authority` row for scope `INVESTOR_ECONOMICS`.

This flag **must** be evaluated per organization **and** per scope, mirroring ADR 0033's
`require_policy_activated(p_organization_id, p_scope)`. An earlier implementation tested only
whether the `policy_authority` table contained *any* row anywhere in the database. That was a
defect found by running the gate suite in sequence: one organization activating investor
economics would silently change what every other organization's result claimed about its own
investor entitlement. A tenant must never be able to alter another tenant's disclosure.

---

## 5. Decision 4 — Budgets: F4 is the control, S3 is the plan

Two independent authoritative budget ceilings are a control hazard. Therefore:

- **`project_budgets` / `project_budget_lines` (F4)** is the **only financial authorization control**:
  ceiling enforcement at obligation authorization, FAC, consumption, roll-up, integrity signals.
- **`property_budget_versions` / `property_budget_lines` (S3)** is retained in full — versioning,
  approval workflow, asset/parcel/phase/category granularity — and **renamed** to
  **Property Cost Plan / خطة تكلفة العقار**. It is a planning artefact, not an authorization control.

Nothing is merged or destroyed. S3's asset-level planning granularity has value F4 does not have.
This is a naming and boundary correction, not a schema change.

---

## 6. Product direction A — Project Brief consolidation (approved)

- `/projects/[projectId]` becomes the canonical project surface for **all three sectors**.
- `/projects/[projectId]/overview` redirects for backward compatibility and disappears as a product
  concept.
- Sector pages are **operational workspaces**, not demoted leftovers. The navigation architecture
  communicates:

  `Project Brief → Operations → Finance / Controls / Evidence`

- **The Project Brief owns synthesis. Sector workspaces own operational truth and commands.**
- Hard cap: seven panels. A panel that cannot state the question it answers does not ship.

Panels: Capital · Result (qualified) · Position · Operations now · Attention · What changed ·
Governance.

---

## 7. Product direction B — Home cross-sector result corrected immediately

The existing `النتيجة المحققة` column on the Executive Home is semantically invalid as a cross-sector
comparative measure: for Real Estate it is net of COGS, for Agriculture and Livestock it is gross
revenue. A footnote does not repair that.

- The legacy field is preserved at the read-model level for gate compatibility. It is **not**
  displayed with equal prominence — displaying both numbers would replace one confusing comparison
  with two.
- The management UI shows the qualified management-basis result.
- If `cost_classification_status = NONE`, the derived result is **suppressed** and the
  revenue/cost decomposition is shown instead.
- If `PARTIAL`, the amount is shown with a status that is impossible to miss, plus the unclassified
  amount inline.
- Historical investor/demo communication is a migration and communications matter, not a reason to
  retain an invalid metric.

---

## 8. Explicitly excluded from H1

| Excluded | Reason |
|---|---|
| `capital_deployed` KPI | Genuinely ambiguous: cumulative capital spent / current invested capital / gross cash deployed / net capital at work / contributed less returned. These diverge the moment a project earns revenue, collects receivables, refinances, or pays distributions. **Requires its own ADR before it may become a KPI.** H1 shows: contributions received, cash by currency, revenue recognized, posted operating cost, open commitments, receivables, payables. |
| Bulk cost-attribution RPC | The correctness problem is missing classification semantics, not ergonomics. Deferred to H2 unless the brief proves operators face volume that requires it. |
| Organization-wide ranked attention | Belongs to H2. The **project** attention panel is in H1; a universal prioritization model must not be designed prematurely. |
| Cash in / out movement summary | Exact and useful, but a new read model. First candidate for H2. |

---

## 9. Authorized H1 scope

1. `project_operating_result_read` with explicitly qualified sector-specific basis.
2. Explicit classification and reconciliation of attributed cost, declared overhead, declared
   excluded, and unresolved eligible cost.
3. `UNCLASSIFIED_OPERATING_COST` and result-verification integrity signals.
4. Correct cash-by-currency presentation (no cross-currency summing at project level).
5. Canonical Project Brief.
6. Existing project risks, decisions, integrity exceptions and recent material facts wired into the
   brief.
7. Home cross-sector result corrected to the qualified contract.
8. `/overview` retired.
9. Missing-value-as-zero defect removed.
10. Typed synthetic/demo marker (replacing `internal_reference LIKE 'DEMO%'`).

---

## 10. Invariants this ADR adds

- `attributed + overhead + excluded + unclassified + outside_scope = expense_posted` — exact, per
  project and currency, gated.
- No read model exposes a bare management-result scalar.
- No UI renders a result amount without its basis and its cost-classification status.
- No currency is summed across currencies at project level.
- `PARTIAL`/`NONE` never suppress the unclassified amount; they display it.
- Reserved terminology (§2.2) appears in no migration, view, column, or UI string.

---

## 11. Horizon sequence after H1

`H1 Project truth → H2 Portfolio/Attention → H3 Sector economics → H4 Publishable evidence →
policy-dependent investor economics (blocked on BD-001…BD-012) → intelligence`
