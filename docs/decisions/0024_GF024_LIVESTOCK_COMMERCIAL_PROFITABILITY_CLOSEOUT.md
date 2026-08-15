# ADR 0024 — GF-024 Livestock Commercial, Profitability & Closeout

- **Status:** Accepted
- **Date:** 2026-08-15
- **Scope:** GF-024 only (Livestock commercial cycle + technical closeout)
- **Depends on:** ADR 0004 (S2), ADR 0006 (S4), ADR 0007 (S6), ADR 0018/0019
  (Agriculture sale/profitability patterns), ADR 0020–0022 (Livestock
  foundation/movement/quantity/weight/biological events)

## Context

GF-020 through GF-022 established the Livestock operational chain
(`Site → Herd → Cohort`), the append-only movement chain, the exact-integer
quantity ledger with its class registry, and births/mortality/split/merge with
conservation and inception invariants. The commercial side was explicitly
deferred. GF-024 closes the operating cycle from external purchase through
sale, cash collection, profitability and a technical closeout, reusing the
existing Terranex Finance Core (S2 journal/cash/obligations, S4
receivable/collection pattern, S6 period close/correction). GF-023 implements
health/reproduction/animal/feed independently in a parallel session; GF-024
must remain fully independent and must work even if GF-023 never merges.

## Decision

### 1. Physical vs financial truth

Livestock headcount is the GF-021/GF-022 **exact integer, event-derived
quantity ledger**. It has no monetary meaning by itself. Money lives only in
the shared balanced journal (`journal_batches` / `journal_lines`) under locked
semantic roles. GF-024 never stores a monetary balance on any Livestock table
and never invents a value for a physical animal or a remaining live Cohort.

### 2. Quantity classes introduced

Two new classes are registered **forward-only** in the existing
`livestock_quantity_event_types` registry (no ledger rebuild, no rewrite of the
GF-020 opening headcount):

- `PURCHASE_IN` (+1) — externally purchased additions to an already-open
  Cohort. `requires_operation = false`, `requires_cause = false`,
  `requires_disposal = false`.
- `SALE_OUT` (−1) — animals physically leaving through a recognized sale.
  `requires_operation = false`, `requires_cause = false`,
  `requires_disposal = false`.

The rollforward becomes:

```
current = opening + births + purchase_in + split_in + merge_in
                 - mortality - sale_out - split_out - merge_out
```

`opening_headcount` is never rewritten; a Cohort whose opening is
`PURCHASED` keeps its GF-020 opening quantity as-is, and GF-024 only adds
`PURCHASE_IN` for **later additions**.

### 3. Purchase model (SCOPE A)

`livestock_purchases` + immutable `livestock_purchase_lines` record the
bounded commercial intake of externally purchased animals:

- supplier/Party provenance through the canonical `parties` table (no new
  supplier master);
- contract/evidence references;
- exact integer quantity per line against a target Cohort (species coherence
  inherited from the Cohort's Herd through the composite foreign key);
- an effective time (`timestamptz`) that must not precede Cohort inception;
- an **optional agreed commercial amount** per line
  (`agreed_unit_price_minor_units` × quantity, exact bigint) that is a
  commercial snapshot, clearly labelled as such and **never posted**;
- audit and organization-scoped payload-hashed idempotency.

`record_livestock_purchase` atomically writes the header, its lines, one
`PURCHASE_IN` quantity event per line, and the audit event. It does **not**
post a journal, create a payable, or fabricate a carrying value. If Finance
truth exists it is recorded separately through the canonical S2 obligation and
flows to profitability through cost attribution (§6).

### 4. Sale / control-transfer model (SCOPE B)

`livestock_sales` + immutable `livestock_sale_lines` follow the GF-018
bounded lifecycle:

```
DRAFT → APPROVED → CONTROL_TRANSFERRED
```

`SETTLED` is a derived read state when immutable collections equal recognized
revenue — never a stored balance. Draft and approval move no animals and post
no accounting. Approval is an OWNER control.

`recognize_livestock_sale` is one transaction that:

1. locks the Sale and every source Cohort in deterministic id order and
   rechecks the **as-of** derived quantity at the control-transfer instant;
2. appends one `SALE_OUT` quantity event per line (never a direct mutation of
   opening/current quantity);
3. posts the shared Finance Core batch — debit `CUSTOMER_RECEIVABLE`, credit
   `LIVESTOCK_SALE_REVENUE`;
4. records the immutable recognition fact; and
5. advances the Sale to `CONTROL_TRANSFERRED`.

The control-transfer quantity instant is the transfer **date at UTC midnight**,
matching the GF-022 date-only inception boundary. A future-dated or
pre-inception transfer is rejected; a sale can never consume animals supplied
only by a later event. Any quantity, period, journal or integrity failure rolls
back the whole recognition.

### 5. Receivable / collection model (SCOPE C)

Finance Core is reused directly. `LIVESTOCK_SALE_REVENUE` is the only new
semantic account; `CUSTOMER_RECEIVABLE` and `BANK_CASH` are shared. Each
collection locks the recognition row, sums prior immutable collections, rejects
an amount above the outstanding recognized receivable, and posts debit
`BANK_CASH` / credit `CUSTOMER_RECEIVABLE` through Finance Core. Partial and
multiple collections are supported; the outstanding receivable is always
derived. No sector-specific receivable ledger, no mutable receivable balance,
no second payment or reconciliation engine. A generic journal-only reversal of
a livestock recognition/collection is blocked (it would detach the immutable
`SALE_OUT` and commercial truth); correction must travel the S6 controlled
path.

### 6. Profitability definitions (SCOPE D)

The eligible cost source is an **active posted Finance Core journal line**
whose batch source is `COST_OBLIGATION` and whose semantic debit role is
`PROJECT_EXPENSE` — identical to GF-019. `livestock_cohort_cost_attributions`
is an append-only dimension from that source to one Cohort, with a positive
amount, category, policy/evidence, a source-row lock ceiling, and an explicit
append-only offset for correction. It posts nothing.

The Cohort result (`livestock_cohort_results_read`) distinguishes, from
immutable facts:

- recognized Livestock revenue (recognitions only);
- collected cash (collections only);
- outstanding receivable (revenue − collections);
- attributed operating cost (active cost attributions);
- acquisition-related attributed cost (the `ACQUISITION` category subset);
- operating result to date (revenue − attributed operating cost);
- quantities sold (`SALE_OUT`), purchased in (`PURCHASE_IN`), born, dead
  (mortality already from GF-022), split/merge movement, and unsold live
  quantity (derived rollforward).

COGS is **not** computed: there is no canonical biological-asset carrying
value. Unsold live quantity and mortality are reported as quantities only, not
as accounting losses. Mortality is never auto-posted. IAS 41 / fair-value
automation is explicitly deferred. Metrics that would require a guessed value
are labelled `UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY` rather than
fabricated.

### 7. Closeout (SCOPE E)

`close_livestock_cohort` is a **technical closeout**, not a second close
engine and not a lifecycle mutation. It evaluates the sector controls in
`livestock_cohort_integrity_issues_read` (quantity rollforward reconciles, no
negative quantity timeline, split/merge conservation holds, sale quantity has
valid `SALE_OUT` provenance, revenue/control-transfer linkage is coherent,
collection ceiling holds, cost-attribution ceiling holds, postings respect S6
periods) and records immutable close metadata. HARD issues block close; open
receivable, open (draft/approved) sales and a zero-quantity ACTIVE Cohort are
WARN/informational and remain visible after close.

GF-020/GF-022 deliberately keep a zero-quantity Cohort `ACTIVE`. GF-024 does
**not** introduce a `CLOSED`/`SOLD` terminal lifecycle transition: the
canonical lifecycle supports only `PLANNED → ACTIVE`, and forcing a close state
would destroy the historical quantity truth. Financial/technical close stays
separate from operational Cohort lifecycle; S6 remains the authoritative
financial period close.

### 8. Security and concurrency

Every new table carries organization/project scope, composite foreign keys,
enabled and **forced** RLS, an active-member read policy, and no browser DML.
Read views are `security_invoker`. Commands are authenticated `SECURITY
DEFINER` functions with `search_path = pg_catalog,public`, actor derived from
`auth.uid()`, OWNER authorization for material finance/close actions, and
PUBLIC/anon denial. The per-Cohort advisory lock plus the deferred non-negative
and conservation backstops already in GF-022 cover purchase/sale quantity
races; the recognition row lock serializes collections. Direct privileged
writes are blocked by the same database-enforced invariants.

### 9. Independence from GF-023

GF-024 owns only the commercial + financial closeout cycle. It does not touch
health/treatment, vaccination, medicine/withdrawal, reproduction/pregnancy/
breeding, optional Animal/RFID identity, feed issue, feed inventory, or FCR.
It depends only on merged `main` at the exact GF-022 boundary, GF-020/021/022,
and the shared Finance Core. It works even if GF-023 never merges.

## Consequences

### Positive

- Physical and financial facts cannot diverge during recognition.
- Finance Core, S6 periods, cash accounts, receivable and audit are reused.
- Purchase additions and sale issues are exact integers with full provenance.
- Profitability is reproducible from immutable facts and honestly labels
  unavailable metrics instead of guessing.

### Trade-offs

- No sale return/credit note/invoice engine, no draft amendment, no biological
  asset valuation, no COGS, no IAS 41 posting.
- A generic journal-only reversal of a livestock sale is blocked pending the
  controlled S6 correction path (which GF-024 integrates but does not
  reimplement).
- Global Livestock navigation wiring is deferred to the post-parallel
  integration step shared with GF-023.

## Rejected alternatives

1. **A second Livestock accounting ledger / receivable / payment / close
   engine.** Rejected — Finance Core is authoritative.
2. **Store mutable balances** (`current_headcount`, `outstanding_receivable`,
   `profit`). Rejected — append-only facts derive everything.
3. **Rewrite opening headcount for purchased Cohorts.** Rejected — opening is
   immutable GF-020 provenance.
4. **Guess COGS or biological carrying value.** Rejected — no canonical policy
   exists.
5. **Auto-post mortality or IAS 41 fair value.** Rejected — deferred.
6. **Force a `CLOSED`/`SOLD` lifecycle state at zero quantity.** Rejected —
   would destroy historical truth and contradicts GF-020/GF-022 doctrine.
