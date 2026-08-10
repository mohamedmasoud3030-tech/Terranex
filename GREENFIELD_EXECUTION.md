# Greenfield Execution Status

**Updated:** 2026-08-10
**Working branch:** `greenfield/foundation`

## Completed foundation

- The former Terranex product is frozen on `legacy/pre-greenfield-20260810`.
- Legacy runtime, migrations, tests, integrations, CI, agent instructions, and non-Greenfield documents are removed from the Greenfield working tree.
- The eight Greenfield documents are preserved unchanged as the product baseline.
- Agent policy now prevents accidental inheritance of legacy business logic.
- `main` is unchanged and remains a temporary safety point until a future explicitly approved replacement.

## Active gate

Phase 0 has not yet met its exit criteria. No design partner, real artifact set, or selected pilot sector is recorded in this repository.

## Next bounded batch

Create the Phase 0 commercial-validation workspace and evidence templates required to recruit and qualify three target companies and secure one paid design partner. This batch must not scaffold domain code or invent customer evidence.

## Decision rules

- Customer evidence outranks the real-estate default.
- Missing evidence is shown as missing; it is never filled with synthetic claims.
- Sensitive source documents stay outside Git. Only sanitized derivatives, schemas, mappings, and decisions may be committed.
- Product coding begins only when the Phase 0 exit decision is explicitly recorded.
