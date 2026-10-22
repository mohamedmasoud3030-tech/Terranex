# Terranex — Product

> Product definition. The full market/charter contract is
> `greenfield/01_PRODUCT_CHARTER_AND_MARKET.md`; sector models are
> `greenfield/04_SECTOR_MODELS.md`; standing decisions are in `decisions/`.

## Product

An Arabic Investment Operations OS for private investment companies. It
connects daily operations to money and control: assets and operating
cycles, suppliers and procurement, obligations and payments, bank
statements and reconciliation, revenue and collection, double-entry
financial postings, period closing, evidence, risk, and decisions.

## Customer

Private investment companies running projects across up to three sectors —
Real Estate first, Agriculture second, Livestock third (sector expansion
sequence, ADR-0012 in `decisions/`) — that need portfolio-level truth
without giving up project-level operational detail.

## Model

`Organization → Investment Portfolio → Investment Project → sector facts /
finance facts / evidence`. One project belongs to exactly one primary
sector. Financial facts are posted through the finance core with
period-close and correction controls (S6), never as free-form edits.

## Boundaries

- Implementation, deployment and customer evidence are separate claims;
  a synthetic demo is never customer evidence (see `GREENFIELD_EXECUTION.md`).
- Pending owner/business choices live only in `OPEN_BUSINESS_DECISIONS.md`.
