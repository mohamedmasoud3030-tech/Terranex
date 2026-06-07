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

## Adding a decision

Add a short ADR file for durable boundary changes and link it from this index.
