# Terranex Decision Register

## Active decisions

### ADR-001 — Standalone product

Terranex is independent from Rentrix and other applications.

### ADR-002 — Local-first production runtime

Fresh browser profiles start empty. Production runtime does not create automatic demo records.

### ADR-003 — Auditable financial logic

Profitability is derived from recorded transactions. Receivables and payables remain explicit obligations. Corrections preserve history.

### ADR-004 — Conservative legacy migration

Migrate legacy records only when mappings are safe. Preserve unmappable records for audit without inventing links.

### ADR-005 — External ERP behavior is reference material only

Rebuild approved behavior as Terranex-native TypeScript. Do not add external ERP runtime dependencies.

### ADR-011 — Effective-dated project ownership

All ownership changes are append-only with temporal validity. Sum of active equity percentages
is enforced ≤100% server-side. History is queryable at any point in time.

### ADR-012 — Append-only partner ledger

Partner financial movements are recorded as immutable entries. Reversals are modeled as new
entries, not updates or deletions. Balance is calculated from the ledger.

### ADR-013 — Immutable distribution snapshots

Distributions freeze ownership percentages and allocation amounts at creation time.
Rounding is assigned to the partner with the largest share to ensure exact totals.

### ADR-014 — Separation of obligation settlements from profit distributions

Settlements reduce obligations (debts). Distributions allocate profits to partners.
These are semantically distinct and stored in separate tables.

## Adding a decision

Add a short ADR file for durable boundary changes and link it from this index.
