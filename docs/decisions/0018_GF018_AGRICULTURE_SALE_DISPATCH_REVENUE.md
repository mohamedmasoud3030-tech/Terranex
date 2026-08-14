# ADR 0018: GF-018 Agriculture Sale, Dispatch & Revenue

- Status: Accepted
- Date: 2026-08-14
- Owners: Product, Architecture, Finance Controls, Agriculture Operations
- Scope: GF-018 only
- Depends on: ADR 0013–0017, S2 Finance Core, S4 revenue/receivable pattern, S6 period controls

## Context

GF-016 established append-only physical truth for harvested output, but intentionally stopped before sale. GF-017 added the durable Agricultural Land Asset without changing that inventory boundary. Agriculture now needs a bounded commercial flow from a buyer agreement to physical dispatch, control-transfer revenue recognition, receivable, and one or more cash collections.

The implementation must not create an Agriculture ledger beside Finance Core, infer revenue from cash, reserve stock merely by saving a draft, or invent harvest valuation/COGS before authoritative CropCycle cost attribution exists. A concurrent sale must not oversell one lot/location, and concurrent collections must not exceed the recognized receivable.

## Decision

### 1. Use sector-specific sale facts and the shared journal

Add `agriculture_sales`, immutable `agriculture_sale_lines`, one immutable `agriculture_sale_recognitions` fact per sale, and append-only `agriculture_sale_collections`.

The sale lifecycle is bounded:

`DRAFT → APPROVED → CONTROL_TRANSFERRED`

`SETTLED` is a derived read state when immutable collections equal recognized revenue. It is not a stored mutable status or balance.

Saving or approving a sale does not move inventory and does not post accounting. Approval is an explicit owner control, not recognition.

### 2. Derive sale units from Harvest Lot truth

Each line names a Harvest Lot, one source Storage Location, a positive quantity, and a positive price in minor units. The database derives and persists the line unit from the selected Harvest Lot. Browser input cannot assert or convert the unit.

GF-018 does not add unit conversion, reservations, order fulfilment, invoicing, warehouse ERP, processing, or purchasing.

### 3. Make control transfer one atomic physical and financial transaction

`recognize_agriculture_sale` locks the Sale and every source Harvest Lot in deterministic order, then rechecks each source-location balance. In one transaction it:

1. appends one `SALE_ISSUE` movement for every Sale Line;
2. posts a shared Finance Core batch that debits `CUSTOMER_RECEIVABLE` and credits `AGRICULTURE_SALE_REVENUE`;
3. records the immutable recognition fact; and
4. advances the Sale to `CONTROL_TRANSFERRED` with date, evidence, actor, and audit lineage.

Any inventory, period, journal, or integrity failure rolls back all four effects. A draft does not reserve stock. This is why two approved sales may compete, and why recognition—not drafting—owns the stock lock.

The S6 journal-batch and journal-line period guards remain authoritative. GF-018 does not create a second close calendar.

### 4. Do not guess inventory value or COGS

The recognition batch contains revenue and receivable only. No COGS, harvest inventory value, gross margin, profit, carrying value, or land cost is estimated or posted.

This is an intentional accounting boundary, not an assumption that harvested output has zero cost. GF-019 must first establish authoritative posted-cost attribution to CropCycle and reproducible profitability before cost-based Agriculture result is presented.

Agricultural Land Asset consideration/value remains separate from CropCycle operating result.

### 5. Derive receivable settlement from append-only collections

Each collection:

- locks the recognition row;
- sums prior immutable collections;
- rejects an amount above the outstanding recognized receivable;
- posts through Finance Core as debit `BANK_CASH` / credit `CUSTOMER_RECEIVABLE`; and
- records evidence, cash account, actor, source journal, idempotency, and audit lineage.

Partial and multiple collections are supported. The outstanding receivable is always derived as recognized revenue less collections. Cash is not re-labelled as revenue.

### 6. Preserve traceability and tenant controls

Read models provide:

- Sale totals, lifecycle, recognized revenue, collected cash, and outstanding receivable;
- line-level Harvest Lot and source Storage lineage;
- collection history; and
- one-step forward traceability from Harvest Lot to Sale, buyer, dispatch movement, control transfer, and revenue batch.

Every new tenant table has enabled and forced RLS. Authenticated users receive read-only table/view access; writes are through security-definer commands. Composite foreign keys enforce organization/project/lot/storage coherence. Material line, recognition, collection, harvest movement, and journal facts are immutable.

### 7. Keep correction policy honest

A generic journal-only reversal of an Agriculture recognition or collection would detach Finance Core from immutable physical dispatch and commercial truth. GF-018 therefore blocks that unsafe reversal. GF-019 must integrate a controlled correction/closeout policy with S6; it may not silently reverse only one side of the physical-financial chain.

## Concurrency and idempotency

- Commands derive the actor from `auth.uid()`.
- Idempotency keys are organization-scoped and payload-hashed.
- Replay is checked before mutable-state validations so a successful recognition remains replayable after stock and collection state changes.
- Sale references are serialized and unique per project.
- Deterministically locked Harvest Lots prevent concurrent oversell.
- A locked recognition row serializes collections and protects the ceiling.
- Database tests use real independent PostgreSQL sessions for both races; mocked or sequential tests are insufficient.

## Forward-upgrade requirement

The forward-upgrade gate constructs a genuine database at the merged GF-017 boundary, replays all cumulative SQL fixtures available there, fingerprints existing Real Estate, Agriculture, land, harvest, Finance Core, journal, and cash rows, applies GF-018, and proves those rows are unchanged. It then exercises the new draft, approval, current-date dispatch/revenue, and collection commands.

Applied migrations remain immutable. Any later repair requires a new migration.

## Arabic/RTL operator contract

The primary workspace section is **المبيعات والتحصيل**. It must state clearly:

- a draft does not issue stock or recognize revenue;
- delivery/control transfer atomically issues stock and recognizes revenue/receivable;
- collected cash is distinct from revenue;
- outstanding receivable is derived;
- line units come from Harvest Lot truth; and
- COGS/inventory value is not guessed.

The forms support multiple lines, evidence capture, partial collections, practical narrow-screen behavior, keyboard-labelled controls, and Arabic lifecycle wording. Raw UUIDs and raw database errors are not operator language.

## Consequences

### Positive

- Physical and financial facts cannot diverge during recognition.
- Existing Finance Core, period controls, audit, cash accounts, and receivable account are reused.
- Lot-to-buyer traceability is direct and reproducible.
- Drafting does not fabricate inventory reservations or accounting.
- Settlement cannot exceed the recognized receivable under concurrency.

### Trade-offs

- There is no draft amendment/cancellation, return, credit note, invoice engine, reservation, conversion, or generic reversal in GF-018.
- Gross margin and Agriculture profit remain unavailable until GF-019 establishes cost attribution.
- Bank-statement reconciliation remains the shared Finance capability boundary and is not duplicated inside Agriculture.

## Rejected alternatives

1. **Create an Agriculture subledger.** Rejected because Finance Core is authoritative.
2. **Recognize revenue at draft/approval or on collection.** Rejected because neither proves control transfer.
3. **Reserve or decrement stock at draft.** Rejected because a commercial draft is not physical dispatch.
4. **Estimate COGS from price, quantity, input applications, or land value.** Rejected because no authoritative cost attribution policy exists yet.
5. **Store outstanding receivable or settlement as mutable balances.** Rejected because immutable collection facts provide reproducible derivation.
6. **Allow journal-only reversals.** Rejected because they would break physical/commercial/accounting coherence.
7. **Build a generic order, warehouse, or asset engine.** Rejected as out of scope.

## Next bounded decision

ADR 0019 must decide and document Agriculture posted-cost attribution, reproducible CropCycle profitability, cycle close validation, land-investment separation, S5/S6 integration and correction policy, the explicit input-stock boundary, full Agriculture hardening, and the final technical sector gate. Livestock remains unauthorized until GF-019 is independently reviewed, merged, and technically passes.
