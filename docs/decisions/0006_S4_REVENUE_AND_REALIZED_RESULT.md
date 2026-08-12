# ADR-0006: S4 Revenue and Realized Result

## Status

Accepted for GF-006 / S4.

## Decision

- S4 supports only whole-property disposition. `property_dispositions.property_asset_id` is unique and there is no parcel, percentage, or allocation input.
- The disposition lifecycle is `DRAFT → APPROVED → CONTROL_TRANSFERRED`. Collection is not a disposition status, and paid never means sold.
- Any active member may prepare a disposition. The existing organization `OWNER` material-action boundary controls approval, control transfer, sale recognition, collection posting, and reconciliation. No roles or workflow engine are added.
- S3 property lifecycle receives only `HELD → EXITING → DISPOSED`. These transitions are explicit history commands and never post journals. `EXITING` requires an approved disposition; `DISPOSED` requires a control-transferred, recognized sale.
- Recognition requires current S3 title/possession coverage, an explicit control-transfer fact, an `EXITING` property, and an authoritative positive carrying cost. It posts one atomic four-line S2 journal batch:
  - Dr Customer Receivable / Cr Real Estate Sale Revenue
  - Dr Real Estate Cost of Sale / Cr existing Development WIP
- Carrying cost is the sum of active S2 `COST_OBLIGATION` journal debits to `DEVELOPMENT_WIP` whose obligations are classified to the whole property by S3 `property_cost_items` under `CAPITALIZABLE_WIP`. Budget, open commitment, payment, acquisition contract value, and management valuation are not carrying cost. Recognition fails rather than estimating when no such posted amount exists.
- `property_sale_carrying_cost_sources` stores immutable provenance links to the S2 journal lines and S3 classifications used at recognition. It is not a ledger or editable amount source.
- Collection is a separate, repeatable posting: Dr existing project Bank Cash / Cr Customer Receivable. Recognition-row locking and a database trigger enforce the receivable ceiling under concurrency.
- Positive bank statement lines from S2 can be reconciled to customer collections. A shared statement-line allocation row prevents one bank line from matching both an S2 supplier payment and an S4 collection under concurrency.
- Selling costs use posted S2 `PROJECT_EXPENSE` facts classified through the existing S3 property cost dimension as `SELLING`; they never enter carrying cost.
- The realized-result read model reports posted revenue, carrying cost derecognized, posted selling costs, realized result, collected cash, outstanding receivable, and latest approved management valuation as separately labelled values. Source-level drilldown exposes journal batch, line, source entity, and evidence.
- S4 sale/collection corrections and reversal orchestration are deferred to S6. The S2 generic reversal command is database-blocked for S4 batches and recognized carrying-cost source batches until that controlled correction model exists.

## Consequences

- Revenue is not cash, valuation is not revenue or realized result, and agreement/control transfer do not silently create accounting effects.
- A property cannot be sold twice, even with different request keys or concurrent calls.
- New carrying-cost postings/classifications cannot be attached to a recognized property. Posted selling expenses remain permitted and separately visible.
- Partial-property disposition, proceeds/cost allocation, distributions, period close/correction, tax, and FX remain outside S4.
