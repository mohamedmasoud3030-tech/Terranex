# ADR 0017 — GF-017 Agricultural Land Asset, Acquisition & Control

**Status:** Accepted  
**Date:** 2026-08-14  
**Decision owner:** Mohamed

## Context

GF-013 through GF-016 established the operating chain `Farm → Field →
CropCycle → operations → harvest output inventory`. That chain did not
represent the durable legal/economic object through which a project controls
agricultural land. A project may buy land, lease it, receive it as approved
in-kind capital, or operate it for another owner. Treating Farm as both that
investment object and an operating location would make ownership/control and
seasonal economics ambiguous.

## Decision

### 1. Land Asset ≠ Farm ≠ Field

`AgriculturalLandAsset` is the Agriculture-specific investment and legal
control object. `Farm` remains an operating location. `Field` remains an
agricultural subdivision. `CropCycle` remains a seasonal operation. The
intended chain is:

```
AgriculturalLandAsset → Farm → Field → CropCycle
```

A small append-only link connects one Farm to one Land Asset in v1. Existing
Farms are neither rewritten nor given fabricated assets; the read/UI state is
“لا يوجد أصل استثماري مرتبط” until an operator records genuine land control
and links it.

No Farm-area allocation was introduced. Therefore GF-017 does not compare Farm
and land areas or perform silent unit conversion. The land's legal/contract
area itself must be positive and uses one of the existing exact area units.

### 2. Sector-specific asset truth, not a universal Asset engine

Real Estate already owns `PropertyAsset`, `Parcel`, `PropertyAcquisition`,
typed title/possession controls, separate payment facts, and disposition. The
alignment audit found that implementation correctly separates project, asset,
parcel, acquisition agreement, title/possession evidence, payment, and
disposal. No Real Estate defect was found and no Real Estate schema or runtime
was changed.

Agriculture therefore gets `agricultural_land_assets`; it does not get a shared
`assets`, `asset_types`, plugin, repository, or universal workflow. Shared
Finance, Party and Audit remain shared.

### 3. Bounded control bases

A land record has exactly one evidence-backed v1 control basis:

- `PURCHASED` — an acquisition agreement; payment and title remain separate;
- `LEASED` — contractual operating control for a bounded/open period, never
  described as project ownership;
- `CONTRIBUTED_IN_KIND` — genuine non-cash control evidence, without creating
  fake cash;
- `MANAGED_FOR_OWNER` — authority to operate for the owner, without inferring
  project ownership or carrying value.

A counterparty Party, agreement reference, control dates, and evidence are
required for all four bases. This gives operators enough truth without an IFRS
16 engine, rent schedule, GIS, cadastral platform, or generic lifecycle.

### 4. Control, title, consideration and payment are separate

A legal/cadastral reference is descriptive evidence; it is not a title-state
engine. The command never infers title from payment or payment from a legal
reference. For purchased land, optional `agreed_consideration_minor_units` and
currency preserve contractual consideration. They do not represent amount
paid, accounting carrying amount, current valuation, or distributable cash.

An existing same-project shared-core cost obligation may be referenced only
when its amount and currency match the recorded consideration. The land command
never creates an obligation, Payment, Contribution, journal batch, or journal
line. Any future posting must use an explicitly approved Finance Core policy.

### 5. Land purchase is not CropCycle operating cost

Land normally survives many crop cycles. GF-017 has no CropCycle cost foreign
key and no automatic allocation. Purchase consideration can therefore remain a
separate land investment position. GF-019 will report it separately from
posted/attributed seasonal operating cost and will not amortize or allocate it
without approved policy.

### 6. Non-cash contribution boundary

The conceptual Greenfield model allows approved non-cash contributions, but
the implemented S1 `contributions` table and command represent a positive money
amount against a capital call, and S2 cash attribution posts it to cash. That
implementation cannot safely represent contributed land. GF-017 therefore does
not link to Contribution, fake a cash Contribution, fake a Payment, or create an
Agriculture capital ledger. It records the genuine `CONTRIBUTED_IN_KIND` basis,
Party, agreement and evidence. A shared-core non-cash contribution contract is
a future core decision.

### 7. Command, authorization and audit boundary

`create_agricultural_land_asset` and
`link_farm_to_agricultural_land_asset` are authenticated, active-member,
Agriculture-project-only, idempotent, atomic and audited. Actor identity always
comes from `auth.uid()`. Composite organization/project foreign keys prevent
cross-project links. Stable replay is checked before natural-key/link state.

Both tables use default-deny forced RLS, authenticated read-only grants,
security-invoker projections, pinned function search paths, and immutable-fact
triggers. The canonical `audit_events` table is reused; replay emits no second
audit event.

## Consequences

- Purchase, lease, in-kind and managed-for-owner land are represented without
  collapsing them to an `owned` boolean.
- The UI can truthfully distinguish the investment land object from operating
  Farm and agricultural Field.
- No pre-GF-017 Agriculture or Real Estate row is fabricated or rewritten.
- No payment/accounting/cycle-cost side effect arises from recording land.
- Lease accounting, recurring rent, title workflow, GIS, valuation,
  depreciation, disposal, universal assets, and a shared non-cash contribution
  implementation remain outside GF-017.

## Next phase

GF-018 adds Agriculture sale, physical `SALE_ISSUE`, control-transfer revenue,
receivable and collection by extending the shared S4 Finance Core patterns. It
must start only after GF-017 is merged.
